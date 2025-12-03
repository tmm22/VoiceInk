import SwiftUI

// MARK: - Configuration View

/// Configuration view for creating and editing Power Mode configurations.
/// Component views are organized in extension files:
/// - PowerModeConfigView+Sections.swift - Header, main input, trigger, transcription, AI enhancement, advanced, and save button sections
/// - PowerModeConfigView+Helpers.swift - Helper methods for app loading, website management, validation, and saving

struct ConfigurationView: View {
    let mode: ConfigurationMode
    let powerModeManager: PowerModeManager
    @EnvironmentObject var enhancementService: AIEnhancementService
    @EnvironmentObject var aiService: AIService
    @Environment(\.presentationMode) var presentationMode
    @FocusState var isNameFieldFocused: Bool
    
    // State for configuration
    @State var configName: String = "New Power Mode"
    @State var selectedEmoji: String = "💼"
    @State var isShowingEmojiPicker = false
    @State var isShowingAppPicker = false
    @State var isAIEnhancementEnabled: Bool
    @State var selectedPromptId: UUID?
    @State var selectedTranscriptionModelName: String?
    @State var selectedLanguage: String?
    @State var installedApps: [(url: URL, name: String, bundleId: String, icon: NSImage)] = []
    @State var searchText = ""
    
    // Validation state
    @State var validationErrors: [PowerModeValidationError] = []
    @State var showValidationAlert = false
    
    // New state for AI provider and model
    @State var selectedAIProvider: String?
    @State var selectedAIModel: String?
    
    // App and Website configurations
    @State var selectedAppConfigs: [AppConfig] = []
    @State var websiteConfigs: [URLConfig] = []
    @State var newWebsiteURL: String = ""
    
    // New state for screen capture toggle
    @State var useScreenCapture = false
    @State var isAutoSendEnabled = false
    @State var isDefault = false
    
    // State for prompt editing (similar to EnhancementSettingsView)
    @State var isEditingPrompt = false
    @State var selectedPromptForEdit: CustomPrompt?
    
    // Whisper state for model selection
    @EnvironmentObject var whisperState: WhisperState
    
    init(mode: ConfigurationMode, powerModeManager: PowerModeManager) {
        self.mode = mode
        self.powerModeManager = powerModeManager
        
        // Always fetch the most current configuration data
        switch mode {
        case .add:
            _isAIEnhancementEnabled = State(initialValue: true)
            _selectedPromptId = State(initialValue: nil)
            _selectedTranscriptionModelName = State(initialValue: nil)
            _selectedLanguage = State(initialValue: nil)
            _configName = State(initialValue: "")
            _selectedEmoji = State(initialValue: "✏️")
            _useScreenCapture = State(initialValue: false)
            _isAutoSendEnabled = State(initialValue: false)
            _isDefault = State(initialValue: false)
            // Default to current global AI provider/model for new configurations - use UserDefaults only
            _selectedAIProvider = State(initialValue: UserDefaults.standard.string(forKey: "selectedAIProvider"))
            _selectedAIModel = State(initialValue: nil) // Initialize to nil and set it after view appears
        case .edit(let config):
            // Get the latest version of this config from PowerModeManager
            let latestConfig = powerModeManager.getConfiguration(with: config.id) ?? config
            _isAIEnhancementEnabled = State(initialValue: latestConfig.isAIEnhancementEnabled)
            _selectedPromptId = State(initialValue: latestConfig.selectedPrompt.flatMap { UUID(uuidString: $0) })
            _selectedTranscriptionModelName = State(initialValue: latestConfig.selectedTranscriptionModelName)
            _selectedLanguage = State(initialValue: latestConfig.selectedLanguage)
            _configName = State(initialValue: latestConfig.name)
            _selectedEmoji = State(initialValue: latestConfig.emoji)
            _selectedAppConfigs = State(initialValue: latestConfig.appConfigs ?? [])
            _websiteConfigs = State(initialValue: latestConfig.urlConfigs ?? [])
            _useScreenCapture = State(initialValue: latestConfig.useScreenCapture)
            _isAutoSendEnabled = State(initialValue: latestConfig.isAutoSendEnabled)
            _isDefault = State(initialValue: latestConfig.isDefault)
            _selectedAIProvider = State(initialValue: latestConfig.selectedAIProvider)
            _selectedAIModel = State(initialValue: latestConfig.selectedAIModel)
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerSection
            
            Divider()
            
            ScrollView {
                VStack(spacing: 20) {
                    mainInputSection
                    triggerSection
                    transcriptionSection
                    aiEnhancementSection
                    advancedSection
                    saveButtonSection
                }
                .padding(.vertical)
            }
        }
        .sheet(isPresented: $isShowingAppPicker) {
            AppPickerSheet(
                installedApps: filteredApps,
                selectedAppConfigs: $selectedAppConfigs,
                searchText: $searchText,
                onDismiss: { isShowingAppPicker = false }
            )
        }
        .sheet(isPresented: $isEditingPrompt) {
            PromptEditorView(mode: .add)
        }
        .sheet(item: $selectedPromptForEdit) { prompt in
            PromptEditorView(mode: .edit(prompt))
        }
        .powerModeValidationAlert(errors: validationErrors, isPresented: $showValidationAlert)
        .navigationTitle("") // Explicitly set an empty title for this view
        .toolbar(.hidden) // Attempt to hide the navigation bar area
        .onAppear {
            // Set AI provider and model for new power modes after environment objects are available
            if case .add = mode {
                if selectedAIProvider == nil {
                    selectedAIProvider = aiService.selectedProvider.rawValue
                }
                if selectedAIModel == nil || selectedAIModel?.isEmpty == true {
                    selectedAIModel = aiService.currentModel
                }
            }
            
            // Select first prompt if AI enhancement is enabled and no prompt is selected
            if isAIEnhancementEnabled && selectedPromptId == nil {
                selectedPromptId = enhancementService.allPrompts.first?.id
            }
        }
    }
}
