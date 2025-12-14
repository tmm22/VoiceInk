import Foundation
import SwiftData
import AppKit
import os

enum EnhancementPrompt {
    case transcriptionEnhancement
    case aiAssistant
}

@MainActor
class AIEnhancementService: ObservableObject {
    private let logger = Logger(subsystem: "com.tmm22.voicelinkcommunity", category: "AIEnhancementService")

    @Published var isEnhancementEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnhancementEnabled, forKey: "isAIEnhancementEnabled")
            if isEnhancementEnabled && selectedPromptId == nil {
                selectedPromptId = customPrompts.first?.id
            }
            NotificationCenter.default.post(name: .AppSettingsDidChange, object: nil)
            NotificationCenter.default.post(name: .enhancementToggleChanged, object: nil)
        }
    }

    @Published var contextSettings: AIContextSettings {
        didSet {
            if let encoded = try? JSONEncoder().encode(contextSettings) {
                UserDefaults.standard.set(encoded, forKey: "aiContextSettings")
            }
        }
    }
    
    // Backward compatibility properties (mapped to contextSettings)
    var useClipboardContext: Bool {
        get { contextSettings.includeClipboard }
        set { contextSettings.includeClipboard = newValue }
    }

    var useScreenCaptureContext: Bool {
        get { contextSettings.includeScreenCapture }
        set { contextSettings.includeScreenCapture = newValue }
    }

    @Published var customPrompts: [CustomPrompt] {
        didSet {
            do {
                let encoded = try JSONEncoder().encode(customPrompts)
                UserDefaults.standard.set(encoded, forKey: "customPrompts")
            } catch {
                logger.error("Failed to encode custom prompts for persistence: \(error.localizedDescription)")
            }
        }
    }

    @Published var selectedPromptId: UUID? {
        didSet {
            UserDefaults.standard.set(selectedPromptId?.uuidString, forKey: "selectedPromptId")
            NotificationCenter.default.post(name: .AppSettingsDidChange, object: nil)
            NotificationCenter.default.post(name: .promptSelectionChanged, object: nil)
        }
    }

    @Published var lastSystemMessageSent: String?
    @Published var lastUserMessageSent: String?
    @Published var lastCapturedContextJSON: String?
    
    @Published var requestTimeout: TimeInterval {
        didSet {
            UserDefaults.standard.set(requestTimeout, forKey: "aiEnhancementTimeout")
            NotificationCenter.default.post(name: .AppSettingsDidChange, object: nil)
        }
    }
    
    @Published var reasoningEffort: ReasoningEffort {
        didSet {
            UserDefaults.standard.set(reasoningEffort.rawValue, forKey: "aiReasoningEffort")
            NotificationCenter.default.post(name: .AppSettingsDidChange, object: nil)
        }
    }
    
    // Timeout configuration constants
    static let defaultTimeout: TimeInterval = 30
    static let minimumTimeout: TimeInterval = 10
    static let maximumTimeout: TimeInterval = 300  // 5 minutes
    
    // Default reasoning effort
    static let defaultReasoningEffort: ReasoningEffort = .low

    var activePrompt: CustomPrompt? {
        allPrompts.first { $0.id == selectedPromptId }
    }

    var allPrompts: [CustomPrompt] {
        return customPrompts
    }

    private let aiService: AIService
    private let customVocabularyService: CustomVocabularyService
    private let rateLimitInterval: TimeInterval = 1.0
    private var lastRequestTime: Date?
    private let modelContext: ModelContext
    private let session = SecureURLSession.makeEphemeral()
    
    // New Context Components
    let contextBuilder: AIContextBuilder
    let contextRenderer: AIContextRenderer

    init(aiService: AIService? = nil, modelContext: ModelContext) {
        self.aiService = aiService ?? AIService()
        self.modelContext = modelContext
        self.customVocabularyService = CustomVocabularyService.shared
        self.contextBuilder = AIContextBuilder(modelContext: modelContext)
        self.contextRenderer = AIContextRenderer()

        self.isEnhancementEnabled = UserDefaults.standard.bool(forKey: "isAIEnhancementEnabled")
        
        // Load Context Settings
        if let data = UserDefaults.standard.data(forKey: "aiContextSettings"),
           let settings = try? JSONDecoder().decode(AIContextSettings.self, from: data) {
            self.contextSettings = settings
        } else {
            // Migration from legacy keys
            var settings = AIContextSettings()
            settings.includeClipboard = UserDefaults.standard.bool(forKey: "useClipboardContext")
            settings.includeScreenCapture = UserDefaults.standard.bool(forKey: "useScreenCaptureContext")
            self.contextSettings = settings
        }
        
        // Load timeout setting, defaulting to 30 seconds
        let savedTimeout = UserDefaults.standard.double(forKey: "aiEnhancementTimeout")
        self.requestTimeout = savedTimeout > 0 ? savedTimeout : Self.defaultTimeout
        
        // Load reasoning effort setting, defaulting to "low"
        if let savedEffort = UserDefaults.standard.string(forKey: "aiReasoningEffort"),
           let effort = ReasoningEffort(rawValue: savedEffort) {
            self.reasoningEffort = effort
        } else {
            self.reasoningEffort = Self.defaultReasoningEffort
        }

        if let savedPromptsData = UserDefaults.standard.data(forKey: "customPrompts"),
           let decodedPrompts = try? JSONDecoder().decode([CustomPrompt].self, from: savedPromptsData) {
            self.customPrompts = decodedPrompts
        } else {
            self.customPrompts = []
        }

        if let savedPromptId = UserDefaults.standard.string(forKey: "selectedPromptId") {
            self.selectedPromptId = UUID(uuidString: savedPromptId)
        }

        if isEnhancementEnabled && (selectedPromptId == nil || !allPrompts.contains(where: { $0.id == selectedPromptId })) {
            self.selectedPromptId = allPrompts.first?.id
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAPIKeyChange),
            name: .aiProviderKeyChanged,
            object: nil
        )

        initializePredefinedPrompts()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func handleAPIKeyChange() {
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            self.objectWillChange.send()
            if !self.aiService.isAPIKeyValid {
                self.isEnhancementEnabled = false
            }
        }
    }

    func getAIService() -> AIService? {
        return aiService
    }

    var isConfigured: Bool {
        aiService.isAPIKeyValid
    }

    private func waitForRateLimit() async throws {
        if let lastRequest = lastRequestTime {
            let timeSinceLastRequest = Date().timeIntervalSince(lastRequest)
            if timeSinceLastRequest < rateLimitInterval {
                try await Task.sleep(nanoseconds: UInt64((rateLimitInterval - timeSinceLastRequest) * 1_000_000_000))
            }
        }
        lastRequestTime = Date()
    }

    private func getSystemMessage(
        for mode: EnhancementPrompt,
        transcriptionModel: String,
        recordingDuration: TimeInterval,
        language: String
    ) async -> String {
        
        let promptName = activePrompt?.title
        
        let context = await contextBuilder.buildContext(
            settings: contextSettings,
            recordingDuration: recordingDuration,
            transcriptionModel: transcriptionModel,
            language: language,
            provider: aiService.selectedProvider.rawValue,
            model: aiService.currentModel,
            promptName: promptName
        )
        
        // Serialize context for debugging/storage
        if let jsonData = try? JSONEncoder().encode(context),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            self.lastCapturedContextJSON = jsonString
        }
        
        let contextXML = contextRenderer.render(context)
        
        // Use Dynamic Prompt Generation for Intent Awareness
        if let activePrompt = activePrompt {
            if activePrompt.id == PredefinedPrompts.assistantPromptId {
                // Assistant mode is special, keep it as is or migrate later
                return activePrompt.promptText + "\n\n" + contextXML
            } else {
                // Use dynamic generation if system instructions are enabled
                if activePrompt.useSystemInstructions {
                    return AIPrompts.generateDynamicSystemPrompt(
                        userInstruction: activePrompt.promptText,
                        context: context
                    ) + "\n\n" + contextXML
                } else {
                    return activePrompt.promptText + "\n\n" + contextXML
                }
            }
        } else {
            // Default prompt logic
            let defaultPromptText = "Enhance the following text."
            return AIPrompts.generateDynamicSystemPrompt(
                userInstruction: defaultPromptText,
                context: context
            ) + "\n\n" + contextXML
        }
    }

    private func makeRequest(
        text: String,
        mode: EnhancementPrompt,
        transcriptionModel: String,
        recordingDuration: TimeInterval,
        language: String
    ) async throws -> String {
        guard isConfigured else {
            throw EnhancementError.notConfigured
        }

        guard !text.isEmpty else {
            return ""
        }

        let formattedText = "\n<TRANSCRIPT>\n\(text)\n</TRANSCRIPT>"
        
        let systemMessage = await getSystemMessage(
            for: mode,
            transcriptionModel: transcriptionModel,
            recordingDuration: recordingDuration,
            language: language
        )
        
        self.lastSystemMessageSent = systemMessage
        self.lastUserMessageSent = formattedText

        logger.notice("AI Enhancement - System Message: \(systemMessage, privacy: .public)")
        
        if aiService.selectedProvider == .ollama {
            do {
                let result = try await aiService.enhanceWithOllama(text: formattedText, systemPrompt: systemMessage, timeout: requestTimeout)
                let filteredResult = AIEnhancementOutputFilter.filter(result)
                return filteredResult
            } catch {
                if let localError = error as? LocalAIError {
                    throw EnhancementError.customError(localError.errorDescription ?? "An unknown Ollama error occurred.")
                } else {
                    throw EnhancementError.customError(error.localizedDescription)
                }
            }
        }

        try await waitForRateLimit()

        switch aiService.selectedProvider {
        case .anthropic:
            let requestBody: [String: Any] = [
                "model": aiService.currentModel,
                "max_tokens": 8192,
                "system": systemMessage,
                "messages": [
                    ["role": "user", "content": formattedText]
                ]
            ]

            guard let url = URL(string: aiService.selectedProvider.baseURL) else {
                throw NSError(domain: "AIEnhancementService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid API URL"])
            }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.addValue(aiService.apiKey, forHTTPHeaderField: "x-api-key")
            request.addValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            request.timeoutInterval = requestTimeout
            do {
                request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
            } catch {
                throw EnhancementError.customError("Failed to prepare request: \(error.localizedDescription)")
            }

            do {
                let (data, response) = try await session.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw EnhancementError.invalidResponse
                }

                if httpResponse.statusCode == 200 {
                    guard let jsonResponse = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let content = jsonResponse["content"] as? [[String: Any]],
                          let firstContent = content.first,
                          let enhancedText = firstContent["text"] as? String else {
                        throw EnhancementError.enhancementFailed
                    }

                    let filteredText = AIEnhancementOutputFilter.filter(enhancedText.trimmingCharacters(in: .whitespacesAndNewlines))
                    return filteredText
                } else if httpResponse.statusCode == 429 {
                    throw EnhancementError.rateLimitExceeded
                } else if (500...599).contains(httpResponse.statusCode) {
                    throw EnhancementError.serverError
                } else {
                    let errorString = String(data: data, encoding: .utf8) ?? "Could not decode error response."
                    throw EnhancementError.customError("HTTP \(httpResponse.statusCode): \(errorString)")
                }

            } catch let error as EnhancementError {
                throw error
            } catch let error as URLError {
                throw error
            } catch {
                throw EnhancementError.customError(error.localizedDescription)
            }

        default:
            guard let url = URL(string: aiService.selectedProvider.baseURL) else {
                throw NSError(domain: "AIEnhancementService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid API URL"])
            }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.addValue("Bearer \(aiService.apiKey)", forHTTPHeaderField: "Authorization")
            request.timeoutInterval = requestTimeout

            let messages: [[String: Any]] = [
                ["role": "system", "content": systemMessage],
                ["role": "user", "content": formattedText]
            ]

            var requestBody: [String: Any] = [
                "model": aiService.currentModel,
                "messages": messages,
                "temperature": aiService.currentModel.lowercased().hasPrefix("gpt-5") ? 1.0 : 0.3,
                "stream": false
            ]

            if let reasoningParam = ReasoningConfig.getReasoningParameter(for: aiService.currentModel, userPreference: reasoningEffort) {
                requestBody["reasoning_effort"] = reasoningParam
            }

            do {
                request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
            } catch {
                throw EnhancementError.customError("Failed to prepare request: \(error.localizedDescription)")
            }

            do {
                let (data, response) = try await session.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw EnhancementError.invalidResponse
                }

                if httpResponse.statusCode == 200 {
                    guard let jsonResponse = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let choices = jsonResponse["choices"] as? [[String: Any]],
                          let firstChoice = choices.first,
                          let message = firstChoice["message"] as? [String: Any],
                          let enhancedText = message["content"] as? String else {
                        throw EnhancementError.enhancementFailed
                    }

                    let filteredText = AIEnhancementOutputFilter.filter(enhancedText.trimmingCharacters(in: .whitespacesAndNewlines))
                    return filteredText
                } else if httpResponse.statusCode == 429 {
                    throw EnhancementError.rateLimitExceeded
                } else if (500...599).contains(httpResponse.statusCode) {
                    throw EnhancementError.serverError
                } else {
                    let errorString = String(data: data, encoding: .utf8) ?? "Could not decode error response."
                    throw EnhancementError.customError("HTTP \(httpResponse.statusCode): \(errorString)")
                }
            } catch let error as EnhancementError {
                throw error
            } catch let error as URLError {
                throw error
            } catch {
                throw EnhancementError.customError(error.localizedDescription)
            }
        }
    }

    private func makeRequestWithRetry(
        text: String,
        mode: EnhancementPrompt,
        transcriptionModel: String,
        recordingDuration: TimeInterval,
        language: String,
        maxRetries: Int = 3,
        initialDelay: TimeInterval = 1.0
    ) async throws -> String {
        var retries = 0
        var currentDelay = initialDelay

        while retries < maxRetries {
            do {
                return try await makeRequest(
                    text: text,
                    mode: mode,
                    transcriptionModel: transcriptionModel,
                    recordingDuration: recordingDuration,
                    language: language
                )
            } catch let error as EnhancementError {
                switch error {
                case .networkError, .serverError, .rateLimitExceeded:
                    retries += 1
                    if retries < maxRetries {
                        logger.warning("Request failed, retrying in \(currentDelay)s... (Attempt \(retries)/\(maxRetries))")
                        try await Task.sleep(nanoseconds: UInt64(currentDelay * 1_000_000_000))
                        currentDelay *= 2
                    } else {
                        throw error
                    }
                default:
                    throw error
                }
            } catch {
                let nsError = error as NSError
                if nsError.domain == NSURLErrorDomain && [NSURLErrorNotConnectedToInternet, NSURLErrorTimedOut, NSURLErrorNetworkConnectionLost].contains(nsError.code) {
                    retries += 1
                    if retries < maxRetries {
                        logger.warning("Request failed with network error, retrying in \(currentDelay)s... (Attempt \(retries)/\(maxRetries))")
                        try await Task.sleep(nanoseconds: UInt64(currentDelay * 1_000_000_000))
                        currentDelay *= 2
                    } else {
                        throw EnhancementError.networkError
                    }
                } else {
                    throw error
                }
            }
        }
        throw EnhancementError.enhancementFailed
    }

    func enhance(
        _ text: String,
        transcriptionModel: String = "Unknown",
        recordingDuration: TimeInterval = 0,
        language: String = "en"
    ) async throws -> (String, TimeInterval, String?) {
        let startTime = Date()
        let enhancementPrompt: EnhancementPrompt = .transcriptionEnhancement
        let promptName = activePrompt?.title

        do {
            let result = try await makeRequestWithRetry(
                text: text,
                mode: enhancementPrompt,
                transcriptionModel: transcriptionModel,
                recordingDuration: recordingDuration,
                language: language
            )
            let endTime = Date()
            let duration = endTime.timeIntervalSince(startTime)
            return (result, duration, promptName)
        } catch {
            throw error
        }
    }

    func captureContext() async {
        await contextBuilder.captureImmediateContext()
        self.objectWillChange.send()
    }
    
    // Deprecated methods kept for compatibility but redirected
    func captureScreenContext() async {
        await contextBuilder.captureImmediateContext()
        self.objectWillChange.send()
    }

    func captureClipboardContext() {
        Task {
            await contextBuilder.captureImmediateContext()
        }
    }
    
    func clearCapturedContexts() {
        // Implementation for clearing would go here if ContextBuilder supports it
        // For now, it's state is overwritten on next capture
    }

    func addPrompt(title: String, promptText: String, icon: PromptIcon = "doc.text.fill", description: String? = nil, triggerWords: [String] = [], useSystemInstructions: Bool = true) {
        let newPrompt = CustomPrompt(title: title, promptText: promptText, icon: icon, description: description, isPredefined: false, triggerWords: triggerWords, useSystemInstructions: useSystemInstructions)
        customPrompts.append(newPrompt)
        if customPrompts.count == 1 {
            selectedPromptId = newPrompt.id
        }
    }

    func updatePrompt(_ prompt: CustomPrompt) {
        if let index = customPrompts.firstIndex(where: { $0.id == prompt.id }) {
            customPrompts[index] = prompt
        }
    }

    func deletePrompt(_ prompt: CustomPrompt) {
        customPrompts.removeAll { $0.id == prompt.id }
        if selectedPromptId == prompt.id {
            selectedPromptId = allPrompts.first?.id
        }
    }

    func setActivePrompt(_ prompt: CustomPrompt) {
        selectedPromptId = prompt.id
    }

    private func initializePredefinedPrompts() {
        let predefinedTemplates = PredefinedPrompts.createDefaultPrompts()

        for template in predefinedTemplates {
            if let existingIndex = customPrompts.firstIndex(where: { $0.id == template.id }) {
                var updatedPrompt = customPrompts[existingIndex]
                updatedPrompt = CustomPrompt(
                    id: updatedPrompt.id,
                    title: template.title,
                    promptText: template.promptText,
                    isActive: updatedPrompt.isActive,
                    icon: template.icon,
                    description: template.description,
                    isPredefined: true,
                    triggerWords: updatedPrompt.triggerWords,
                    useSystemInstructions: template.useSystemInstructions
                )
                customPrompts[existingIndex] = updatedPrompt
            } else {
                customPrompts.append(template)
            }
        }
    }
}

enum EnhancementError: Error {
    case notConfigured
    case invalidResponse
    case enhancementFailed
    case networkError
    case serverError
    case rateLimitExceeded
    case customError(String)
}

extension EnhancementError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "AI provider not configured. Please check your API key."
        case .invalidResponse:
            return "Invalid response from AI provider."
        case .enhancementFailed:
            return "AI enhancement failed to process the text."
        case .networkError:
            return "Network connection failed. Check your internet."
        case .serverError:
            return "The AI provider's server encountered an error. Please try again later."
        case .rateLimitExceeded:
            return "Rate limit exceeded. Please try again later."
        case .customError(let message):
            return message
        }
    }
}
