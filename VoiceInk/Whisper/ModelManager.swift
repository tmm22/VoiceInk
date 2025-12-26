import Foundation
import Combine
import os

/// Coordinates all model providers and manages the current transcription model
///
/// This class serves as the central point for model management, coordinating
/// between different model providers (Local Whisper, Parakeet, etc.) and
/// maintaining the current model selection.
///
/// - Note: This class is `@MainActor` to ensure thread-safe access to
///   published properties and UI updates.
@MainActor
final class ModelManager: ObservableObject {
    
    // MARK: - Published Properties
    
    /// All available transcription models across all providers
    @Published var allAvailableModels: [any TranscriptionModel] = PredefinedModels.models
    
    /// The currently selected transcription model
    @Published var currentModel: (any TranscriptionModel)?
    
    /// Combined download progress from all providers
    @Published var downloadProgress: [String: Double] = [:]
    
    // MARK: - Providers
    
    /// Provider for local Whisper models
    let localProvider: LocalModelProvider
    
    /// Provider for Parakeet models
    let parakeetProvider: ParakeetModelProvider
    
    // MARK: - Private Properties
    
    private let logger = Logger(subsystem: "com.tmm22.voicelinkcommunity", category: "ModelManager")
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    /// Initialize the ModelManager with required directories
    /// - Parameter modelsDirectory: Directory for local Whisper models
    init(modelsDirectory: URL) {
        self.localProvider = LocalModelProvider(modelsDirectory: modelsDirectory)
        self.parakeetProvider = ParakeetModelProvider()
        
        setupProgressObservers()
        refreshAllAvailableModels()
        loadCurrentTranscriptionModel()
    }
    
    /// Initialize with pre-configured providers (for testing or custom setups)
    /// - Parameters:
    ///   - localProvider: The local model provider
    ///   - parakeetProvider: The Parakeet model provider
    init(localProvider: LocalModelProvider, parakeetProvider: ParakeetModelProvider) {
        self.localProvider = localProvider
        self.parakeetProvider = parakeetProvider
        
        setupProgressObservers()
        refreshAllAvailableModels()
        loadCurrentTranscriptionModel()
    }
    
    // MARK: - Progress Observation
    
    private func setupProgressObservers() {
        // Observe local provider download progress
        localProvider.$downloadProgress
            .sink { [weak self] progress in
                self?.mergeDownloadProgress(progress, prefix: "local_")
            }
            .store(in: &cancellables)
        
        // Observe Parakeet provider download progress
        parakeetProvider.$downloadProgress
            .sink { [weak self] progress in
                self?.mergeDownloadProgress(progress, prefix: "parakeet_")
            }
            .store(in: &cancellables)
    }
    
    private func mergeDownloadProgress(_ progress: [String: Double], prefix: String) {
        for (key, value) in progress {
            downloadProgress[prefix + key] = value
        }
        // Remove completed downloads
        for key in downloadProgress.keys where key.hasPrefix(prefix) {
            let originalKey = String(key.dropFirst(prefix.count))
            if progress[originalKey] == nil {
                downloadProgress.removeValue(forKey: key)
            }
        }
    }
    
    // MARK: - Model Selection
    
    /// Load the current transcription model from UserDefaults
    func loadCurrentTranscriptionModel() {
        if let savedModelName = AppSettings.TranscriptionSettings.currentTranscriptionModel,
           let savedModel = allAvailableModels.first(where: { $0.name == savedModelName }) {
            currentModel = savedModel
        }
    }
    
    /// Set the current transcription model
    /// - Parameter model: The model to set as current
    func setCurrentModel(_ model: any TranscriptionModel) {
        currentModel = model
        AppSettings.TranscriptionSettings.currentTranscriptionModel = model.name
        
        // Post notification about the model change
        NotificationCenter.default.post(name: .didChangeModel, object: nil, userInfo: ["modelName": model.name])
    }
    
    // MARK: - Model Availability
    
    /// Refresh the list of all available models
    func refreshAllAvailableModels() {
        let currentModelName = currentModel?.name
        var models = PredefinedModels.models
        
        // Append dynamically discovered local models (imported .bin files) with minimal metadata
        for whisperModel in localProvider.whisperModels {
            if !models.contains(where: { $0.name == whisperModel.name }) {
                let importedModel = ImportedLocalModel(fileBaseName: whisperModel.name)
                models.append(importedModel)
            }
        }
        
        allAvailableModels = models
        
        // Preserve current selection by name (IDs may change for dynamic models)
        if let currentName = currentModelName,
           let updatedModel = allAvailableModels.first(where: { $0.name == currentName }) {
            setCurrentModel(updatedModel)
        }
    }
    
