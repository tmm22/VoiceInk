import Foundation
import AVFoundation
import os

class LocalTranscriptionService: TranscriptionService {

    private let contextManager: WhisperContextManager
    private let logger = Logger(subsystem: "com.tmm22.voicelinkcommunity", category: "LocalTranscriptionService")
    private let modelsDirectory: URL
    private weak var whisperState: WhisperState?
    
    /// Initialize with WhisperState (legacy interface for backward compatibility)
    init(modelsDirectory: URL, whisperState: WhisperState? = nil) {
        self.modelsDirectory = modelsDirectory
        self.contextManager = WhisperContextManager.shared
        self.whisperState = whisperState
    }
    
    func transcribe(audioURL: URL, model: any TranscriptionModel) async throws -> String {
        guard model.provider == .local else {
            throw WhisperStateError.modelLoadFailed
        }
        
        logger.notice("Initiating local transcription")
        
        return try await transcribeWithWhisperState(audioURL: audioURL, model: model)
    }
    
    private func transcribeWithWhisperState(audioURL: URL, model: any TranscriptionModel) async throws -> String {
        // Check if the required model is already loaded
        if await contextManager.isContextLoaded(for: model.name) {
            logger.notice("✅ Using already loaded local model")
        } else {
            // Model not loaded, proceed with loading
            // Resolve the on-disk URL using WhisperState.availableModels (covers imports)
            let resolvedURL: URL? = await whisperState?.availableModels.first(where: { $0.name == model.name })?.url
            guard let modelURL = resolvedURL, FileManager.default.fileExists(atPath: modelURL.path) else {
                logger.error("Local model file not found")
                throw WhisperStateError.modelLoadFailed
            }

            logger.notice("Loading local model")
            do {
                _ = try await contextManager.loadContext(for: model.name, modelURL: modelURL)
            } catch {
                logger.error("Failed to load local model: \(AppLogger.errorMetadata(error), privacy: .public)")
                throw WhisperStateError.modelLoadFailed
            }
        }

        return try await contextManager.performInference(modelName: model.name, audioURL: audioURL)
    }
    
}
