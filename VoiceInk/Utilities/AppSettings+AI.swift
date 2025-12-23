import Foundation

extension AppSettings {
    enum Ollama {
        static let defaultBaseURL = "http://localhost:11434"
        static let defaultModel = "mistral"

        static var baseURL: String {
            get { defaults.string(forKey: Keys.ollamaBaseURL) ?? defaultBaseURL }
            set { setValue(newValue, forKey: Keys.ollamaBaseURL) }
        }

        static var selectedModel: String {
            get { defaults.string(forKey: Keys.ollamaSelectedModel) ?? defaultModel }
            set { setValue(newValue, forKey: Keys.ollamaSelectedModel) }
        }
    }

    enum AI {
        static var selectedProviderRawValue: String? {
            get { defaults.string(forKey: Keys.aiSelectedProvider) }
            set { updateString(newValue, forKey: Keys.aiSelectedProvider) }
        }

        static var customProviderBaseURL: String {
            get { defaults.string(forKey: Keys.aiCustomProviderBaseURL) ?? "" }
            set { setValue(newValue, forKey: Keys.aiCustomProviderBaseURL) }
        }

        static var customProviderModel: String {
            get { defaults.string(forKey: Keys.aiCustomProviderModel) ?? "" }
            set { setValue(newValue, forKey: Keys.aiCustomProviderModel) }
        }

        static var openRouterModels: [String] {
            get { defaults.array(forKey: Keys.aiOpenRouterModels) as? [String] ?? [] }
            set { setValue(newValue, forKey: Keys.aiOpenRouterModels) }
        }

        static func selectedModelKey(for providerRawValue: String) -> String {
            "\(providerRawValue)SelectedModel"
        }
    }

    enum Enhancements {
        static var isEnhancementEnabled: Bool {
            get { bool(forKey: Keys.aiEnhancementEnabled, default: false) }
            set { setValue(newValue, forKey: Keys.aiEnhancementEnabled) }
        }

        static var contextSettingsData: Data? {
            get { defaults.data(forKey: Keys.aiContextSettings) }
            set { updateValue(newValue, forKey: Keys.aiContextSettings) }
        }

        static var customPromptsData: Data? {
            get { defaults.data(forKey: Keys.aiCustomPrompts) }
            set { updateValue(newValue, forKey: Keys.aiCustomPrompts) }
        }

        static var selectedPromptId: String? {
            get { defaults.string(forKey: Keys.aiSelectedPromptId) }
            set { updateString(newValue, forKey: Keys.aiSelectedPromptId) }
        }

        static var requestTimeout: Double {
            get { double(forKey: Keys.aiEnhancementTimeout, default: 0) }
            set { setValue(newValue, forKey: Keys.aiEnhancementTimeout) }
        }

        static var reasoningEffortRawValue: String? {
            get { defaults.string(forKey: Keys.aiReasoningEffort) }
            set { updateString(newValue, forKey: Keys.aiReasoningEffort) }
        }

        static var useClipboardContext: Bool {
            get { bool(forKey: Keys.useClipboardContext, default: false) }
            set { setValue(newValue, forKey: Keys.useClipboardContext) }
        }

        static var useScreenCaptureContext: Bool {
            get { bool(forKey: Keys.useScreenCaptureContext, default: false) }
            set { setValue(newValue, forKey: Keys.useScreenCaptureContext) }
        }
    }

    enum Shortcuts {
        static var isToggleEnhancementShortcutEnabled: Bool {
            get { bool(forKey: Keys.enhancementShortcutEnabled, default: true) }
            set { setValue(newValue, forKey: Keys.enhancementShortcutEnabled) }
        }
    }

    enum QuickRules {
        static var isEnabled: Bool {
            get { bool(forKey: Keys.quickRulesEnabled, default: false) }
            set { setValue(newValue, forKey: Keys.quickRulesEnabled) }
        }

        static var rulesData: Data? {
            get { defaults.data(forKey: Keys.quickRulesData) }
            set { updateValue(newValue, forKey: Keys.quickRulesData) }
        }
    }
}