    // MARK: - Model Status Queries
    
    /// Check if a model is downloaded
    /// - Parameter model: The model to check
    /// - Returns: `true` if the model is downloaded
    func isModelDownloaded(_ model: any TranscriptionModel) -> Bool {
        switch model.provider {
        case .local:
            if let whisperModel = localProvider.whisperModels.first(where: { $0.name == model.name }) {
                return localProvider.isModelDownloaded(whisperModel)
            }
            // Check if it's a predefined local model
            return localProvider.whisperModels.contains { $0.name == model.name }
            
        case .parakeet:
            if let parakeetModel = model as? ParakeetModel {
                return parakeetProvider.isModelDownloaded(parakeetModel)
            }
            return false
            
        default:
            // Cloud models are always "available" (no download needed)
            return true
        }
    }
    
    /// Check if a model is currently downloading
    /// - Parameter model: The model to check
    /// - Returns: `true` if the model is downloading
    func isModelDownloading(_ model: any TranscriptionModel) -> Bool {
        switch model.provider {
        case .local:
            if let whisperModel = localProvider.whisperModels.first(where: { $0.name == model.name }) {
                return localProvider.isModelDownloading(whisperModel)
            }
            // Check by name for models not yet downloaded
            return localProvider.downloadProgress[model.name + "_main"] != nil
            
        case .parakeet:
            if let parakeetModel = model as? ParakeetModel {
                return parakeetProvider.isModelDownloading(parakeetModel)
            }
            return false
            
        default:
            return false
        }
    }
    
    // MARK: - Model Operations
    
    /// Download a model
    /// - Parameter model: The model to download
    func downloadModel(_ model: any TranscriptionModel) async throws {
        switch model.provider {
        case .local:
            if let localModel = model as? LocalModel {
                try await localProvider.downloadLocalModel(localModel)
                refreshAllAvailableModels()
            }
            
        case .parakeet:
            if let parakeetModel = model as? ParakeetModel {
                try await parakeetProvider.downloadModel(parakeetModel)
                refreshAllAvailableModels()
            }
            
        default:
            logger.warning("Download not supported for provider: \(model.provider.rawValue)")
        }
    }
    
    /// Delete a model
    /// - Parameter model: The model to delete
    func deleteModel(_ model: any TranscriptionModel) async throws {
        switch model.provider {
        case .local:
            if let whisperModel = localProvider.whisperModels.first(where: { $0.name == model.name }) {
                try await localProvider.deleteModel(whisperModel)
                
                // Clear current selection if this was the active model
                if currentModel?.name == model.name {
                    currentModel = nil
                    AppSettings.TranscriptionSettings.currentTranscriptionModel = nil
                }
                
                refreshAllAvailableModels()
            }
            
        case .parakeet:
            if let parakeetModel = model as? ParakeetModel {
                try await parakeetProvider.deleteModel(parakeetModel)
                
                // Clear current selection if this was the active model
                if currentModel?.name == model.name {
                    currentModel = nil
                    AppSettings.TranscriptionSettings.currentTranscriptionModel = nil
                }
                
                refreshAllAvailableModels()
            }
            
        default:
            logger.warning("Delete not supported for provider: \(model.provider.rawValue)")
        }
    }
    
    /// Show a model's location in Finder
    /// - Parameter model: The model to reveal
    func showModelInFinder(_ model: any TranscriptionModel) {
        switch model.provider {
        case .local:
            if let whisperModel = localProvider.whisperModels.first(where: { $0.name == model.name }) {
                localProvider.showModelInFinder(whisperModel)
            }
            
        case .parakeet:
            if let parakeetModel = model as? ParakeetModel {
                parakeetProvider.showModelInFinder(parakeetModel)
            }
            
        default:
            logger.warning("Show in Finder not supported for provider: \(model.provider.rawValue)")
        }
    }
    
    // MARK: - Local Model Operations
    
    /// Import a local model file
    /// - Parameter sourceURL: URL of the model file to import
    /// - Returns: The imported model, or nil if import failed
    @discardableResult
    func importLocalModel(from sourceURL: URL) async -> WhisperModel? {
        let result = await localProvider.importLocalModel(from: sourceURL)
        if result != nil {
            refreshAllAvailableModels()
        }
        return result
    }
    
    /// Load a local Whisper model into memory
    /// - Parameter model: The model to load
    func loadLocalModel(_ model: WhisperModel) async throws {
        try await localProvider.loadModel(model)
    }
    
    /// Unload the current local model from memory
    func unloadLocalModel() async {
        await localProvider.unloadModel()
    }
}
