import Foundation
import AVFoundation
import os

class LocalTranscriptionService: TranscriptionService {
    
    private var whisperContext: WhisperContext?
    private let logger = Logger(subsystem: "com.tmm22.voicelinkcommunity", category: "LocalTranscriptionService")
    private let modelsDirectory: URL
    private weak var whisperState: WhisperState?
    private weak var localProvider: LocalModelProvider?
    
    /// Initialize with WhisperState (legacy interface for backward compatibility)
    init(modelsDirectory: URL, whisperState: WhisperState? = nil) {
        self.modelsDirectory = modelsDirectory
        self.whisperState = whisperState
        self.localProvider = nil
    }
    
    /// Initialize with LocalModelProvider (new interface)
    init(modelsDirectory: URL, localProvider: LocalModelProvider) {
        self.modelsDirectory = modelsDirectory
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
           let loadedContext = await localProvider.whisperContext,
           let currentModel = await localProvider.loadedModel,
           currentModel.name == model.name {
            
            logger.notice("✅ Using already loaded model from LocalModelProvider: \(model.name)")
            whisperContext = loadedContext
        } else {
            // Model not loaded or wrong model loaded, proceed with loading
            let resolvedURL: URL? = await localProvider.whisperModels.first(where: { $0.name == model.name })?.url
            guard let modelURL = resolvedURL, FileManager.default.fileExists(atPath: modelURL.path) else {
                logger.error("Model file not found for: \(model.name)")
                throw WhisperStateError.modelLoadFailed
            }
            
            logger.notice("Loading model: \(model.name)")
            do {
                whisperContext = try await WhisperContext.createContext(path: modelURL.path)
            } catch {
                logger.error("Failed to load model: \(model.name) - \(error.localizedDescription)")
                throw WhisperStateError.modelLoadFailed
            }
        }
        
        return try await performTranscription(audioURL: audioURL, sharedContext: await localProvider.whisperContext)
    }
    
    private func transcribeWithWhisperState(audioURL: URL, model: any TranscriptionModel) async throws -> String {
        // Check if the required model is already loaded in WhisperState
        if let whisperState = whisperState,
           await whisperState.isModelLoaded,
           let loadedContext = await whisperState.whisperContext,
           let currentModel = await whisperState.currentTranscriptionModel,
           currentModel.provider == .local,
           currentModel.name == model.name {
            
            logger.notice("✅ Using already loaded model: \(model.name)")
            whisperContext = loadedContext
        } else {
            // Model not loaded or wrong model loaded, proceed with loading
            // Resolve the on-disk URL using WhisperState.availableModels (covers imports)
            let resolvedURL: URL? = await whisperState?.availableModels.first(where: { $0.name == model.name })?.url
            guard let modelURL = resolvedURL, FileManager.default.fileExists(atPath: modelURL.path) else {
                logger.error("Model file not found for: \(model.name)")
                throw WhisperStateError.modelLoadFailed
            }
            
            logger.notice("Loading model: \(model.name)")
            do {
                whisperContext = try await WhisperContext.createContext(path: modelURL.path)
            } catch {
                logger.error("Failed to load model: \(model.name) - \(error.localizedDescription)")
                throw WhisperStateError.modelLoadFailed
            }
        }
        
        return try await performTranscription(audioURL: audioURL, sharedContext: await whisperState?.whisperContext)
    }
    
    private func performTranscription(audioURL: URL, sharedContext: WhisperContext?) async throws -> String {
        guard let whisperContext = whisperContext else {
            logger.error("Cannot transcribe: Model could not be loaded")
            throw WhisperStateError.modelLoadFailed
        }
        
        // Read audio data
        let data = try readAudioSamples(audioURL)
        
        // Set prompt
        let currentPrompt = AppSettings.TranscriptionSettings.prompt ?? ""
        await whisperContext.setPrompt(currentPrompt)
        
        // Transcribe
        let success = await whisperContext.fullTranscribe(samples: data)
        
        guard success else {
            logger.error("Core transcription engine failed (whisper_full).")
            throw WhisperStateError.whisperCoreFailed
        }
        
        let text = await whisperContext.getTranscription()

        logger.notice("✅ Local transcription completed successfully.")
        
        // Only release resources if we created a new context (not using the shared one)
        if sharedContext !== whisperContext {
            await whisperContext.releaseResources()
            self.whisperContext = nil
        }
        
        return text
    }
    
    private func readAudioSamples(_ url: URL) throws -> [Float] {
        try AudioSampleReader.readPCM16LE(from: url)
    }
}
