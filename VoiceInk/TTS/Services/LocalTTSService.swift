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

    func hasValidAPIKey() -> Bool { true }

    func synthesizeSpeech(text: String, voice: Voice, settings: AudioSettings) async throws -> Data {
        guard settings.format == .wav else {
            throw TTSError.unsupportedFormat
        }

        if let pocketVoiceID = LocalTTSService.pocketVoiceIdentifier(from: voice.id) {
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
            AppLogger.audio.error("Pocket TTS synthesis failed for \(pocketVoiceID): \(error.localizedDescription)")
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

    func synthesize(text: String, voiceID: String, speed: Float) async throws -> Data {
        let resolvedManager: TtSManager
        if let manager {
            resolvedManager = manager
        } else {
            let created = TtSManager(defaultVoice: voiceID)
            manager = created
            resolvedManager = created
        }

        if !resolvedManager.isAvailable {
            try await resolvedManager.initialize(preloadVoices: Set([voiceID]))
            initializedVoices = Set([voiceID])
        } else if !initializedVoices.contains(voiceID) {
            try await resolvedManager.setDefaultVoice(voiceID)
            initializedVoices.insert(voiceID)
        }

        return try await resolvedManager.synthesize(
            text: text,
            voice: voiceID,
            voiceSpeed: speed
        )
    }

    func cleanup() {
        manager?.cleanup()
        manager = nil
        initializedVoices.removeAll()
    }
}
