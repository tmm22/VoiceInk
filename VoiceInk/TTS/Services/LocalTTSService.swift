import Foundation
import AVFoundation
import FluidAudioTTS

@MainActor
final class LocalTTSService: NSObject, TTSProvider {
    // MARK: - Properties
    private let voices: [Voice]
    private let systemVoices: [Voice]
    private let pocketVoiceEngine = PocketVoiceEngine()

    override init() {
        let loadedSystemVoices = LocalTTSService.loadSystemVoices()
        self.systemVoices = loadedSystemVoices
        self.voices = LocalTTSService.pocketVoices + loadedSystemVoices
        super.init()
    }

    deinit {
        let engine = pocketVoiceEngine
        Task {
            await engine.cleanup()
        }
    }

    var name: String { "Tight Ass Mode" }

    var availableVoices: [Voice] { voices }

    var defaultVoice: Voice {
        if let preferred = systemVoices.first(where: { $0.language.lowercased().hasPrefix("en") }) {
            return preferred
        }
        return systemVoices.first ?? LocalTTSService.fallbackVoice
    }

    static var pocketVoiceIDs: [String] {
        pocketVoices.map(\.id)
    }

    static func isPocketVoiceID(_ id: String) -> Bool {
        pocketVoiceIdentifier(from: id) != nil
    }

    static func pocketVoiceName(for id: String) -> String? {
        pocketVoices.first(where: { $0.id == id })?.name
    }

    static func removeCachedPocketVoiceEmbedding(for id: String) throws {
        guard let pocketVoiceID = pocketVoiceIdentifier(from: id) else { return }

        var voiceIDsToRemove = Set([pocketVoiceID])
        if let engineVoiceID = pocketVoiceEngineIdentifier(from: id) {
            voiceIDsToRemove.insert(engineVoiceID)
        }

        for voiceID in voiceIDsToRemove {
            let cacheURL = cachedPocketVoiceEmbeddingURL(for: voiceID)
            if FileManager.default.fileExists(atPath: cacheURL.path) {
                try FileManager.default.removeItem(at: cacheURL)
            }
        }
    }

    func hasValidAPIKey() -> Bool { true }

    func synthesizeSpeech(text: String, voice: Voice, settings: AudioSettings) async throws -> Data {
        guard settings.format == .wav else {
            throw TTSError.unsupportedFormat
        }

        if let pocketVoiceID = LocalTTSService.pocketVoiceEngineIdentifier(from: voice.id) {
            return try await synthesizePocketSpeech(
                text: text,
                pocketVoiceID: pocketVoiceID,
                settings: settings
            )
        }

        return try await synthesizeSystemSpeech(text: text, voice: voice, settings: settings)
    }
}

// MARK: - Synthesis
private extension LocalTTSService {
    func synthesizePocketSpeech(text: String,
                                pocketVoiceID: String,
                                settings: AudioSettings) async throws -> Data {
        let clampedSpeed = Float(min(max(settings.speed, 0.5), 2.0))

        do {
            return try await pocketVoiceEngine.synthesize(
                text: text,
                voiceID: pocketVoiceID,
                speed: clampedSpeed
            )
        } catch let error as TTSError {
            throw error
        } catch {
            AppLogger.audio.error("Pocket TTS synthesis failed: \(AppLogger.errorMetadata(error), privacy: .public)")
            throw TTSError.apiError(error.localizedDescription)
        }
    }

    func synthesizeSystemSpeech(text: String,
                                voice: Voice,
                                settings: AudioSettings) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            let utterance = AVSpeechUtterance(string: text)
            guard let systemVoice = LocalTTSService.resolveVoice(identifier: voice.id, language: voice.language) else {
                continuation.resume(throwing: TTSError.invalidVoice)
                return
            }

            utterance.voice = systemVoice

