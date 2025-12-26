import Foundation
import AVFoundation
import os

#if canImport(whisper)
import whisper
#endif

/// Global actor for Whisper context management operations
@globalActor
actor WhisperContextManager {
    static let shared = WhisperContextManager()

    private var contexts: [String: WhisperContext] = [:]
    private var loadingContexts: Set<String> = []
    private let logger = Logger(subsystem: "com.tmm22.voicelinkcommunity", category: "WhisperContextManager")

    private init() {}

    /// Load a Whisper context for the given model
    func loadContext(for modelName: String, modelURL: URL) async throws -> WhisperContext {
        // Check if already loaded
        if let existingContext = contexts[modelName] {
            logger.info("Using existing context for model: \(modelName)")
            return existingContext
        }

        // Check if currently loading
        guard !loadingContexts.contains(modelName) else {
            logger.warning("Context for model \(modelName) is already being loaded")
            throw WhisperContextError.contextLoadingInProgress
        }

        // Mark as loading
        loadingContexts.insert(modelName)

        do {
            logger.info("Loading Whisper context for model: \(modelName)")
            let context = try await WhisperContext.createContext(path: modelURL.path)
            contexts[modelName] = context
            logger.info("Successfully loaded context for model: \(modelName)")
            return context
        } catch {
            logger.error("Failed to load context for model \(modelName): \(error.localizedDescription)")
            throw error
        }
    }

    /// Unload a Whisper context
    func unloadContext(for modelName: String) async {
        if let context = contexts.removeValue(forKey: modelName) {
            logger.info("Unloading context for model: \(modelName)")
            await context.releaseResources()
        }
        loadingContexts.remove(modelName)
    }

    /// Perform inference with the specified model
    func performInference(modelName: String, audioURL: URL) async throws -> String {
        guard let context = contexts[modelName] else {
            logger.error("No context loaded for model: \(modelName)")
            throw WhisperContextError.contextNotLoaded
        }

        logger.info("Starting inference for model: \(modelName)")

        // Read audio samples
        let samples = try readAudioSamples(audioURL)

        // Set prompt if configured
        let currentPrompt = AppSettings.TranscriptionSettings.prompt ?? ""
        await context.setPrompt(currentPrompt)

        // Perform transcription
        let success = await context.fullTranscribe(samples: samples)

        guard success else {
            logger.error("Whisper transcription failed for model: \(modelName)")
            throw WhisperContextError.transcriptionFailed
        }

        let transcription = await context.getTranscription()
        logger.info("Inference completed for model: \(modelName)")
        return transcription
    }

    /// Get available contexts
    func availableContexts() -> [String] {
        Array(contexts.keys)
    }

    /// Check if a context is loaded for the given model
    func isContextLoaded(for modelName: String) -> Bool {
        contexts[modelName] != nil
    }

    /// Unload all contexts
    func unloadAllContexts() async {
        logger.info("Unloading all Whisper contexts")
        for (modelName, context) in contexts {
            await context.releaseResources()
            logger.info("Unloaded context for model: \(modelName)")
        }
        contexts.removeAll()
        loadingContexts.removeAll()
    }

    private func readAudioSamples(_ url: URL) throws -> [Float] {
        try AudioSampleReader.readPCM16LE(from: url)
    }
}

// MARK: - Error Types
enum WhisperContextError: LocalizedError {
    case contextNotLoaded
    case contextLoadingInProgress
    case transcriptionFailed

    var errorDescription: String? {
        switch self {
        case .contextNotLoaded:
            return "Whisper context is not loaded"
        case .contextLoadingInProgress:
            return "Whisper context is currently being loaded"
        case .transcriptionFailed:
            return "Whisper transcription failed"
        }
    }
}