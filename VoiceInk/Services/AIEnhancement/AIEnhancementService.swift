import Foundation
import SwiftData
import AppKit
import os

@MainActor
class AIEnhancementService: ObservableObject {
    
    // MARK: - Logger
    let logger = Logger(subsystem: "com.tmm22.voicelinkcommunity", category: "AIEnhancementService")

    // MARK: - Published Properties
    
    @Published var isEnhancementEnabled: Bool {
        didSet {
            AppSettings.Enhancements.isEnhancementEnabled = isEnhancementEnabled
            if isEnhancementEnabled && selectedPromptId == nil {
                selectedPromptId = customPrompts.first?.id
            }
            NotificationCenter.default.post(name: .enhancementToggleChanged, object: nil)
        }
    }

    @Published var contextSettings: AIContextSettings {
        didSet {
            // Best-effort persistence; encoding failure is non-critical as defaults will be used on next launch
            if let encoded = try? JSONEncoder().encode(contextSettings) {
                AppSettings.Enhancements.contextSettingsData = encoded
            }
        }
    }
    
    @Published var customPrompts: [CustomPrompt] {
        didSet {
            do {
                let encoded = try JSONEncoder().encode(customPrompts)
                AppSettings.Enhancements.customPromptsData = encoded
            } catch {
                logger.error("Failed to encode custom prompts for persistence: \(error.localizedDescription)")
            }
        }
    }

    @Published var selectedPromptId: UUID? {
        didSet {
            AppSettings.Enhancements.selectedPromptId = selectedPromptId?.uuidString
            NotificationCenter.default.post(name: .promptSelectionChanged, object: nil)
        }
    }

    @Published var lastSystemMessageSent: String?
    @Published var lastUserMessageSent: String?
    @Published var lastCapturedContextJSON: String?
    
    @Published var requestTimeout: TimeInterval {
        didSet {
            AppSettings.Enhancements.requestTimeout = requestTimeout
        }
    }
    
    @Published var reasoningEffort: ReasoningEffort {
        didSet {
            AppSettings.Enhancements.reasoningEffortRawValue = reasoningEffort.rawValue
        }
    }
    
    // MARK: - Backward Compatibility Properties
    
    var useClipboardContext: Bool {
        get { contextSettings.includeClipboard }
        set { contextSettings.includeClipboard = newValue }
    }

    var useScreenCaptureContext: Bool {
        get { contextSettings.includeScreenCapture }
        set { contextSettings.includeScreenCapture = newValue }
    }
    
    // MARK: - Constants
    
    static let defaultTimeout: TimeInterval = 30
    static let minimumTimeout: TimeInterval = 10
    static let maximumTimeout: TimeInterval = 300  // 5 minutes
    static let defaultReasoningEffort: ReasoningEffort = .low
    
    let maxStoredMessageCharacters = 50_000
    let maxStoredContextCharacters = 50_000

    // MARK: - Computed Properties
    
    var activePrompt: CustomPrompt? {
        allPrompts.first { $0.id == selectedPromptId }
    }

    var allPrompts: [CustomPrompt] {
        return customPrompts
    }
    
    var isConfigured: Bool {
        aiService.isAPIKeyValid
    }

    // MARK: - Private Properties
    
    let aiService: AIService
    private let customVocabularyService: CustomVocabularyService
    let rateLimitInterval: TimeInterval = 1.0
    var lastRequestTime: Date?
    private let modelContext: ModelContext
    let session = SecureURLSession.makeEphemeral()
    
    // MARK: - Context Components
    
    let contextBuilder: AIContextBuilder
    let contextRenderer: AIContextRenderer

    // MARK: - Initialization
    
