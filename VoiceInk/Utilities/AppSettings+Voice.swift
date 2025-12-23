import Foundation

extension AppSettings {
    enum TTS {
        static var selectedProviderRawValue: String? {
            get { defaults.string(forKey: Keys.ttsSelectedProvider) }
            set { updateString(newValue, forKey: Keys.ttsSelectedProvider) }
        }

        static var playbackSpeed: Double? {
            get { doubleValue(forKey: Keys.ttsPlaybackSpeed) }
            set { updateValue(newValue, forKey: Keys.ttsPlaybackSpeed) }
        }

        static var volume: Double? {
            get { doubleValue(forKey: Keys.ttsVolume) }
            set { updateValue(newValue, forKey: Keys.ttsVolume) }
        }

        static var isLoopEnabled: Bool? {
            get { boolValue(forKey: Keys.ttsLoopEnabled) }
            set { updateValue(newValue, forKey: Keys.ttsLoopEnabled) }
        }

        static var isMinimalistMode: Bool? {
            get { boolValue(forKey: Keys.ttsIsMinimalistMode) }
            set { updateValue(newValue, forKey: Keys.ttsIsMinimalistMode) }
        }

        static var selectedAudioFormatRawValue: String? {
            get { defaults.string(forKey: Keys.ttsAudioFormat) }
            set { updateString(newValue, forKey: Keys.ttsAudioFormat) }
        }

        static var appearancePreferenceRawValue: String? {
            get { defaults.string(forKey: Keys.ttsAppearancePreference) }
            set { updateString(newValue, forKey: Keys.ttsAppearancePreference) }
        }

        static var notificationsEnabled: Bool? {
            get { boolValue(forKey: Keys.ttsNotificationsEnabled) }
            set { updateValue(newValue, forKey: Keys.ttsNotificationsEnabled) }
        }

        static var inspectorEnabled: Bool? {
            get { boolValue(forKey: Keys.ttsInspectorEnabled) }
            set { updateValue(newValue, forKey: Keys.ttsInspectorEnabled) }
        }

        static var styleValuesData: Data? {
            get { defaults.data(forKey: Keys.ttsStyleValues) }
            set { updateValue(newValue, forKey: Keys.ttsStyleValues) }
        }

        static var snippetsData: Data? {
            get { defaults.data(forKey: Keys.ttsSnippets) }
            set { updateValue(newValue, forKey: Keys.ttsSnippets) }
        }

        static var pronunciationRulesData: Data? {
            get { defaults.data(forKey: Keys.ttsPronunciationRules) }
            set { updateValue(newValue, forKey: Keys.ttsPronunciationRules) }
        }

        static var elevenLabsPrompt: String? {
            get { defaults.string(forKey: Keys.ttsElevenLabsPrompt) }
            set { updateString(newValue, forKey: Keys.ttsElevenLabsPrompt) }
        }

        static var elevenLabsModelRawValue: String? {
            get { defaults.string(forKey: Keys.ttsElevenLabsModel) }
            set { updateString(newValue, forKey: Keys.ttsElevenLabsModel) }
        }

        static var elevenLabsTags: [String]? {
            get {
                guard defaults.object(forKey: Keys.ttsElevenLabsTags) != nil else { return nil }
                return defaults.array(forKey: Keys.ttsElevenLabsTags) as? [String] ?? []
            }
            set { updateValue(newValue, forKey: Keys.ttsElevenLabsTags) }
        }
    }

    enum Transcription {
        static var selectedProviderRawValue: String? {
            get { defaults.string(forKey: Keys.ttsSelectedTranscriptionProvider) }
            set { updateString(newValue, forKey: Keys.ttsSelectedTranscriptionProvider) }
        }
    }

    enum TranscriptionSettings {
        static var prompt: String? {
            get { defaults.string(forKey: Keys.transcriptionPrompt) }
            set { updateString(newValue, forKey: Keys.transcriptionPrompt) }
        }

        static var selectedLanguage: String? {
            get { defaults.string(forKey: Keys.selectedLanguage) }
            set { updateString(newValue, forKey: Keys.selectedLanguage) }
        }

        static var isVADEnabled: Bool {
            get { bool(forKey: Keys.isVADEnabled, default: true) }
            set { setValue(newValue, forKey: Keys.isVADEnabled) }
        }

        static var isTextFormattingEnabled: Bool {
            get { bool(forKey: Keys.isTextFormattingEnabled, default: true) }
            set { setValue(newValue, forKey: Keys.isTextFormattingEnabled) }
        }

        static var appendTrailingSpace: Bool {
            get { bool(forKey: Keys.appendTrailingSpace, default: true) }
            set { setValue(newValue, forKey: Keys.appendTrailingSpace) }
        }

        static var recorderType: String? {
            get { defaults.string(forKey: Keys.recorderType) }
            set { updateString(newValue, forKey: Keys.recorderType) }
        }

        static var customLanguagePrompts: [String: String] {
            get { defaults.dictionary(forKey: Keys.customLanguagePrompts) as? [String: String] ?? [:] }
            set { setValue(newValue, forKey: Keys.customLanguagePrompts) }
        }

        static var currentTranscriptionModel: String? {
            get { defaults.string(forKey: Keys.currentTranscriptionModel) }
            set { updateString(newValue, forKey: Keys.currentTranscriptionModel) }
        }

        static var currentModel: String? {
            get { defaults.string(forKey: Keys.currentModel) }
            set { updateString(newValue, forKey: Keys.currentModel) }
        }
    }
}
