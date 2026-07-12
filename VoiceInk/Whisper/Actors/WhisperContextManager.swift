import Foundation
import AVFoundation
import os

#if canImport(whisper)
import whisper
#endif

/// Global actor for Whisper context management operations
@globalActor
actor WhisperContextManager {
    private final class ContextLoad: @unchecked Sendable {
        let task: Task<WhisperContext, Error>
        var isInvalidated = false
        var didReleaseResult = false

        init(modelURL: URL) {
            task = Task {
                try await WhisperContext.createContext(path: modelURL.path)
            }
        }
    }

    static let shared = WhisperContextManager()

    private var contexts: [String: WhisperContext] = [:]
    private var contextLoads: [String: ContextLoad] = [:]
    private var activeInferenceCounts: [String: Int] = [:]
    private var retiringContexts: [String: [WhisperContext]] = [:]
    private let logger = Logger(subsystem: "com.tmm22.voicelinkcommunity", category: "WhisperContextManager")

    private init() {}

    /// Load a Whisper context for the given model
    func loadContext(for modelName: String, modelURL: URL) async throws -> WhisperContext {
        // Check if already loaded
        if let existingContext = contexts[modelName] {
            logger.info("Using existing context for model: \(modelName)")
            return existingContext
        }

        let operation: ContextLoad
        if let existingOperation = contextLoads[modelName] {
            operation = existingOperation
        } else {
            operation = ContextLoad(modelURL: modelURL)
            contextLoads[modelName] = operation
        }

        do {
            logger.info("Loading Whisper context for model: \(modelName)")
            let context = try await operation.task.value

            if let existingContext = contexts[modelName], existingContext === context {
                return existingContext
            }

            guard contextLoads[modelName] === operation, !operation.isInvalidated else {
                if !operation.didReleaseResult {
                    operation.didReleaseResult = true
                    await context.releaseResources()
                }
                throw CancellationError()
            }

            contexts[modelName] = context
            contextLoads.removeValue(forKey: modelName)
            logger.info("Successfully loaded context for model: \(modelName)")
            return context
        } catch {
            if contextLoads[modelName] === operation {
                contextLoads.removeValue(forKey: modelName)
            }
            logger.error("Failed to load context for model \(modelName): \(AppLogger.errorMetadata(error), privacy: .public)")
            throw error
        }
    }

    /// Unload a Whisper context
    func unloadContext(for modelName: String) async {
        if let operation = contextLoads.removeValue(forKey: modelName) {
            operation.isInvalidated = true
            operation.task.cancel()
        }
        await retireContext(for: modelName)
    }

    /// Perform inference with the specified model
    func performInference(modelName: String, audioURL: URL) async throws -> String {
        guard let context = contexts[modelName] else {
            logger.error("No context loaded for model: \(modelName)")
            throw WhisperContextError.contextNotLoaded
        }

        logger.info("Starting inference for model: \(modelName)")
        activeInferenceCounts[modelName, default: 0] += 1

        do {
            let samples = try readAudioSamples(audioURL)
            let currentPrompt = AppSettings.TranscriptionSettings.prompt ?? ""
            await context.setPrompt(currentPrompt)
            let success = await context.fullTranscribe(samples: samples)

            guard success else {
                throw WhisperContextError.transcriptionFailed
            }

            let transcription = await context.getTranscription()
            await finishInference(for: modelName)
            logger.info("Inference completed for model: \(modelName)")
            return transcription
        } catch {
            await finishInference(for: modelName)
            logger.error("Whisper transcription failed for model: \(modelName)")
            throw error
        }
    }

    /// Get available contexts
    func availableContexts() -> [String] {
        Array(contexts.keys)
    }

    /// Check if a context is loaded for the given model
    func isContextLoaded(for modelName: String) -> Bool {
        contexts[modelName] != nil
    }

    func updatePrompt(_ prompt: String, for modelName: String) async {
        await contexts[modelName]?.setPrompt(prompt)
    }

    /// Unload all contexts
    func unloadAllContexts() async {
        logger.info("Unloading all Whisper contexts")
        let loading = contextLoads.values
        contextLoads.removeAll()
        loading.forEach {
            $0.isInvalidated = true
            $0.task.cancel()
        }
        for modelName in Array(contexts.keys) {
            await retireContext(for: modelName)
        }
    }

    private func retireContext(for modelName: String) async {
        guard let context = contexts.removeValue(forKey: modelName) else { return }
        if activeInferenceCounts[modelName, default: 0] > 0 {
            retiringContexts[modelName, default: []].append(context)
        } else {
            await context.releaseResources()
            logger.info("Unloaded context for model: \(modelName)")
        }
    }

    private func finishInference(for modelName: String) async {
        let remaining = max(0, activeInferenceCounts[modelName, default: 1] - 1)
        if remaining == 0 {
            activeInferenceCounts.removeValue(forKey: modelName)
            for context in retiringContexts.removeValue(forKey: modelName) ?? [] {
                await context.releaseResources()
                logger.info("Unloaded retired context for model: \(modelName)")
            }
        } else {
            activeInferenceCounts[modelName] = remaining
        }
    }

    private func readAudioSamples(_ url: URL) throws -> [Float] {
        try AudioSampleReader.readPCM16LE(from: url)
    }
}

// MARK: - Error Types
enum WhisperContextError: LocalizedError {
    case contextNotLoaded
    case transcriptionFailed

    var errorDescription: String? {
        switch self {
        case .contextNotLoaded:
            return "Whisper context is not loaded"
        case .transcriptionFailed:
            return "Whisper transcription failed"
        }
    }
}
