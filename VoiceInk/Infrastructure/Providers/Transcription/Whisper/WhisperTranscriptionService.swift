import AVFoundation
import Foundation
import os

class WhisperTranscriptionService: TranscriptionService {
    private let logger = Logger(subsystem: AppLogger.subsystem, category: "WhisperTranscriptionService")
    private let modelsDirectory: URL
    private weak var modelProvider: (any WhisperModelProvider)?

    init(modelsDirectory: URL, modelProvider: (any WhisperModelProvider)? = nil) {
        self.modelsDirectory = modelsDirectory
        self.modelProvider = modelProvider
    }

    /// Loads (or reuses) the Whisper context for `model` without running inference.
    ///
    /// Context creation is where whisper.cpp reads the weights, initialises the Metal backend,
    /// compiles its kernels and allocates the encoder/decoder graph buffers, so this alone removes
    /// the multi-second first-transcription stall. No fake inference is performed on purpose.
    func prepareModel(_ model: any TranscriptionModel) async throws {
        let resolvedURL = try await resolveModelURL(for: model)
        _ = try await WhisperContextManager.shared.loadContext(for: model.name, modelURL: resolvedURL)
    }

    func transcribe(audioURL: URL, model: any TranscriptionModel, context: TranscriptionRequestContext) async throws
        -> String
    {
        logger.notice("Initiating local transcription for model: \(model.displayName, privacy: .public)")

        let resolvedURL = try await resolveModelURL(for: model)

        return try await WhisperContextManager.shared.performInference(
            modelName: model.name,
            modelURL: resolvedURL,
            audioURL: audioURL,
            language: context.language,
            prompt: context.prompt
        )
    }

    /// Resolves the on-disk model file, preferring the provider's discovered models and falling
    /// back to `<modelsDirectory>/<name>.bin`.
    private func resolveModelURL(for model: any TranscriptionModel) async throws -> URL {
        guard model.provider == .whisper else {
            throw VoiceInkEngineError.modelLoadFailed
        }

        let resolvedURL = await modelProvider?.availableModels.first(where: { $0.name == model.name })?.url
            ?? modelsDirectory.appendingPathComponent(model.name).appendingPathExtension("bin")
        guard FileManager.default.fileExists(atPath: resolvedURL.path) else {
            logger.error("Model file not found for \(model.name, privacy: .public)")
            throw VoiceInkEngineError.modelLoadFailed
        }
        return resolvedURL
    }
}
