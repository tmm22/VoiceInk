import Foundation
import os

// MARK: - Ollama Extension
extension AIService {
    
    /// Checks if Ollama is connected and available
    /// - Parameter completion: Callback with connection status
    func checkOllamaConnection(completion: @escaping (Bool) -> Void) {
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            await self.ollamaService.checkConnection()
            // No need for DispatchQueue - already on MainActor
            completion(self.ollamaService.isConnected)
        }
    }
    
    /// Fetches available Ollama models
    /// - Returns: Array of available Ollama models
    func fetchOllamaModels() async -> [OllamaAIService.OllamaModel] {
        await ollamaService.refreshModels()
        return ollamaService.availableModels
    }
    
    /// Enhances text using Ollama
    /// - Parameters:
    ///   - text: The text to enhance
    ///   - systemPrompt: The system prompt to use
    ///   - timeout: Optional timeout for the request
    /// - Returns: Enhanced text
    /// - Throws: Error if enhancement fails
    func enhanceWithOllama(text: String, systemPrompt: String, timeout: TimeInterval? = nil) async throws -> String {
        logger.notice("🔄 Sending transcription to Ollama for enhancement (model: \(self.ollamaService.selectedModel))")
        do {
            let result = try await ollamaService.enhance(text, withSystemPrompt: systemPrompt, timeout: timeout)
            logger.notice("✅ Ollama enhancement completed successfully (\(result.count) characters)")
            return result
        } catch {
            logger.notice("❌ Ollama enhancement failed: \(error.localizedDescription)")
            throw error
        }
    }
    
    /// Updates the Ollama base URL
    /// - Parameter newURL: The new base URL for Ollama
    func updateOllamaBaseURL(_ newURL: String) {
        ollamaService.baseURL = newURL
        AppSettings.Ollama.baseURL = newURL
    }
    
    /// Updates the selected Ollama model
    /// - Parameter modelName: The name of the model to select
    func updateSelectedOllamaModel(_ modelName: String) {
        ollamaService.selectedModel = modelName
        AppSettings.Ollama.selectedModel = modelName
    }
    
    /// Returns available Ollama models from the service
    var ollamaAvailableModels: [OllamaAIService.OllamaModel] {
        ollamaService.availableModels
    }
    
    /// Returns whether Ollama is connected
    var isOllamaConnected: Bool {
        ollamaService.isConnected
    }
    
    /// Refreshes Ollama connection and models
    func refreshOllamaConnection() async {
        await ollamaService.checkConnection()
        await ollamaService.refreshModels()
    }
}
