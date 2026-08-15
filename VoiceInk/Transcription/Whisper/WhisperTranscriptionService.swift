import AVFoundation
import Foundation
import os

class WhisperTranscriptionService: TranscriptionService {
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "WhisperTranscriptionService")
    private let modelsDirectory: URL
    private weak var modelProvider: (any WhisperModelProvider)?

    init(modelsDirectory: URL, modelProvider: (any WhisperModelProvider)? = nil) {
        self.modelsDirectory = modelsDirectory
        self.modelProvider = modelProvider
    }

    func transcribe(audioURL: URL, model: any TranscriptionModel, context: TranscriptionRequestContext) async throws
        -> String
    {
        guard model.provider == .whisper else {
            throw VoiceInkEngineError.modelLoadFailed
        }

        logger.notice("Initiating local transcription for model: \(model.displayName, privacy: .public)")

        let resolvedURL = await modelProvider?.availableModels.first(where: { $0.name == model.name })?.url
            ?? modelsDirectory.appendingPathComponent(model.name).appendingPathExtension("bin")
        guard FileManager.default.fileExists(atPath: resolvedURL.path) else {
            logger.error("Model file not found for \(model.name, privacy: .public)")
            throw VoiceInkEngineError.modelLoadFailed
        }

        return try await WhisperContextManager.shared.performInference(
            modelName: model.name,
            modelURL: resolvedURL,
            audioURL: audioURL,
            language: context.language,
            prompt: context.prompt
        )
    }
}
