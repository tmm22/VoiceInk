import Foundation

extension Notification.Name {
    static let AppSettingsDidChange = Notification.Name("appSettingsDidChange")
    static let languageDidChange = Notification.Name("languageDidChange")
    static let promptDidChange = Notification.Name("promptDidChange")
    static let toggleMiniRecorder = Notification.Name("toggleMiniRecorder")
    static let dismissMiniRecorder = Notification.Name("dismissMiniRecorder")
    static let didChangeModel = Notification.Name("didChangeModel")
    static let aiProviderKeyChanged = Notification.Name("aiProviderKeyChanged")
    static let licenseStatusChanged = Notification.Name("licenseStatusChanged")
    static let navigateToDestination = Notification.Name("navigateToDestination")
    static let promptSelectionChanged = Notification.Name("promptSelectionChanged")
    static let powerModeConfigurationApplied = Notification.Name("powerModeConfigurationApplied")
    static let transcriptionCreated = Notification.Name("transcriptionCreated")
    static let transcriptionCompleted = Notification.Name("transcriptionCompleted")
    static let transcriptionDeleted = Notification.Name("transcriptionDeleted")
    static let enhancementToggleChanged = Notification.Name("enhancementToggleChanged")
    static let openFileForTranscription = Notification.Name("openFileForTranscription")
    static let showShortcutCheatSheet = Notification.Name("showShortcutCheatSheet")
    static let audioDeviceChanged = Notification.Name("AudioDeviceChanged")
    static let audioDeviceSwitchRequired = Notification.Name("audioDeviceSwitchRequired")
    // Distinct from `powerModeConfigurationApplied`: fires when the set of configurations changes (add/remove/save).
    static let powerModeConfigurationsDidChange = Notification.Name("PowerModeConfigurationsDidChange")
    // Note: Observed by MiniWindowManager; no in-repo post sites found. Kept for external/system events.
    static let hideMiniRecorder = Notification.Name("HideMiniRecorder")
    // Note: Observed by NotchWindowManager; no in-repo post sites found. Kept for external/system events.
    static let hideNotchRecorder = Notification.Name("HideNotchRecorder")
    // Note: Posted by CustomSoundManager; no in-repo observers found. Kept for external/system listeners.
    static let customSoundsChanged = Notification.Name("CustomSoundsChanged")
    // Note: Observed in RecorderTests; no in-repo post sites found. Kept so the test wiring stays intact.
    static let noAudioDetected = Notification.Name("NoAudioDetected")
}
