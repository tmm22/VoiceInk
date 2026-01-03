import Foundation

enum AppSettings {
    static var defaults: UserDefaults { .standard }

    enum Keys {
        static let ttsSelectedProvider = "selectedProvider"
        static let ttsPlaybackSpeed = "playbackSpeed"
        static let ttsVolume = "volume"
        static let ttsLoopEnabled = "loopEnabled"
        static let ttsIsMinimalistMode = "isMinimalistMode"
        static let ttsAudioFormat = "audioFormat"
        static let ttsAppearancePreference = "appearancePreference"
        static let ttsNotificationsEnabled = "notificationsEnabled"
        static let ttsInspectorEnabled = "isInspectorEnabled"
        static let ttsStyleValues = "providerStyleValues"
        static let ttsSnippets = "textSnippets"
        static let ttsPronunciationRules = "pronunciationRules"
        static let ttsElevenLabsPrompt = "elevenLabs.prompt"
        static let ttsElevenLabsModel = "elevenLabs.model"
        static let ttsElevenLabsTags = "elevenLabs.tags"
        static let ttsSelectedTranscriptionProvider = "selectedTranscriptionProvider"
        static let aiSelectedProvider = "selectedAIProvider"
        static let aiCustomProviderBaseURL = "customProviderBaseURL"
        static let aiCustomProviderModel = "customProviderModel"
        static let aiOpenRouterModels = "openRouterModels"
        static let ollamaBaseURL = "ollamaBaseURL"
        static let ollamaSelectedModel = "ollamaSelectedModel"
        static let powerModeUIFlag = "powerModeUIFlag"
        static let powerModeAutoRestoreEnabled = "powerModeAutoRestoreEnabled"
        static let powerModeConfigurations = "powerModeConfigurationsV2"
        static let powerModeActiveConfigurationId = "activeConfigurationId"
        static let powerModeActiveSession = "powerModeActiveSession.v1"
        static let enableAIEnhancementFeatures = "enableAIEnhancementFeatures"
        static let isMenuBarOnly = "IsMenuBarOnly"
        static let isExperimentalFeaturesEnabled = "isExperimentalFeaturesEnabled"
        static let transcriptionPrompt = "TranscriptionPrompt"
        static let selectedLanguage = "SelectedLanguage"
        static let isVADEnabled = "IsVADEnabled"
        static let isTextFormattingEnabled = "IsTextFormattingEnabled"
        static let appendTrailingSpace = "AppendTrailingSpace"
        static let recorderType = "RecorderType"
        static let currentTranscriptionModel = "CurrentTranscriptionModel"
        static let currentModel = "CurrentModel"
        static let isSystemMuteEnabled = "isSystemMuteEnabled"
        static let isPauseMediaEnabled = "isPauseMediaEnabled"
        static let lastUsedMicrophoneDeviceID = "lastUsedMicrophoneDeviceID"
        static let audioInputMode = "audioInputMode"
        static let selectedAudioDeviceUID = "selectedAudioDeviceUID"
        static let prioritizedDevices = "prioritizedDevices"
        static let audioRetentionPeriod = "AudioRetentionPeriod"
        static let isAudioCleanupEnabled = "IsAudioCleanupEnabled"
        static let transcriptionCleanupEnabled = "IsTranscriptionCleanupEnabled"
        static let transcriptionRetentionMinutes = "TranscriptionRetentionMinutes"
        static let restoreClipboardAfterPaste = "restoreClipboardAfterPaste"
        static let useAppleScriptPaste = "UseAppleScriptPaste"
        static let clipboardRestoreDelay = "clipboardRestoreDelay"
        static let selectedHotkey1 = "selectedHotkey1"
        static let selectedHotkey2 = "selectedHotkey2"
        static let isMiddleClickToggleEnabled = "isMiddleClickToggleEnabled"
        static let middleClickActivationDelay = "middleClickActivationDelay"
        static let customVocabularyItems = "CustomVocabularyItems"
        static let customDictionaryItems = "CustomDictionaryItems"
        static let wordReplacements = "wordReplacements"
        static let dictionarySortMode = "dictionarySortMode"
        static let wordReplacementSortMode = "wordReplacementSortMode"
        static let dismissedAnnouncementIds = "dismissedAnnouncementIds"
        static let customEmojis = "userAddedEmojis"
        static let audioFeedbackSettings = "audioFeedbackSettings"
        static let legacySoundFeedbackEnabled = "isSoundFeedbackEnabled"
        static let aiEnhancementEnabled = "isAIEnhancementEnabled"
        static let aiContextSettings = "aiContextSettings"
        static let aiCustomPrompts = "customPrompts"
        static let aiSelectedPromptId = "selectedPromptId"
        static let aiEnhancementTimeout = "aiEnhancementTimeout"
        static let aiReasoningEffort = "aiReasoningEffort"
        static let useClipboardContext = "useClipboardContext"
        static let useScreenCaptureContext = "useScreenCaptureContext"
        static let enhancementShortcutEnabled = "isToggleEnhancementShortcutEnabled"
        static let quickRulesEnabled = "quickRulesEnabled"
        static let quickRulesData = "quickRules"
        static let deviceIdentifier = "VoiceInkDeviceIdentifier"
        static let customLanguagePrompts = "CustomLanguagePrompts"
        static let licenseKey = "VoiceInkLicense"
    }

