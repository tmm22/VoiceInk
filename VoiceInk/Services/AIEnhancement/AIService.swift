import Foundation
import os

// MARK: - URL Validation Errors
enum AIServiceURLError: LocalizedError {
    case invalidURL(String)
    case insecureURL(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL(let message):
            return "Invalid URL: \(message)"
        case .insecureURL(let message):
            return "Insecure URL: \(message)"
        }
    }
}

enum AIProvider: String, CaseIterable {
    case cerebras = "Cerebras"
    case groq = "GROQ"
    case gemini = "Gemini"
    case anthropic = "Anthropic"
    case openAI = "OpenAI"
    case openRouter = "OpenRouter"
    case mistral = "Mistral"
    case elevenLabs = "ElevenLabs"
    case deepgram = "Deepgram"
    case soniox = "Soniox"
    case assemblyAI = "AssemblyAI"
    case zai = "ZAI"
    case ollama = "Ollama"
    case custom = "Custom"
    
    
    var baseURL: String {
        switch self {
        case .cerebras:
            return "https://api.cerebras.ai/v1/chat/completions"
        case .groq:
            return "https://api.groq.com/openai/v1/chat/completions"
        case .gemini:
            return "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions"
        case .anthropic:
            return "https://api.anthropic.com/v1/messages"
        case .openAI:
            return "https://api.openai.com/v1/chat/completions"
        case .openRouter:
            return "https://openrouter.ai/api/v1/chat/completions"
        case .mistral:
            return "https://api.mistral.ai/v1/chat/completions"
        case .elevenLabs:
            return "https://api.elevenlabs.io/v1/speech-to-text"
        case .deepgram:
            return "https://api.deepgram.com/v1/listen"
        case .soniox:
            return "https://api.soniox.com/v1"
        case .assemblyAI:
            return "https://api.assemblyai.com/v2"
        case .zai:
            return "https://api.z.ai/api/paas/v4/chat/completions"
        case .ollama:
            // NOTE: Ollama runs locally, so http://localhost is acceptable for local development
            return UserDefaults.standard.string(forKey: "ollamaBaseURL") ?? "http://localhost:11434"
        case .custom:
            return UserDefaults.standard.string(forKey: "customProviderBaseURL") ?? ""
        }
    }
    
    /// Validates that a custom URL is secure (HTTPS) for use with API credentials.
    /// - Parameter urlString: The URL string to validate
    /// - Returns: A validated URL
    /// - Throws: AIServiceURLError if the URL is invalid or insecure
    /// - Note: Ollama URLs are exempt from HTTPS requirement as they typically run locally
    static func validateSecureURL(_ urlString: String, allowLocalhost: Bool = false) throws -> URL {
        guard let url = URL(string: urlString) else {
            throw AIServiceURLError.invalidURL("Cannot parse URL: \(urlString)")
        }
        
        guard let host = url.host, !host.isEmpty else {
            throw AIServiceURLError.invalidURL("Missing host in URL")
        }
        
        // Allow localhost/127.0.0.1 for local development (e.g., Ollama)
        let isLocalhost = host == "localhost" || host == "127.0.0.1" || host == "::1"
        if allowLocalhost && isLocalhost {
            return url
        }
        
        // CRITICAL: Enforce HTTPS for any URL carrying API credentials
        guard url.scheme?.lowercased() == "https" else {
            throw AIServiceURLError.insecureURL("HTTPS required for API endpoints. Use https:// instead of http://")
        }
        
        return url
    }
    
    var defaultModel: String {
        switch self {
        case .cerebras:
            return "gpt-oss-120b"
        case .groq:
            return "openai/gpt-oss-120b"
        case .gemini:
            return "gemini-2.5-flash-lite"
        case .anthropic:
            return "claude-sonnet-4-5"
        case .openAI:
            return "gpt-5.2"
        case .mistral:
            return "mistral-large-latest"
        case .elevenLabs:
            return "scribe_v2_realtime"
        case .deepgram:
            return "whisper-1"
        case .soniox:
            return "stt-async-v3"
        case .assemblyAI:
            return "best"
        case .zai:
            return "glm-4.5-flash"
        case .ollama:
            return UserDefaults.standard.string(forKey: "ollamaSelectedModel") ?? "mistral"
        case .custom:
            return UserDefaults.standard.string(forKey: "customProviderModel") ?? ""
        case .openRouter:
            return "openai/gpt-oss-120b"
        }
    }
    
