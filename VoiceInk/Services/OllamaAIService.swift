import Foundation
import SwiftUI

@MainActor
class OllamaAIService: ObservableObject {
    static let defaultBaseURL = AppSettings.Ollama.defaultBaseURL
    
    // MARK: - Response Types
    struct OllamaModel: Codable, Identifiable {
        let name: String
        let modified_at: String
        let size: Int64
        let digest: String
        let details: ModelDetails
        
        var id: String { name }
        
        struct ModelDetails: Codable {
            let format: String
            let family: String
            let families: [String]?
            let parameter_size: String
            let quantization_level: String
        }
    }

    struct OllamaModelsResponse: Codable {
        let models: [OllamaModel]
    }

    struct OllamaResponse: Codable {
        let response: String
    }
    
    // MARK: - Published Properties
    @Published var baseURL: String {
        didSet {
            AppSettings.Ollama.baseURL = baseURL
        }
    }
    
    @Published var selectedModel: String {
        didSet {
            AppSettings.Ollama.selectedModel = selectedModel
        }
    }
    
    @Published var availableModels: [OllamaModel] = []
    @Published var isConnected: Bool = false
    @Published var isLoadingModels: Bool = false
    
    private let defaultTemperature: Double = 0.3
    private let session = SecureURLSession.makeEphemeral()
    
    // MARK: - Model Caching
    /// Cached models to avoid repeated network requests
    private var cachedModels: [OllamaModel]?
    /// Timestamp of when the cache was last updated
    private var cacheTimestamp: Date?
    /// Time-to-live for the cache (60 seconds)
    private let cacheTTL: TimeInterval = 60
    
    init() {
        self.baseURL = AppSettings.Ollama.baseURL
        self.selectedModel = AppSettings.Ollama.selectedModel
    }
    
    func checkConnection() async {
        guard let url = URL(string: baseURL) else {
            isConnected = false
            return
        }
        
        do {
            let (_, response) = try await session.data(from: url)
            if let httpResponse = response as? HTTPURLResponse {
                isConnected = (200...299).contains(httpResponse.statusCode)
            } else {
                isConnected = false
            }
        } catch {
            isConnected = false
        }
    }
    
    func refreshModels() async {
        isLoadingModels = true
        defer { isLoadingModels = false }
        
        do {
            let models = try await fetchAvailableModels()
            availableModels = models
            
            // If selected model is not in available models, select first available
            if !models.contains(where: { $0.name == selectedModel }) && !models.isEmpty {
                selectedModel = models[0].name
            }
        } catch {
            AppLogger.ai.error("Ollama model refresh failed: \(error.localizedDescription, privacy: .public)")
            availableModels = []
        }
    }
    
    /// Fetches available models with caching to reduce network requests.
    /// Returns cached data if available and not expired, otherwise fetches fresh data.
    private func fetchAvailableModels() async throws -> [OllamaModel] {
        // Return cached data if valid
        if let cached = cachedModels,
           let timestamp = cacheTimestamp,
           Date().timeIntervalSince(timestamp) < cacheTTL {
            AppLogger.ai.debug("Ollama: returning cached models (\(cached.count, privacy: .public))")
            return cached
        }
        
        // Fetch fresh data from API
        let models = try await fetchModelsFromAPI()
        
        // Update cache
        cachedModels = models
        cacheTimestamp = Date()
        
        AppLogger.ai.debug("Ollama: fetched and cached \(models.count, privacy: .public) models")
        
        return models
    }
    
    /// Fetches models directly from the Ollama API (no caching).
    private func fetchModelsFromAPI() async throws -> [OllamaModel] {
        guard let base = URL(string: baseURL),
              let url = URL(string: "api/tags", relativeTo: base) else {
            throw LocalAIError.invalidURL
        }
        
        let (data, _) = try await session.data(from: url)
        let response = try JSONDecoder().decode(OllamaModelsResponse.self, from: data)
        return response.models
    }
    
    /// Invalidates the model cache, forcing the next fetch to retrieve fresh data.
    /// Call this when you know the model list may have changed (e.g., after pulling a new model).
    func invalidateModelCache() {
        cachedModels = nil
        cacheTimestamp = nil
        AppLogger.ai.debug("Ollama: model cache invalidated")
    }
    
    func enhance(_ text: String, withSystemPrompt systemPrompt: String? = nil, timeout: TimeInterval? = nil) async throws -> String {
        guard let base = URL(string: baseURL),
              let url = URL(string: "api/generate", relativeTo: base) else {
            throw LocalAIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Apply custom timeout if provided
        if let timeout = timeout {
            request.timeoutInterval = timeout
        }
        
        guard let systemPrompt = systemPrompt else {
            throw LocalAIError.invalidRequest
        }
        
        AppLogger.ai.debug("Ollama enhancement request. textLength=\(text.count, privacy: .public) promptLength=\(systemPrompt.count, privacy: .public)")
        
        let body: [String: Any] = [
            "model": selectedModel,
            "prompt": text,
            "system": systemPrompt,
            "temperature": defaultTemperature,
            "stream": false
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LocalAIError.invalidResponse
        }
        
        switch httpResponse.statusCode {
        case 200:
            let response = try JSONDecoder().decode(OllamaResponse.self, from: data)
            AppLogger.ai.debug("Ollama enhancement response length \(response.response.count, privacy: .public)")
            return response.response
        case 404:
            throw LocalAIError.modelNotFound
        case 500:
            throw LocalAIError.serverError
        default:
            throw LocalAIError.invalidResponse
        }
    }
}

// MARK: - Error Types
enum LocalAIError: Error, LocalizedError {
    case invalidURL
    case serviceUnavailable
    case invalidResponse
    case modelNotFound
    case serverError
    case invalidRequest
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid Ollama server URL"
        case .serviceUnavailable:
            return "Ollama service is not available"
        case .invalidResponse:
            return "Invalid response from Ollama server"
        case .modelNotFound:
            return "Selected model not found"
        case .serverError:
            return "Ollama server error"
        case .invalidRequest:
            return "System prompt is required"
        }
    }
} 
