import Foundation
import AVFoundation
import os

class LocalTranscriptionService: TranscriptionService {

    private let contextManager: WhisperContextManager
    private let logger = Logger(subsystem: "com.tmm22.voicelinkcommunity", category: "LocalTranscriptionService")
    private let modelsDirectory: URL
    private weak var whisperState: WhisperState?
    private weak var localProvider: LocalModelProvider?
    
    /// Initialize with WhisperState (legacy interface for backward compatibility)
    init(modelsDirectory: URL, whisperState: WhisperState? = nil) {
        self.modelsDirectory = modelsDirectory
        self.contextManager = WhisperContextManager.shared
        self.whisperState = whisperState
        self.localProvider = nil
    }

    /// Initialize with LocalModelProvider (new interface)
    init(modelsDirectory: URL, localProvider: LocalModelProvider) {
        self.modelsDirectory = modelsDirectory
        self.contextManager = WhisperContextManager.shared
        self.whisperState = nil
        self.localProvider = localProvider
    }
    
    func transcribe(audioURL: URL, model: any TranscriptionModel) async throws -> String {
        guard model.provider == .local else {
            throw WhisperStateError.modelLoadFailed
        }
        
        logger.notice("Initiating local transcription for model: \(model.displayName)")
        
        // Try to use LocalModelProvider first (new interface)
        if let localProvider = localProvider {
            return try await transcribeWithLocalProvider(audioURL: audioURL, model: model, localProvider: localProvider)
        }
        
        // Fall back to WhisperState (legacy interface)
        return try await transcribeWithWhisperState(audioURL: audioURL, model: model)
    }
    
    private func transcribeWithLocalProvider(audioURL: URL, model: any TranscriptionModel, localProvider: LocalModelProvider) async throws -> String {
        // Check if the required model is already loaded in LocalModelProvider
        if await localProvider.isModelLoaded,
           await contextManager.isContextLoaded(for: model.name),
           let currentModel = await localProvider.loadedModel,
           currentModel.name == model.name {

            logger.notice("✅ Using already loaded model from LocalModelProvider: \(model.name)")
        } else {
            // Model not loaded or wrong model loaded, proceed with loading
            let resolvedURL: URL? = await localProvider.whisperModels.first(where: { $0.name == model.name })?.url
            guard let modelURL = resolvedURL, FileManager.default.fileExists(atPath: modelURL.path) else {
                logger.error("Model file not found for: \(model.name)")
                throw WhisperStateError.modelLoadFailed
            }

            logger.notice("Loading model: \(model.name)")
            do {
                _ = try await contextManager.loadContext(for: model.name, modelURL: modelURL)
            } catch {
                logger.error("Failed to load model: \(model.name) - \(error.localizedDescription)")
                throw WhisperStateError.modelLoadFailed
            }
        }

        return try await contextManager.performInference(modelName: model.name, audioURL: audioURL)
    }
    
    private func transcribeWithWhisperState(audioURL: URL, model: any TranscriptionModel) async throws -> String {
        // Check if the required model is already loaded
        if await contextManager.isContextLoaded(for: model.name) {
            logger.notice("✅ Using already loaded model: \(model.name)")
        } else {
            // Model not loaded, proceed with loading
            // Resolve the on-disk URL using WhisperState.availableModels (covers imports)
            let resolvedURL: URL? = await whisperState?.availableModels.first(where: { $0.name == model.name })?.url
            guard let modelURL = resolvedURL, FileManager.default.fileExists(atPath: modelURL.path) else {
                logger.error("Model file not found for: \(model.name)")
                throw WhisperStateError.modelLoadFailed
            }

            logger.notice("Loading model: \(model.name)")
            do {
                _ = try await contextManager.loadContext(for: model.name, modelURL: modelURL)
            } catch {
                logger.error("Failed to load model: \(model.name) - \(error.localizedDescription)")
                throw WhisperStateError.modelLoadFailed
            }
        }

        return try await contextManager.performInference(modelName: model.name, audioURL: audioURL)
    }
    
}