    var availableModels: [String] {
        switch self {
        case .cerebras:
            return [
                "gpt-oss-120b",
                "llama-3.1-8b",
                "llama-4-scout-17b-16e-instruct",
                "llama-3.3-70b",
                "qwen-3-32b",
                "qwen-3-235b-a22b-instruct-2507"
            ]
        case .groq:
            return [
                "llama-3.1-8b-instant",
                "llama-3.3-70b-versatile",
                "moonshotai/kimi-k2-instruct-0905",
                "qwen/qwen3-32b",
                "meta-llama/llama-4-maverick-17b-128e-instruct",
                "openai/gpt-oss-120b",
                "openai/gpt-oss-20b"
            ]
        case .gemini:
            return [
                "gemini-3-pro-preview",
                "gemini-2.5-pro",
                "gemini-2.5-flash",
                "gemini-2.5-flash-lite",
                "gemini-2.0-flash-001"
            ]
        case .anthropic:
            return [
                "claude-opus-4-5",
                "claude-sonnet-4-5",
                "claude-haiku-4-5"
            ]
        case .openAI:
            return [
                "gpt-5.2",
                "gpt-5.2-pro",
                "gpt-5.1",
                "gpt-5-mini",
                "gpt-5-nano",
                "gpt-4.1",
                "gpt-4.1-mini"
            ]
        case .mistral:
            return [
                "mistral-large-latest",
                "mistral-medium-latest",
                "mistral-small-latest",
                "mistral-saba-latest"
            ]
        case .elevenLabs:
            return ["scribe_v2_realtime", "scribe_v1", "scribe_v1_experimental"]
        case .deepgram:
            return ["whisper-1"]
        case .soniox:
            return ["stt-async-v3"]
        case .assemblyAI:
            return ["best", "nano"]
        case .zai:
            return [
                "glm-4.5-flash",        // Free tier
                "glm-4.6",              // Latest flagship, 200K context
                "glm-4.5",              // Previous flagship
                "glm-4.5-air",          // Lightweight/faster
                "glm-4-32b-0414-128k"   // Open weights model
            ]
        case .ollama:
            return []
        case .custom:
            return []
        case .openRouter:
            return []
        }
    }
    
    var requiresAPIKey: Bool {
        switch self {
        case .ollama:
            return false
        default:
            return true
        }
    }
}

@MainActor
class AIService: ObservableObject {
    private let logger = Logger(subsystem: "com.tmm22.voicelinkcommunity", category: "AIService")
    private let session = SecureURLSession.makeEphemeral()
    
    @Published var apiKey: String = ""
    @Published var isAPIKeyValid: Bool = false
    @Published var customBaseURL: String = UserDefaults.standard.string(forKey: "customProviderBaseURL") ?? "" {
        didSet {
            userDefaults.set(customBaseURL, forKey: "customProviderBaseURL")
        }
    }
    @Published var customModel: String = UserDefaults.standard.string(forKey: "customProviderModel") ?? "" {
        didSet {
            userDefaults.set(customModel, forKey: "customProviderModel")
        }
    }
    @Published var selectedProvider: AIProvider {
        didSet {
            userDefaults.set(selectedProvider.rawValue, forKey: "selectedAIProvider")
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
            NotificationCenter.default.post(name: .AppSettingsDidChange, object: nil)
        }
    }
    
    @Published private var selectedModels: [AIProvider: String] = [:]
    private let userDefaults = UserDefaults.standard
    private let keychain = KeychainManager()
    private lazy var ollamaService = OllamaService()
    
    @Published private var openRouterModels: [String] = []
    
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
    