    static func contains(key: String) -> Bool {
        defaults.object(forKey: key) != nil
    }

    static func removeValue(forKey key: String, notify: Bool = true) {
        defaults.removeObject(forKey: key)
        if notify {
            notifyChange()
        }
    }

    static func string(forKey key: String, default defaultValue: String) -> String {
        defaults.string(forKey: key) ?? defaultValue
    }

    static func string(forKey key: String) -> String? {
        defaults.string(forKey: key)
    }

    static func bool(forKey key: String, default defaultValue: Bool) -> Bool {
        defaults.object(forKey: key) as? Bool ?? defaultValue
    }

    static func integer(forKey key: String, default defaultValue: Int) -> Int {
        if defaults.object(forKey: key) == nil { return defaultValue }
        return defaults.integer(forKey: key)
    }

    static func double(forKey key: String, default defaultValue: Double) -> Double {
        if defaults.object(forKey: key) == nil { return defaultValue }
        return defaults.double(forKey: key)
    }

    static func data(forKey key: String) -> Data? {
        defaults.data(forKey: key)
    }

    static func stringArray(forKey key: String) -> [String] {
        defaults.stringArray(forKey: key) ?? []
    }

    static func dictionary(forKey key: String) -> [String: String] {
        defaults.dictionary(forKey: key) as? [String: String] ?? [:]
    }

    static func setValue<T>(_ value: T, forKey key: String, notify: Bool = true) {
        defaults.set(value, forKey: key)
        if notify {
            notifyChange()
        }
    }

    static func boolValue(forKey key: String) -> Bool? {
        guard defaults.object(forKey: key) != nil else { return nil }
        return defaults.bool(forKey: key)
    }

    static func doubleValue(forKey key: String) -> Double? {
        guard defaults.object(forKey: key) != nil else { return nil }
        return defaults.double(forKey: key)
    }

    static func updateString(_ value: String?, forKey key: String, notify: Bool = true) {
        guard let value else {
            defaults.removeObject(forKey: key)
            if notify {
                notifyChange()
            }
            return
        }
        defaults.set(value, forKey: key)
        if notify {
            notifyChange()
        }
    }

    static func updateValue<T>(_ value: T?, forKey key: String, notify: Bool = true) {
        guard let value else {
            defaults.removeObject(forKey: key)
            if notify {
                notifyChange()
            }
            return
        }
        defaults.set(value, forKey: key)
        if notify {
            notifyChange()
        }
    }

    static func notifyChange() {
        if Thread.isMainThread {
            NotificationCenter.default.post(name: .AppSettingsDidChange, object: nil)
        } else {
            Task { @MainActor in
                NotificationCenter.default.post(name: .AppSettingsDidChange, object: nil)
            }
        }
    }
}
