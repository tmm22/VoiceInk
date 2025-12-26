import Foundation
import os

#if canImport(whisper)
import whisper
#endif

/// Thread-safe wrapper around WhisperContext that provides memory management and reference counting
@MainActor
class WhisperContextWrapper {
    private let context: WhisperContext
    private let modelName: String
    private var referenceCount: Int = 0
    private let logger = Logger(subsystem: "com.tmm22.voicelinkcommunity", category: "WhisperContextWrapper")

    /// Initialize with a WhisperContext
    init(context: WhisperContext, modelName: String) {
        self.context = context
        self.modelName = modelName
        logger.info("Created WhisperContextWrapper for model: \(modelName)")
    }

    deinit {
        logger.info("Deinitializing WhisperContextWrapper for model: \(self.modelName)")
        Task { [context] in
            await context.releaseResources()
        }
    }

    /// Increment reference count
    func retain() {
        referenceCount += 1
        logger.debug("Retained context for \(self.modelName), count: \(self.referenceCount)")
    }

    /// Decrement reference count
    func release() {
        referenceCount = max(0, referenceCount - 1)
        logger.debug("Released context for \(self.modelName), count: \(self.referenceCount)")
    }

    /// Get current reference count
    var refCount: Int {
        referenceCount
    }

    /// Check if context is still referenced
    var isReferenced: Bool {
        referenceCount > 0
    }

    /// Get the model name
    var name: String {
        modelName
    }

    /// Perform transcription with the wrapped context
    func transcribe(samples: [Float]) async -> String? {
        logger.debug("Starting transcription for model: \(self.modelName)")

        // Set prompt if configured
        let currentPrompt = AppSettings.TranscriptionSettings.prompt ?? ""
        await context.setPrompt(currentPrompt)

        // Perform transcription
        let success = await context.fullTranscribe(samples: samples)

        guard success else {
            logger.error("Transcription failed for model: \(self.modelName)")
            return nil
        }

        let transcription = await context.getTranscription()
        logger.debug("Transcription completed for model: \(self.modelName)")
        return transcription
    }

    /// Get access to the underlying WhisperContext for advanced operations
    func withContext<T>(_ operation: (WhisperContext) async throws -> T) async throws -> T {
        try await operation(context)
    }
}