    init() {
        if let savedProvider = userDefaults.string(forKey: "selectedAIProvider"),
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
    
    private func loadSavedModelSelections() {
        for provider in AIProvider.allCases {
            let key = "\(provider.rawValue)SelectedModel"
            if let savedModel = userDefaults.string(forKey: key), !savedModel.isEmpty {
                selectedModels[provider] = savedModel
            }
        }
    }
    
    private func loadSavedOpenRouterModels() {
        if let savedModels = userDefaults.array(forKey: "openRouterModels") as? [String] {
            openRouterModels = savedModels
        }
    }
    
    private func saveOpenRouterModels() {
        userDefaults.set(openRouterModels, forKey: "openRouterModels")
    }
    
    func selectModel(_ model: String) {
        guard !model.isEmpty else { return }
        
        selectedModels[selectedProvider] = model
        let key = "\(selectedProvider.rawValue)SelectedModel"
        userDefaults.set(model, forKey: key)
        
        if selectedProvider == .ollama {
            updateSelectedOllamaModel(model)
        }
        
        objectWillChange.send()
        NotificationCenter.default.post(name: .AppSettingsDidChange, object: nil)
    }
    
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
                    self.apiKey = key
                    self.isAPIKeyValid = true
                    self.keychain.saveAPIKey(key, for: self.selectedProvider.rawValue)
                    NotificationCenter.default.post(name: .aiProviderKeyChanged, object: nil)
                } else {
                    self.isAPIKeyValid = false
                }
                completion(isValid, errorMessage)
            }
        }
    }
    
    func verifyAPIKey(_ key: String, completion: @escaping (Bool, String?) -> Void) {
        guard selectedProvider.requiresAPIKey else {
            completion(true, nil)
            return
        }
        
        switch selectedProvider {
        case .anthropic:
            verifyAnthropicAPIKey(key, completion: completion)
        case .elevenLabs:
            verifyElevenLabsAPIKey(key, completion: completion)
        case .deepgram:
            verifyDeepgramAPIKey(key, completion: completion)
        case .mistral:
            verifyMistralAPIKey(key, completion: completion)
        case .soniox:
            verifySonioxAPIKey(key, completion: completion)
        case .assemblyAI:
            verifyAssemblyAIAPIKey(key, completion: completion)
        default:
            verifyOpenAICompatibleAPIKey(key, completion: completion)
        }
    }
    
    private func verifyOpenAICompatibleAPIKey(_ key: String, completion: @escaping (Bool, String?) -> Void) {
        guard let url = URL(string: self.selectedProvider.baseURL) else {
            logger.error("Invalid base URL for provider: \(self.selectedProvider.baseURL)")
            completion(false, "Invalid base URL for provider")
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        
        let testBody: [String: Any] = [
            "model": currentModel,
            "messages": [
                ["role": "user", "content": "test"]
            ]
        ]
        
        // Log if JSON serialization fails (non-critical for verification)
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: testBody)
        } catch {
            logger.warning("Failed to serialize API key verification request body: \(error.localizedDescription)")
            completion(false, "Failed to create verification request")
            return
        }
        
        logger.notice("🔑 Verifying API key for \(self.selectedProvider.rawValue, privacy: .public) provider at \(url.absoluteString, privacy: .public)")
        
        session.dataTask(with: request) { data, response, error in
            if let error = error {
                self.logger.notice("🔑 API key verification failed for \(self.selectedProvider.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)")
                completion(false, error.localizedDescription)
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                let isValid = httpResponse.statusCode == 200
                
                if !isValid {
                    // Log and return the exact API error response
                    if let data = data, let exactAPIError = String(data: data, encoding: .utf8) {
                        self.logger.notice("🔑 API key verification failed for \(self.selectedProvider.rawValue, privacy: .public) - Status: \(httpResponse.statusCode) - \(exactAPIError, privacy: .public)")
                        // Truncate error message to 500 characters to prevent UI overflow
                        let truncatedError = exactAPIError.count > 500 ? String(exactAPIError.prefix(500)) + "..." : exactAPIError
                        completion(false, truncatedError)
                    } else {
                        self.logger.notice("🔑 API key verification failed for \(self.selectedProvider.rawValue, privacy: .public) - Status: \(httpResponse.statusCode)")
                        completion(false, "Verification failed with status code \(httpResponse.statusCode)")
                    }
                } else {
                    completion(true, nil)
                }
            } else {
                self.logger.notice("🔑 API key verification failed for \(self.selectedProvider.rawValue, privacy: .public): Invalid response")
                completion(false, "Invalid response from server")
            }
        }.resume()
    }
    
    private func verifyAnthropicAPIKey(_ key: String, completion: @escaping (Bool, String?) -> Void) {
        guard let url = URL(string: self.selectedProvider.baseURL) else {
            logger.error("Invalid base URL for provider: \(self.selectedProvider.baseURL)")
            completion(false, "Invalid base URL for Anthropic")
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(key, forHTTPHeaderField: "x-api-key")
        request.addValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        
        let testBody: [String: Any] = [
            "model": currentModel,
            "max_tokens": 1024,
            "system": "You are a test system.",
            "messages": [
                ["role": "user", "content": "test"]
            ]
        ]
        
        // Log if JSON serialization fails (non-critical for verification)
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: testBody)
        } catch {
            logger.warning("Failed to serialize Anthropic API key verification request body: \(error.localizedDescription)")
            completion(false, "Failed to create verification request")
            return
        }
        
        session.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(false, error.localizedDescription)
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 {
                    completion(true, nil)
                } else {
                    if let data = data, let responseString = String(data: data, encoding: .utf8) {
                        // Truncate error message to 500 characters to prevent UI overflow
                        let truncatedError = responseString.count > 500 ? String(responseString.prefix(500)) + "..." : responseString
                        completion(false, truncatedError)
                    } else {
                        completion(false, "Verification failed with status code \(httpResponse.statusCode)")
                    }
                }
            } else {
                completion(false, "Invalid response from server")
            }
        }.resume()
    }
    
    private func verifyElevenLabsAPIKey(_ key: String, completion: @escaping (Bool, String?) -> Void) {
        guard let url = URL(string: "https://api.elevenlabs.io/v1/user") else {
            logger.error("Invalid ElevenLabs API URL")
            completion(false, "Invalid ElevenLabs API URL")
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(key, forHTTPHeaderField: "xi-api-key")

        session.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(false, error.localizedDescription)
                return
            }
            
            let isValid = (response as? HTTPURLResponse)?.statusCode == 200

            if let data = data, let body = String(data: data, encoding: .utf8) {
                self.logger.info("ElevenLabs verification response: \(body)")
                if !isValid {
                    // Truncate error message to 500 characters to prevent UI overflow
                    let truncatedError = body.count > 500 ? String(body.prefix(500)) + "..." : body
                    completion(false, truncatedError)
                    return
                }
            }

            completion(isValid, nil)
        }.resume()
    }
    
    private func verifyMistralAPIKey(_ key: String, completion: @escaping (Bool, String?) -> Void) {
        guard let url = URL(string: "https://api.mistral.ai/v1/models") else {
            logger.error("Invalid Mistral API URL")
            completion(false, "Invalid Mistral API URL")
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        
        session.dataTask(with: request) { data, response, error in
            if let error = error {
                self.logger.error("Mistral API key verification failed: \(error.localizedDescription)")
                completion(false, error.localizedDescription)
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 {
                    completion(true, nil)
                } else {
                    if let data = data, let body = String(data: data, encoding: .utf8) {
                        self.logger.error("Mistral API key verification failed with status code \(httpResponse.statusCode): \(body)")
                        // Truncate error message to 500 characters to prevent UI overflow
                        let truncatedError = body.count > 500 ? String(body.prefix(500)) + "..." : body
                        completion(false, truncatedError)
                    } else {
                        self.logger.error("Mistral API key verification failed with status code \(httpResponse.statusCode) and no response body.")
                        completion(false, "Verification failed with status code \(httpResponse.statusCode)")
                    }
                }
            } else {
                self.logger.error("Mistral API key verification failed: Invalid response from server.")
                completion(false, "Invalid response from server")
            }
        }.resume()
    }

    private func verifyDeepgramAPIKey(_ key: String, completion: @escaping (Bool, String?) -> Void) {
        guard let url = URL(string: "https://api.deepgram.com/v1/auth/token") else {
            logger.error("Invalid Deepgram API URL")
            completion(false, "Invalid Deepgram API URL")
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("Token \(key)", forHTTPHeaderField: "Authorization")
        
        session.dataTask(with: request) { data, response, error in
            if let error = error {
                self.logger.error("Deepgram API key verification failed: \(error.localizedDescription)")
                completion(false, error.localizedDescription)
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 {
                    completion(true, nil)
                } else {
                    if let data = data, let responseString = String(data: data, encoding: .utf8) {
                        // Truncate error message to 500 characters to prevent UI overflow
                        let truncatedError = responseString.count > 500 ? String(responseString.prefix(500)) + "..." : responseString
                        completion(false, truncatedError)
                    } else {
                        completion(false, "Verification failed with status code \(httpResponse.statusCode)")
                    }
                }
            } else {
                completion(false, "Invalid response from server")
            }
        }.resume()
    }
    
    private func verifySonioxAPIKey(_ key: String, completion: @escaping (Bool, String?) -> Void) {
        guard let url = URL(string: "https://api.soniox.com/v1/files") else {
            completion(false, "Invalid Soniox API URL")
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        
        session.dataTask(with: request) { data, response, error in
            if let error = error {
                self.logger.error("Soniox API key verification failed: \(error.localizedDescription)")
                completion(false, error.localizedDescription)
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 {
                    completion(true, nil)
                } else {
                    if let data = data, let responseString = String(data: data, encoding: .utf8) {
                        // Truncate error message to 500 characters to prevent UI overflow
                        let truncatedError = responseString.count > 500 ? String(responseString.prefix(500)) + "..." : responseString
                        completion(false, truncatedError)
                    } else {
                        completion(false, "Verification failed with status code \(httpResponse.statusCode)")
                    }
                }
            } else {
                completion(false, "Invalid response from server")
            }
        }.resume()
    }
    
    private func verifyAssemblyAIAPIKey(_ key: String, completion: @escaping (Bool, String?) -> Void) {
        guard let url = URL(string: "https://api.assemblyai.com/v2/transcript") else {
            logger.error("Invalid AssemblyAI API URL")
            completion(false, "Invalid AssemblyAI API URL")
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue(key, forHTTPHeaderField: "authorization")
        
        session.dataTask(with: request) { data, response, error in
            if let error = error {
                self.logger.error("AssemblyAI API key verification failed: \(error.localizedDescription)")
                completion(false, error.localizedDescription)
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                // AssemblyAI returns 200 for valid API keys (returns list of transcripts)
                // Returns 401 for invalid keys
                let isValid = httpResponse.statusCode == 200
                if isValid {
                    completion(true, nil)
                } else {
                    if let data = data, let body = String(data: data, encoding: .utf8) {
                        self.logger.error("AssemblyAI API key verification failed with status \(httpResponse.statusCode): \(body)")
                        // Truncate error message to 500 characters to prevent UI overflow
                        let truncatedError = body.count > 500 ? String(body.prefix(500)) + "..." : body
                        completion(false, truncatedError)
                    } else {
                        completion(false, "Verification failed with status code \(httpResponse.statusCode)")
                    }
                }
            } else {
                completion(false, "Invalid response from server")
            }
        }.resume()
    }
    
    func clearAPIKey() {
        guard selectedProvider.requiresAPIKey else { return }
        
        apiKey = ""
        isAPIKeyValid = false
        try? keychain.deleteAPIKey(for: selectedProvider.rawValue)
        NotificationCenter.default.post(name: .aiProviderKeyChanged, object: nil)
    }
    
    func checkOllamaConnection(completion: @escaping (Bool) -> Void) {
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            await self.ollamaService.checkConnection()
            // No need for DispatchQueue - already on MainActor
            completion(self.ollamaService.isConnected)
        }
    }
    
    func fetchOllamaModels() async -> [OllamaService.OllamaModel] {
        await ollamaService.refreshModels()
        return ollamaService.availableModels
    }
    
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
    
    func updateOllamaBaseURL(_ newURL: String) {
        ollamaService.baseURL = newURL
        userDefaults.set(newURL, forKey: "ollamaBaseURL")
    }
    
    func updateSelectedOllamaModel(_ modelName: String) {
        ollamaService.selectedModel = modelName
        userDefaults.set(modelName, forKey: "ollamaSelectedModel")
    }
    
    func fetchOpenRouterModels() async {
        guard let url = URL(string: "https://openrouter.ai/api/v1/models") else {
            logger.error("Invalid OpenRouter API URL")
            // No need for MainActor.run - this class is already @MainActor
            self.openRouterModels = []
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
                self.openRouterModels = []
                self.saveOpenRouterModels()
                self.objectWillChange.send()
                return
            }
            
            guard let jsonResponse = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let dataArray = jsonResponse["data"] as? [[String: Any]] else {
                logger.error("Failed to parse OpenRouter models JSON")
                self.openRouterModels = []
                self.saveOpenRouterModels()
                self.objectWillChange.send()
                return
            }
            
            let models = dataArray.compactMap { $0["id"] as? String }
            self.openRouterModels = models.sorted()
            self.saveOpenRouterModels() // Save to UserDefaults
            if self.selectedProvider == .openRouter && self.currentModel == self.selectedProvider.defaultModel && !models.isEmpty {
                self.selectModel(models.sorted().first!)
            }
            self.objectWillChange.send()
            logger.info("Successfully fetched \(models.count) OpenRouter models.")
            
        } catch {
            logger.error("Error fetching OpenRouter models: \(error.localizedDescription)")
            self.openRouterModels = []
            self.saveOpenRouterModels()
            self.objectWillChange.send()
        }
    }
}


