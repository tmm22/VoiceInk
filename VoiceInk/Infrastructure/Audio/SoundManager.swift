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
    private var loadSequencer = SoundLoadSequencer()
    
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
        let generation = loadSequencer.beginLoad()
        
        if currentSettings.preset == .silent {
            finishLoad(generation, outcome: .clearPlayers)
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
        
        guard let startURL = startURL,
              let stopURL = stopURL,
              let cancelURL = cancelURL else {
            finishLoad(generation, outcome: .keepExistingPlayers)
            return
        }

        // Parsing the files and priming the output hardware takes tens of milliseconds, so it
        // runs off the main actor, which stays free while this is suspended. The task is created
        // here, with its own priority, so it does not inherit a background-priority caller.
        let load = Task.detached(priority: .userInitiated) {
            SoundPlayerLoader.loadPreparedPlayers(start: startURL, stop: stopURL, cancel: cancelURL)
        }
        switch await load.value {
        case .success(let players):
            finishLoad(generation, outcome: .install(players))
        case .failure(let error):
            AppLogger.audio.error(
                "Failed to load audio feedback sounds: \(AppLogger.errorMetadata(error), privacy: .public)"
            )
            finishLoad(generation, outcome: .keepExistingPlayers)
        }
    }

    private func finishLoad(_ generation: UInt64, outcome: SoundLoadOutcome) {
        let changesPlayers: Bool
        switch outcome {
        case .clearPlayers, .install: changesPlayers = true
        case .keepExistingPlayers: changesPlayers = false
        }

        let completion = loadSequencer.completeLoad(generation, changesPlayers: changesPlayers)
        if completion.shouldApply {
            switch outcome {
            case .clearPlayers:
                startSound = nil
                stopSound = nil
                escSound = nil
            case .install(let players):
                startSound = players.start
                stopSound = players.stop
                escSound = players.cancel

                startSound?.volume = settings.volumes.start
                stopSound?.volume = settings.volumes.stop
                escSound?.volume = settings.volumes.cancel
            case .keepExistingPlayers:
                break
            }
        }

        for cue in completion.cuesToPlay {
            play(cue)
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
    
    func playStartSound() {
        guard settings.isEnabled, settings.preset != .silent else { return }
        playOrDefer(.start)
    }

    func playStopSound() {
        guard settings.isEnabled, settings.preset != .silent else { return }
        playOrDefer(.stop)
    }
    
    func playEscSound() {
        guard settings.isEnabled, settings.preset != .silent else { return }
        playOrDefer(.cancel)
    }
    
    func previewSound(type: SoundType) {
        guard settings.preset != .silent else { return }
        playOrDefer(type)
    }

    /// A cue requested while a reload is in flight plays as soon as that reload lands. When
    /// reloads ran synchronously the main actor was blocked for that window, so the cue came out
    /// of the reloaded players at the same moment.
    private func playOrDefer(_ cue: SoundType) {
        guard !loadSequencer.deferCueIfLoading(cue) else { return }
        play(cue)
    }

    private func play(_ cue: SoundType) {
        switch cue {
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

/// Bookkeeping for feedback-sound reloads whose players are built off the main actor.
///
/// Reloads used to run synchronously on the main actor: they took effect in the order they were
/// requested, and a cue requested after a reload came out of that reload's players. Both
/// properties are kept now that a reload finishes later than it starts:
/// - a result is applied only when no newer result has been applied, so a later reload wins over
///   an older in-flight one, while a newer reload that changes nothing leaves the older result in place;
/// - a cue requested while any reload is in flight is handed back when the last one finishes.
struct SoundLoadSequencer {
    struct Completion: Equatable {
        /// Whether this reload's result should replace the installed players.
        let shouldApply: Bool
        /// Cues that were waiting on in-flight reloads, in the order they were requested.
        let cuesToPlay: [SoundType]
    }

    private var latestGeneration: UInt64 = 0
    private var appliedGeneration: UInt64 = 0
    private var loadsInFlight = 0
    private var deferredCues: [SoundType] = []

    /// Registers a reload and returns its generation. Later reloads get larger generations.
    mutating func beginLoad() -> UInt64 {
        latestGeneration &+= 1
        loadsInFlight += 1
        return latestGeneration
    }

    /// Finishes the reload started with `generation`.
    /// - Parameter changesPlayers: false when the reload leaves the installed players alone
    ///   (a sound file was missing or unreadable), which must not block an older reload's result.
    mutating func completeLoad(_ generation: UInt64, changesPlayers: Bool) -> Completion {
        let shouldApply = changesPlayers && generation > appliedGeneration
        if shouldApply {
            appliedGeneration = generation
        }

        loadsInFlight = max(0, loadsInFlight - 1)
        guard loadsInFlight == 0 else {
            return Completion(shouldApply: shouldApply, cuesToPlay: [])
        }

        let cuesToPlay = deferredCues
        deferredCues.removeAll()
        return Completion(shouldApply: shouldApply, cuesToPlay: cuesToPlay)
    }

    /// Queues `cue` when a reload is in flight and returns true; returns false when the caller
    /// should play it immediately. A cue already waiting is not queued twice.
    mutating func deferCueIfLoading(_ cue: SoundType) -> Bool {
        guard loadsInFlight > 0 else { return false }
        if !deferredCues.contains(cue) {
            deferredCues.append(cue)
        }
        return true
    }
}

/// What a finished reload does to the installed players.
private enum SoundLoadOutcome {
    case clearPlayers
    case keepExistingPlayers
    case install(PreparedSoundPlayers)
}

/// Players built and primed off the main actor.
///
/// `AVAudioPlayer` is not `Sendable`. The loading task creates the players, hands them to the main
/// actor once and never touches them again, so no player is used from two threads at a time.
private struct PreparedSoundPlayers: @unchecked Sendable {
    let start: AVAudioPlayer
    let stop: AVAudioPlayer
    let cancel: AVAudioPlayer
}

private enum SoundPlayerLoader {
    /// Builds all three players or none: one unreadable file fails the whole load, as it did when
    /// the players were built on the main actor.
    static func loadPreparedPlayers(start: URL, stop: URL, cancel: URL) -> Result<PreparedSoundPlayers, Error> {
        Result {
            let players = PreparedSoundPlayers(
                start: try AVAudioPlayer(contentsOf: start),
                stop: try AVAudioPlayer(contentsOf: stop),
                cancel: try AVAudioPlayer(contentsOf: cancel)
            )
            players.start.prepareToPlay()
            players.stop.prepareToPlay()
            players.cancel.prepareToPlay()
            return players
        }
    }
}
