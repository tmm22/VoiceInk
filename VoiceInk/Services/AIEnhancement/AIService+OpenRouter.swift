import Foundation
import os

// MARK: - OpenRouter Extension
extension AIService {
    
    /// Fetches available models from OpenRouter API
    func fetchOpenRouterModels() async {
        guard let url = URL(string: "https://openrouter.ai/api/v1/models") else {
            logger.error("Invalid OpenRouter API URL")
            // No need for MainActor.run - this class is already @MainActor
            self.setOpenRouterModels([])
            self.saveOpenRouterModels()
            self.objectWillChange.send()
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                logger.error("Failed to fetch OpenRouter models: Invalid HTTP response")
                self.setOpenRouterModels([])
                self.saveOpenRouterModels()
                self.objectWillChange.send()
                return
            }
            
            guard let jsonResponse = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let dataArray = jsonResponse["data"] as? [[String: Any]] else {
                logger.error("Failed to parse OpenRouter models JSON")
                self.setOpenRouterModels([])
                self.saveOpenRouterModels()
                self.objectWillChange.send()
                return
            }
            
            let models = dataArray.compactMap { $0["id"] as? String }
            self.setOpenRouterModels(models.sorted())
            self.saveOpenRouterModels() // Save to UserDefaults
            if self.selectedProvider == .openRouter && self.currentModel == self.selectedProvider.defaultModel && !models.isEmpty {
                self.selectModel(models.sorted().first!)
            }
            self.objectWillChange.send()
            logger.info("Successfully fetched \(models.count) OpenRouter models.")
            
        } catch {
            logger.error("Error fetching OpenRouter models: \(error.localizedDescription)")
            self.setOpenRouterModels([])
            self.saveOpenRouterModels()
            self.objectWillChange.send()
        }
    }
    
    /// Returns the available OpenRouter models
    var openRouterAvailableModels: [String] {
        getOpenRouterModels()
    }
}
