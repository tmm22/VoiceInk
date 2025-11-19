import Foundation
import AVFoundation
import SwiftUI

@MainActor
class SoundManager: ObservableObject {
    static let shared = SoundManager()

    private var startSound: AVAudioPlayer?
    private var stopSound: AVAudioPlayer?
    private var escSound: AVAudioPlayer?
    
    @Published var settings: AudioFeedbackSettings {
        didSet {
            saveSettings()
            Task {
                await reloadSounds()
            }
        }
    }
    
    private init() {
        self.settings = Self.loadSettings()
        Task(priority: .background) {
            await setupSounds()
        }
    }
    
    private static func loadSettings() -> AudioFeedbackSettings {
        if let data = UserDefaults.standard.data(forKey: AudioFeedbackSettings.userDefaultsKey),
           let settings = try? JSONDecoder().decode(AudioFeedbackSettings.self, from: data) {
            return settings
        }
        
        let legacyEnabled = UserDefaults.standard.object(forKey: "isSoundFeedbackEnabled") as? Bool ?? true
        
        var defaultSettings = AudioFeedbackSettings.default
        defaultSettings.isEnabled = legacyEnabled
        
        return defaultSettings
    }
    
    private func saveSettings() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: AudioFeedbackSettings.userDefaultsKey)
        }
    }
    
    private func setupSounds() async {
        await reloadSounds()
    }
    
    func reloadSounds() async {
        let currentSettings = settings
        
        if currentSettings.preset == .silent {
            await MainActor.run {
                startSound = nil
                stopSound = nil
                escSound = nil
            }
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
            try? await loadSounds(start: startURL, stop: stopURL, cancel: cancelURL)
        }
    }
    
    private func getBundleSoundURL(fileName: String) -> URL? {
        let components = fileName.split(separator: ".")
        guard components.count == 2 else { return nil }
        return Bundle.main.url(forResource: String(components[0]), withExtension: String(components[1]))
    }
    
    private func loadSounds(start startURL: URL, stop stopURL: URL, cancel cancelURL: URL) async throws {
        do {
            let newStartSound = try AVAudioPlayer(contentsOf: startURL)
            let newStopSound = try AVAudioPlayer(contentsOf: stopURL)
            let newCancelSound = try AVAudioPlayer(contentsOf: cancelURL)
            
            await MainActor.run {
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
        } catch {
            throw error
        }
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
    
    func setCustomSound(type: SoundType, url: URL?) {
        var customSounds = settings.customSounds ?? CustomSounds()
        
        switch type {
        case .start:
            customSounds.startPath = url?.path
        case .stop:
            customSounds.stopPath = url?.path
        case .cancel:
            customSounds.cancelPath = url?.path
        }
        
        settings.customSounds = customSounds
    }
    
    func resetToPresetDefaults() {
        settings.customSounds = nil
        settings.volumes = settings.preset.defaultVolumes
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
        case .start: return "Recording Start"
        case .stop: return "Recording Stop"
        case .cancel: return "Cancel/Escape"
        }
    }
} 
