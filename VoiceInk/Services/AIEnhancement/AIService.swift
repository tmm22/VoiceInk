import Foundation
import os

// MARK: - AIService Class
/// Main AI service for managing AI providers, API keys, and model selection.
/// Extensions provide additional functionality:
/// - AIService+APIKeyVerification.swift: API key verification for all providers
/// - AIService+Ollama.swift: Ollama-specific functionality
/// - AIService+OpenRouter.swift: OpenRouter model fetching
/// - AIProvider.swift: AIProvider enum and AIServiceURLError
@MainActor
class AIService: ObservableObject {
    // MARK: - Internal Properties (accessible by extensions)
    let logger = Logger(subsystem: "com.tmm22.voicelinkcommunity", category: "AIService")
    let session = SecureURLSession.makeEphemeral()
    let keychain = KeychainManager()
    lazy var ollamaService = OllamaAIService()
    
    // MARK: - Published Properties
    @Published var apiKey: String = ""
    @Published var isAPIKeyValid: Bool = false
    @Published var customBaseURL: String = AppSettings.AI.customProviderBaseURL {
        didSet {
            AppSettings.AI.customProviderBaseURL = customBaseURL
        }
    }
    @Published var customModel: String = AppSettings.AI.customProviderModel {
        didSet {
            AppSettings.AI.customProviderModel = customModel
        }
    }
    @Published var selectedProvider: AIProvider {
        didSet {
            AppSettings.AI.selectedProviderRawValue = selectedProvider.rawValue
            if selectedProvider.requiresAPIKey {
                // Try Keychain first
                if let savedKey = keychain.getAPIKey(for: selectedProvider.rawValue) {
                    self.apiKey = savedKey
                    self.isAPIKeyValid = true
                } else {
                    self.apiKey = ""
                    self.isAPIKeyValid = false
                }
            } else {
                self.apiKey = ""
                self.isAPIKeyValid = true
                if selectedProvider == .ollama {
                    Task {
                        await ollamaService.checkConnection()
                        await ollamaService.refreshModels()
                    }
                }
            }
        }
    }
    
    @Published private var selectedModels: [AIProvider: String] = [:]
    @Published private var openRouterModels: [String] = []
    
    // MARK: - Computed Properties
    var connectedProviders: [AIProvider] {
        AIProvider.allCases.filter { provider in
            if provider == .ollama {
                return ollamaService.isConnected
            } else if provider.requiresAPIKey {
                return keychain.hasAPIKey(for: provider.rawValue)
            }
            return false
        }
    }
    
    var currentModel: String {
        if let selectedModel = selectedModels[selectedProvider],
           !selectedModel.isEmpty,
           (selectedProvider == .ollama && !selectedModel.isEmpty) || availableModels.contains(selectedModel) {
            return selectedModel
        }
        return selectedProvider.defaultModel
    }
    
    var availableModels: [String] {
        if selectedProvider == .ollama {
            return ollamaService.availableModels.map { $0.name }
        } else if selectedProvider == .openRouter {
            return openRouterModels
        }
        return selectedProvider.availableModels
    }
    
    // MARK: - Initialization
    init() {
        if let savedProvider = AppSettings.AI.selectedProviderRawValue,
           let provider = AIProvider(rawValue: savedProvider) {
            self.selectedProvider = provider
        } else {
            self.selectedProvider = .gemini
        }
        
        if selectedProvider.requiresAPIKey {
            // Try Keychain first
            if let savedKey = keychain.getAPIKey(for: selectedProvider.rawValue) {
                self.apiKey = savedKey
                self.isAPIKeyValid = true
            }
        } else {
            self.isAPIKeyValid = true
        }
        
        loadSavedModelSelections()
        loadSavedOpenRouterModels()
    }
    
    // MARK: - Model Selection
    func selectModel(_ model: String) {
        guard !model.isEmpty else { return }
        
        selectedModels[selectedProvider] = model
        let key = AppSettings.AI.selectedModelKey(for: selectedProvider.rawValue)
        AppSettings.setValue(model, forKey: key)
        
        if selectedProvider == .ollama {
            updateSelectedOllamaModel(model)
        }
        
        objectWillChange.send()
    }
    
    // MARK: - API Key Management
    func saveAPIKey(_ key: String, completion: @escaping (Bool, String?) -> Void) {
        guard selectedProvider.requiresAPIKey else {
            completion(true, nil)
            return
        }
        
        verifyAPIKey(key) { [weak self] isValid, errorMessage in
            guard let self = self else { return }
            // Use Task to properly hop back to MainActor instead of DispatchQueue.main.async
            Task { @MainActor in
                if isValid {
                    do {
                        try self.keychain.saveAPIKey(key, for: self.selectedProvider.rawValue)
                        self.apiKey = key
                        self.isAPIKeyValid = true
                        NotificationCenter.default.post(name: .aiProviderKeyChanged, object: nil)
                    } catch {
                        self.isAPIKeyValid = false
                        let message = "Failed to save API key. Please try again."
                        self.logger.error("Failed to save API key for \(self.selectedProvider.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)")
                        completion(false, message)
                        return
                    }
                } else {
                    self.isAPIKeyValid = false
                }
                completion(isValid, errorMessage)
            }
        }
    }
    
    func clearAPIKey() {
        guard selectedProvider.requiresAPIKey else { return }
        
        apiKey = ""
        isAPIKeyValid = false
        // Best-effort cleanup; key may already be missing.
        try? keychain.deleteAPIKey(for: selectedProvider.rawValue)
        NotificationCenter.default.post(name: .aiProviderKeyChanged, object: nil)
    }
    
    // MARK: - Private Methods
    private func loadSavedModelSelections() {
        for provider in AIProvider.allCases {
            let key = AppSettings.AI.selectedModelKey(for: provider.rawValue)
            let savedModel = AppSettings.string(forKey: key, default: "")
            if !savedModel.isEmpty {
                selectedModels[provider] = savedModel
            }
        }
    }
    
    private func loadSavedOpenRouterModels() {
        openRouterModels = AppSettings.AI.openRouterModels
    }
    
    // MARK: - Internal Methods (for extensions)
    func saveOpenRouterModels() {
        AppSettings.AI.openRouterModels = openRouterModels
    }
    
    func setOpenRouterModels(_ models: [String]) {
        openRouterModels = models
    }
    
    func getOpenRouterModels() -> [String] {
        return openRouterModels
    }
}