    init(aiService: AIService? = nil, modelContext: ModelContext) {
        self.aiService = aiService ?? AIService()
        self.modelContext = modelContext
        self.customVocabularyService = CustomVocabularyService.shared
        self.contextBuilder = AIContextBuilder(modelContext: modelContext)
        self.contextRenderer = AIContextRenderer()

        self.isEnhancementEnabled = AppSettings.Enhancements.isEnhancementEnabled
        
        // Load Context Settings
        // Decode failure is acceptable; will use default settings if stored data is corrupted
        if let data = AppSettings.Enhancements.contextSettingsData,
           let settings = try? JSONDecoder().decode(AIContextSettings.self, from: data) {
            self.contextSettings = settings
        } else {
            // Migration from legacy keys
            var settings = AIContextSettings()
            settings.includeClipboard = AppSettings.Enhancements.useClipboardContext
            settings.includeScreenCapture = AppSettings.Enhancements.useScreenCaptureContext
            self.contextSettings = settings
        }
        
        // Load timeout setting
        let savedTimeout = AppSettings.Enhancements.requestTimeout
        self.requestTimeout = savedTimeout > 0 ? savedTimeout : Self.defaultTimeout
        
        // Load reasoning effort setting
        if let savedEffort = AppSettings.Enhancements.reasoningEffortRawValue,
           let effort = ReasoningEffort(rawValue: savedEffort) {
            self.reasoningEffort = effort
        } else {
            self.reasoningEffort = Self.defaultReasoningEffort
        }

        // Load custom prompts
        // Decode failure is acceptable; will use empty prompts array if stored data is corrupted
        if let savedPromptsData = AppSettings.Enhancements.customPromptsData,
           let decodedPrompts = try? JSONDecoder().decode([CustomPrompt].self, from: savedPromptsData) {
            self.customPrompts = decodedPrompts
        } else {
            self.customPrompts = []
        }

        // Load selected prompt
        if let savedPromptId = AppSettings.Enhancements.selectedPromptId {
            self.selectedPromptId = UUID(uuidString: savedPromptId)
        }

        // Ensure valid prompt selection
        if isEnhancementEnabled && (selectedPromptId == nil || !allPrompts.contains(where: { $0.id == selectedPromptId })) {
            self.selectedPromptId = allPrompts.first?.id
        }

        // Register for API key changes
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

    // MARK: - Public Methods
    
    func getAIService() -> AIService? {
        return aiService
    }
    
    /// Main enhancement method
    /// - Parameters:
    ///   - text: The text to enhance
    ///   - transcriptionModel: The transcription model used
    ///   - recordingDuration: Duration of the recording
    ///   - language: Language code
    /// - Returns: Tuple of (enhanced text, duration, prompt name)
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

    /// Captures context for AI enhancement
    func captureContext() async {
        await contextBuilder.captureImmediateContext()
        self.objectWillChange.send()
    }
    
    // MARK: - Deprecated Methods (kept for compatibility)
    
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
        // Context state is overwritten on next capture
    }

    // MARK: - Internal Methods
    
    func waitForRateLimit() async throws {
        if let lastRequest = lastRequestTime {
            let timeSinceLastRequest = Date().timeIntervalSince(lastRequest)
            if timeSinceLastRequest < rateLimitInterval {
                try await Task.sleep(nanoseconds: UInt64((rateLimitInterval - timeSinceLastRequest) * 1_000_000_000))
            }
        }
        lastRequestTime = Date()
    }

    func getSystemMessage(
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
        // Encoding failure is non-critical; debug context is optional
        if let jsonData = try? JSONEncoder().encode(context),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            self.lastCapturedContextJSON = truncateForStorage(jsonString, limit: maxStoredContextCharacters)
        }
        
        let contextXML = contextRenderer.render(context)
        
        // Use Dynamic Prompt Generation for Intent Awareness
        if let activePrompt = activePrompt {
            if activePrompt.id == PredefinedPrompts.assistantPromptId {
                // Assistant mode is special, keep it as is
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

    func truncateForStorage(_ text: String, limit: Int) -> String {
        guard limit > 0, text.count > limit else { return text }
        return String(text.prefix(limit)) + "...[TRUNCATED]"
    }

    // MARK: - Private Methods
    
    @objc private func handleAPIKeyChange() {
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            self.objectWillChange.send()
            if !self.aiService.isAPIKeyValid {
                self.isEnhancementEnabled = false
            }
        }
    }
}