            let rateMultiplier = min(max(settings.speed, 0.5), 2.0)
            let baseRate = AVSpeechUtteranceDefaultSpeechRate
            let minimumRate = AVSpeechUtteranceMinimumSpeechRate
            let maximumRate = AVSpeechUtteranceMaximumSpeechRate
            let proposedRate = baseRate * Float(rateMultiplier)
            utterance.rate = min(max(proposedRate, minimumRate), maximumRate)
            utterance.pitchMultiplier = Float(min(max(settings.pitch, 0.5), 2.0))
            utterance.volume = Float(min(max(settings.volume, 0.0), 1.0))

            let synthesizer = AVSpeechSynthesizer()
            let destinationURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("wav")

            var audioFile: AVAudioFile?
            var hasCompleted = false

            synthesizer.write(utterance) { buffer in
                guard !hasCompleted else { return }

                do {
                    guard let pcmBuffer = buffer as? AVAudioPCMBuffer else {
                        return
                    }

                    if pcmBuffer.frameLength == 0 {
                        hasCompleted = true
                        audioFile = nil
                        Task {
                            do {
                                let data = try await AudioFileLoader.loadData(from: destinationURL)
                                try? FileManager.default.removeItem(at: destinationURL)
                                continuation.resume(returning: data)
                            } catch {
                                // Best-effort cleanup; temp file may have already been removed.
                                try? FileManager.default.removeItem(at: destinationURL)
                                continuation.resume(throwing: TTSError.apiError(error.localizedDescription))
                            }
                        }
                        return
                    }

                    if audioFile == nil {
                        audioFile = try AVAudioFile(
                            forWriting: destinationURL,
                            settings: pcmBuffer.format.settings
                        )
                    }

                    try audioFile?.write(from: pcmBuffer)
                } catch {
                    hasCompleted = true
                    synthesizer.stopSpeaking(at: .immediate)
                    // Best-effort cleanup; temp file may have already been removed.
                    try? FileManager.default.removeItem(at: destinationURL)
                    continuation.resume(throwing: TTSError.apiError(error.localizedDescription))
                }
            }
        }
    }
}

// MARK: - Voice Helpers
private extension LocalTTSService {
    static let pocketVoicePrefix = "pocket-tts:"
    static let legacyPocketToKokoroVoiceMap: [String: String] = [
        "alba": "af_heart",
        "azelma": "af_bella",
        "cosette": "af_nova",
        "javert": "am_michael"
    ]

    static let pocketVoices: [Voice] = [
        Voice(
            id: pocketVoicePrefix + "alba",
            name: "Pocket TTS - Alba",
            language: "en-US",
            gender: .female,
            provider: .tightAss,
            previewURL: nil
        ),
        Voice(
            id: pocketVoicePrefix + "azelma",
            name: "Pocket TTS - Azelma",
            language: "en-US",
            gender: .female,
            provider: .tightAss,
            previewURL: nil
        ),
        Voice(
            id: pocketVoicePrefix + "cosette",
            name: "Pocket TTS - Cosette",
            language: "en-US",
            gender: .female,
            provider: .tightAss,
            previewURL: nil
        ),
        Voice(
            id: pocketVoicePrefix + "javert",
            name: "Pocket TTS - Javert",
            language: "en-US",
            gender: .male,
            provider: .tightAss,
            previewURL: nil
        )
    ]

    static func pocketVoiceIdentifier(from id: String) -> String? {
        guard id.hasPrefix(pocketVoicePrefix) else { return nil }
        let value = String(id.dropFirst(pocketVoicePrefix.count))
        return value.isEmpty ? nil : value
    }

    static func pocketVoiceEngineIdentifier(from id: String) -> String? {
        guard let voiceID = pocketVoiceIdentifier(from: id) else { return nil }
        return legacyPocketToKokoroVoiceMap[voiceID] ?? voiceID
    }

