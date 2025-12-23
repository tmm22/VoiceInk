import Foundation

extension AppSettings {
    enum General {
        static var isMenuBarOnly: Bool? {
            get { boolValue(forKey: Keys.isMenuBarOnly) }
            set { updateValue(newValue, forKey: Keys.isMenuBarOnly) }
        }

        static var powerModeUIFlag: Bool? {
            get { boolValue(forKey: Keys.powerModeUIFlag) }
            set { updateValue(newValue, forKey: Keys.powerModeUIFlag) }
        }

        static var enableAIEnhancementFeatures: Bool? {
            get { boolValue(forKey: Keys.enableAIEnhancementFeatures) }
            set { updateValue(newValue, forKey: Keys.enableAIEnhancementFeatures) }
        }

        static var isExperimentalFeaturesEnabled: Bool? {
            get { boolValue(forKey: Keys.isExperimentalFeaturesEnabled) }
            set { updateValue(newValue, forKey: Keys.isExperimentalFeaturesEnabled) }
        }
    }

    enum PowerMode {
        static var autoRestoreEnabled: Bool? {
            get { boolValue(forKey: Keys.powerModeAutoRestoreEnabled) }
            set { updateValue(newValue, forKey: Keys.powerModeAutoRestoreEnabled) }
        }

        static var configurationsData: Data? {
            get { defaults.data(forKey: Keys.powerModeConfigurations) }
            set { updateValue(newValue, forKey: Keys.powerModeConfigurations) }
        }

        static var activeConfigurationId: String? {
            get { defaults.string(forKey: Keys.powerModeActiveConfigurationId) }
            set { updateString(newValue, forKey: Keys.powerModeActiveConfigurationId) }
        }

        static var activeSessionData: Data? {
            get { defaults.data(forKey: Keys.powerModeActiveSession) }
            set { updateValue(newValue, forKey: Keys.powerModeActiveSession, notify: false) }
        }

        static var customEmojis: [String] {
            get { defaults.array(forKey: Keys.customEmojis) as? [String] ?? [] }
            set { setValue(newValue, forKey: Keys.customEmojis) }
        }
    }

    enum Audio {
        static var isSystemMuteEnabled: Bool {
            get { bool(forKey: Keys.isSystemMuteEnabled, default: true) }
            set { setValue(newValue, forKey: Keys.isSystemMuteEnabled) }
        }

        static var isPauseMediaEnabled: Bool {
            get { bool(forKey: Keys.isPauseMediaEnabled, default: false) }
            set { setValue(newValue, forKey: Keys.isPauseMediaEnabled) }
        }

        static var audioRetentionPeriod: Int {
            get { integer(forKey: Keys.audioRetentionPeriod, default: 0) }
            set { setValue(newValue, forKey: Keys.audioRetentionPeriod) }
        }

        static var isAudioCleanupEnabled: Bool {
            get { bool(forKey: Keys.isAudioCleanupEnabled, default: false) }
            set { setValue(newValue, forKey: Keys.isAudioCleanupEnabled) }
        }

        static var audioFeedbackSettingsData: Data? {
            get { defaults.data(forKey: Keys.audioFeedbackSettings) }
            set { updateValue(newValue, forKey: Keys.audioFeedbackSettings) }
        }

        static var legacySoundFeedbackEnabled: Bool {
            get { bool(forKey: Keys.legacySoundFeedbackEnabled, default: true) }
            set { setValue(newValue, forKey: Keys.legacySoundFeedbackEnabled) }
        }
    }

    enum AudioInput {
        static var lastUsedMicrophoneDeviceID: String? {
            get { defaults.string(forKey: Keys.lastUsedMicrophoneDeviceID) }
            set { updateString(newValue, forKey: Keys.lastUsedMicrophoneDeviceID) }
        }

        static var audioInputModeRawValue: String? {
            get { defaults.string(forKey: Keys.audioInputMode) }
            set { updateString(newValue, forKey: Keys.audioInputMode) }
        }

