import Foundation

/// Protocol for model providers that manage AI model lifecycle
///
/// This protocol defines the interface for managing transcription models,
/// including downloading, loading, and deleting models. Each provider
/// implementation handles a specific type of model (e.g., Whisper, Parakeet).
///
/// - Note: All implementations must be `@MainActor` to ensure thread-safe
///   access to published properties and UI updates.
@MainActor
protocol ModelProviderProtocol: ObservableObject {
    /// The type of model this provider manages
    associatedtype ModelType
    
    /// The provider type this implementation handles
    var providerType: ModelProvider { get }
    
    /// Directory where models are stored
    var modelsDirectory: URL { get }
    
    /// Current download progress for models, keyed by model name
    var downloadProgress: [String: Double] { get set }
    
    /// Check if a model is downloaded and available for use
    /// - Parameter model: The model to check
    /// - Returns: `true` if the model is downloaded and ready
    func isModelDownloaded(_ model: ModelType) -> Bool
    
    /// Check if a model is currently being downloaded
    /// - Parameter model: The model to check
    /// - Returns: `true` if the model is currently downloading
    func isModelDownloading(_ model: ModelType) -> Bool
    
    /// Download a model
    /// - Parameter model: The model to download
    /// - Throws: An error if the download fails
    func downloadModel(_ model: ModelType) async throws
    
    /// Delete a model from disk
    /// - Parameter model: The model to delete
    /// - Throws: An error if deletion fails
    func deleteModel(_ model: ModelType) async throws
    
    /// Show the model's location in Finder
    /// - Parameter model: The model to reveal
    func showModelInFinder(_ model: ModelType)
    
    /// Get all available models of this type
    /// - Returns: Array of available models
    func availableModels() -> [ModelType]
}

/// Protocol for providers that support loading models into memory
@MainActor
protocol LoadableModelProviderProtocol: ModelProviderProtocol {
    /// The currently loaded model, if any
    var loadedModel: ModelType? { get }
    
    /// Whether a model is currently loaded
    var isModelLoaded: Bool { get }
    
    /// Whether a model is currently being loaded
    var isModelLoading: Bool { get }
    
    /// Load a model into memory
    /// - Parameter model: The model to load
    /// - Throws: An error if loading fails
    func loadModel(_ model: ModelType) async throws
    
    /// Unload the current model from memory
    func unloadModel() async
}