    static func cachedPocketVoiceEmbeddingURL(for voiceID: String) -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache")
            .appendingPathComponent("fluidaudio")
            .appendingPathComponent("Models")
            .appendingPathComponent("kokoro")
            .appendingPathComponent("voices")
            .appendingPathComponent("\(voiceID).json")
    }

    @MainActor
    static func loadSystemVoices() -> [Voice] {
        // Since LocalTTSService is @MainActor, this runs on the main thread.
        let systemVoices = AVSpeechSynthesisVoice.speechVoices()

        let mapped = systemVoices
            .sorted { lhs, rhs in
                if lhs.language == rhs.language {
                    return lhs.name < rhs.name
                }
                return lhs.language < rhs.language
            }
            .map { voice in
                Voice(
                    id: voice.identifier,
                    name: voice.name,
                    language: voice.language,
                    gender: mapGender(from: voice),
                    provider: .tightAss,
                    previewURL: nil
                )
            }

        if mapped.isEmpty {
            return [fallbackVoice]
        }

        return mapped
    }

    static func mapGender(from voice: AVSpeechSynthesisVoice) -> Voice.Gender {
        switch voice.gender {
        case .male:
            return .male
        case .female:
            return .female
        default:
            return .neutral
        }
    }

    static func resolveVoice(identifier: String, language: String) -> AVSpeechSynthesisVoice? {
        if let match = AVSpeechSynthesisVoice(identifier: identifier) {
            return match
        }
        return AVSpeechSynthesisVoice(language: language)
    }

    static var fallbackVoice: Voice {
        Voice(
            id: "com.apple.speech.synthesis.voice.samantha",
            name: "Samantha",
            language: "en-US",
            gender: .female,
            provider: .tightAss,
            previewURL: nil
        )
    }
}

private actor PocketVoiceEngine {
    private var manager: TtSManager?
    private var initializedVoices = Set<String>()
    private let fallbackVoiceID = TtsConstants.recommendedVoice

    func synthesize(text: String, voiceID: String, speed: Float) async throws -> Data {
        let resolvedManager: TtSManager
        if let manager {
            resolvedManager = manager
        } else {
            let created = TtSManager(defaultVoice: voiceID)
            manager = created
            resolvedManager = created
        }

        let requestedVoiceID = voiceID.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedVoiceID = requestedVoiceID.isEmpty ? fallbackVoiceID : requestedVoiceID

        if !resolvedManager.isAvailable {
            do {
                try await resolvedManager.initialize(preloadVoices: Set([normalizedVoiceID]))
                initializedVoices = Set([normalizedVoiceID])
            } catch {
                guard normalizedVoiceID != fallbackVoiceID else {
                    throw error
                }
                AppLogger.audio.warning(
                    "Pocket TTS voice \(normalizedVoiceID) unavailable (\(error.localizedDescription)); falling back to \(self.fallbackVoiceID)"
                )
                try await resolvedManager.initialize(preloadVoices: Set([fallbackVoiceID]))
                initializedVoices = Set([fallbackVoiceID])
            }
        } else if !initializedVoices.contains(normalizedVoiceID) {
            do {
                try await resolvedManager.setDefaultVoice(normalizedVoiceID)
                initializedVoices.insert(normalizedVoiceID)
            } catch {
                guard normalizedVoiceID != fallbackVoiceID else {
                    throw error
                }
                AppLogger.audio.warning(
                    "Pocket TTS voice \(normalizedVoiceID) unavailable (\(error.localizedDescription)); falling back to \(self.fallbackVoiceID)"
                )
                try await resolvedManager.setDefaultVoice(fallbackVoiceID)
                initializedVoices.insert(fallbackVoiceID)
            }
        }

        let synthesisVoice = initializedVoices.contains(normalizedVoiceID) ? normalizedVoiceID : fallbackVoiceID
        return try await resolvedManager.synthesize(
            text: text,
            voice: synthesisVoice,
            voiceSpeed: speed
        )
    }

    func cleanup() {
        manager?.cleanup()
        manager = nil
        initializedVoices.removeAll()
    }
}