        static var selectedAudioDeviceUID: String? {
            get { defaults.string(forKey: Keys.selectedAudioDeviceUID) }
            set { updateString(newValue, forKey: Keys.selectedAudioDeviceUID) }
        }

        static var prioritizedDevicesData: Data? {
            get { defaults.data(forKey: Keys.prioritizedDevices) }
            set { updateValue(newValue, forKey: Keys.prioritizedDevices) }
        }
    }

    enum Clipboard {
        static var restoreClipboardAfterPaste: Bool {
            get { bool(forKey: Keys.restoreClipboardAfterPaste, default: false) }
            set { setValue(newValue, forKey: Keys.restoreClipboardAfterPaste) }
        }

        static var useAppleScriptPaste: Bool {
            get { bool(forKey: Keys.useAppleScriptPaste, default: false) }
            set { setValue(newValue, forKey: Keys.useAppleScriptPaste) }
        }

        static var clipboardRestoreDelay: Double {
            get { double(forKey: Keys.clipboardRestoreDelay, default: 0) }
            set { setValue(newValue, forKey: Keys.clipboardRestoreDelay) }
        }
    }

    enum Hotkeys {
        static var selectedHotkey1: String? {
            get { defaults.string(forKey: Keys.selectedHotkey1) }
            set { updateString(newValue, forKey: Keys.selectedHotkey1) }
        }

        static var selectedHotkey2: String? {
            get { defaults.string(forKey: Keys.selectedHotkey2) }
            set { updateString(newValue, forKey: Keys.selectedHotkey2) }
        }

        static var isMiddleClickToggleEnabled: Bool {
            get { bool(forKey: Keys.isMiddleClickToggleEnabled, default: false) }
            set { setValue(newValue, forKey: Keys.isMiddleClickToggleEnabled) }
        }

        static var middleClickActivationDelay: Int {
            get { integer(forKey: Keys.middleClickActivationDelay, default: 0) }
            set { setValue(newValue, forKey: Keys.middleClickActivationDelay) }
        }
    }

    enum Dictionary {
        static var customVocabularyItemsData: Data? {
            get { defaults.data(forKey: Keys.customVocabularyItems) }
            set { updateValue(newValue, forKey: Keys.customVocabularyItems) }
        }

        static var legacyCustomDictionaryItemsData: Data? {
            get { defaults.data(forKey: Keys.customDictionaryItems) }
            set { updateValue(newValue, forKey: Keys.customDictionaryItems) }
        }

        static var wordReplacements: [String: String] {
            get { defaults.dictionary(forKey: Keys.wordReplacements) as? [String: String] ?? [:] }
            set { setValue(newValue, forKey: Keys.wordReplacements) }
        }

        static var dictionarySortMode: String? {
            get { defaults.string(forKey: Keys.dictionarySortMode) }
            set { updateString(newValue, forKey: Keys.dictionarySortMode) }
        }

        static var wordReplacementSortMode: String? {
            get { defaults.string(forKey: Keys.wordReplacementSortMode) }
            set { updateString(newValue, forKey: Keys.wordReplacementSortMode) }
        }
    }

    enum Cleanup {
        static var isTranscriptionCleanupEnabled: Bool {
            get { bool(forKey: Keys.transcriptionCleanupEnabled, default: false) }
            set { setValue(newValue, forKey: Keys.transcriptionCleanupEnabled) }
        }

        static var transcriptionRetentionMinutes: Int {
            get { integer(forKey: Keys.transcriptionRetentionMinutes, default: 0) }
            set { setValue(newValue, forKey: Keys.transcriptionRetentionMinutes) }
        }
    }

    enum Announcements {
        static var dismissedIds: [String] {
            get { defaults.stringArray(forKey: Keys.dismissedAnnouncementIds) ?? [] }
            set { setValue(newValue, forKey: Keys.dismissedAnnouncementIds) }
        }
    }

    enum Device {
        static var identifier: String? {
            get { defaults.string(forKey: Keys.deviceIdentifier) }
            set { updateString(newValue, forKey: Keys.deviceIdentifier) }
        }
    }
}
