import Foundation
import AVFoundation
import SwiftUI

@MainActor
class SoundManager: ObservableObject {
    static let shared = SoundManager()

    private var startSound: AVAudioPlayer?
    private var stopSound: AVAudioPlayer?
    private var escSound: AVAudioPlayer?
    private let soundFileStore = SoundFileStore()
    
    @Published var settings: AudioFeedbackSettings {
        didSet {
            saveSettings()
            Task { [weak self] in
                await self?.reloadSounds()
            }
        }
    }
    
    private init() {
        self.settings = Self.loadSettings()
        Task(priority: .background) { [weak self] in
            await self?.setupSounds()
        }
    }
    
    private static func loadSettings() -> AudioFeedbackSettings {
        if let data = AppSettings.Audio.audioFeedbackSettingsData,
           let settings = try? JSONDecoder().decode(AudioFeedbackSettings.self, from: data) {
            return settings
        }
        
        let legacyEnabled = AppSettings.Audio.legacySoundFeedbackEnabled
        
        var defaultSettings = AudioFeedbackSettings.default
        defaultSettings.isEnabled = legacyEnabled
        
        return defaultSettings
    }
    
    private func saveSettings() {
        do {
            let data = try JSONEncoder().encode(settings)
            AppSettings.Audio.audioFeedbackSettingsData = data
        } catch {
            AppLogger.storage.error(
                "Failed to save audio feedback settings: \(AppLogger.errorMetadata(error), privacy: .public)"
            )
        }
    }
    
    private func setupSounds() async {
        await reloadSounds()
    }
    
    func reloadSounds() async {
        let currentSettings = settings
        
        if currentSettings.preset == .silent {
            startSound = nil
            stopSound = nil
            escSound = nil
            return
        }
        
        var startURL: URL?
        var stopURL: URL?
        var cancelURL: URL?
        
        if let customSounds = currentSettings.customSounds {
            if let path = customSounds.startPath {
                startURL = URL(fileURLWithPath: path)
            }
            if let path = customSounds.stopPath {
                stopURL = URL(fileURLWithPath: path)
            }
            if let path = customSounds.cancelPath {
                cancelURL = URL(fileURLWithPath: path)
            }
        }
        
        let soundFiles = currentSettings.preset.soundFiles
        
        if startURL == nil, let fileName = soundFiles.start {
            startURL = getBundleSoundURL(fileName: fileName)
        }
        if stopURL == nil, let fileName = soundFiles.stop {
            stopURL = getBundleSoundURL(fileName: fileName)
        }
        if cancelURL == nil, let fileName = soundFiles.cancel {
            cancelURL = getBundleSoundURL(fileName: fileName)
        }
        
        if let startURL = startURL,
           let stopURL = stopURL,
           let cancelURL = cancelURL {
            do {
                try loadSounds(start: startURL, stop: stopURL, cancel: cancelURL)
            } catch {
                AppLogger.audio.error(
                    "Failed to load audio feedback sounds: \(AppLogger.errorMetadata(error), privacy: .public)"
                )
            }
        }
    }
    
    private func getBundleSoundURL(fileName: String) -> URL? {
        let components = fileName.split(separator: ".")
        guard components.count == 2 else { return nil }
        return Bundle.main.url(forResource: String(components[0]), withExtension: String(components[1]))
            ?? Bundle.main.url(
                forResource: String(components[0]),
                withExtension: String(components[1]),
                subdirectory: "Sounds"
            )
    }
    
    private func loadSounds(start startURL: URL, stop stopURL: URL, cancel cancelURL: URL) throws {
        let newStartSound = try AVAudioPlayer(contentsOf: startURL)
        let newStopSound = try AVAudioPlayer(contentsOf: stopURL)
        let newCancelSound = try AVAudioPlayer(contentsOf: cancelURL)
            
            self.startSound = newStartSound
            self.stopSound = newStopSound
            self.escSound = newCancelSound
            
            startSound?.prepareToPlay()
            stopSound?.prepareToPlay()
            escSound?.prepareToPlay()
            
            startSound?.volume = settings.volumes.start
            stopSound?.volume = settings.volumes.stop
            escSound?.volume = settings.volumes.cancel
    }

    func playStartSound() {
        guard settings.isEnabled, settings.preset != .silent else { return }
        startSound?.volume = settings.volumes.start
        startSound?.play()
    }

    func playStopSound() {
        guard settings.isEnabled, settings.preset != .silent else { return }
        stopSound?.volume = settings.volumes.stop
        stopSound?.play()
    }
    
    func playEscSound() {
        guard settings.isEnabled, settings.preset != .silent else { return }
        escSound?.volume = settings.volumes.cancel
        escSound?.play()
    }
    
    func previewSound(type: SoundType) {
        guard settings.preset != .silent else { return }
        switch type {
        case .start:
            startSound?.volume = settings.volumes.start
            startSound?.play()
        case .stop:
            stopSound?.volume = settings.volumes.stop
            stopSound?.play()
        case .cancel:
            escSound?.volume = settings.volumes.cancel
            escSound?.play()
        }
    }
    
    func setCustomSound(type: SoundType, url: URL?) async throws {
        var customSounds = settings.customSounds ?? CustomSounds()
        let previousPath = type.path(in: customSounds)

        let storedPath: String?
        if let url {
            storedPath = try await soundFileStore.importSound(from: url, type: type).path
        } else {
            storedPath = nil
        }
        
        switch type {
        case .start:
            customSounds.startPath = storedPath
        case .stop:
            customSounds.stopPath = storedPath
        case .cancel:
            customSounds.cancelPath = storedPath
        }
        
        settings.customSounds = customSounds
        if let previousPath, previousPath != storedPath {
            await soundFileStore.removeStoredSound(at: URL(fileURLWithPath: previousPath))
        }
    }
    
    func resetToPresetDefaults() {
        let storedURLs = settings.customSounds?.paths.map(URL.init(fileURLWithPath:)) ?? []
        settings.customSounds = nil
        settings.volumes = settings.preset.defaultVolumes
        let store = soundFileStore
        Task {
            for url in storedURLs {
                await store.removeStoredSound(at: url)
            }
        }
    }
    
    var isEnabled: Bool {
        get { settings.isEnabled }
        set {
            settings.isEnabled = newValue
        }
    }
}

enum SoundType {
    case start
    case stop
    case cancel
    
    var displayName: String {
        switch self {
        case .start: return String(localized: "Recording Start")
        case .stop: return String(localized: "Recording Stop")
        case .cancel: return String(localized: "Cancel/Escape")
        }
    }

    var storageName: String {
        switch self {
        case .start: return "start"
        case .stop: return "stop"
        case .cancel: return "cancel"
        }
    }

    func path(in sounds: CustomSounds) -> String? {
        switch self {
        case .start: return sounds.startPath
        case .stop: return sounds.stopPath
        case .cancel: return sounds.cancelPath
        }
    }
}

private extension CustomSounds {
    var paths: [String] {
        [startPath, stopPath, cancelPath].compactMap { $0 }
    }
}
