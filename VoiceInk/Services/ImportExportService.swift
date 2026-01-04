import Foundation
import AppKit
import UniformTypeIdentifiers
import KeyboardShortcuts
import LaunchAtLogin
import os

struct GeneralSettings: Codable {
    let toggleMiniRecorderShortcut: KeyboardShortcuts.Shortcut?
    let toggleMiniRecorderShortcut2: KeyboardShortcuts.Shortcut?
    let retryLastTranscriptionShortcut: KeyboardShortcuts.Shortcut?
    let selectedHotkey1RawValue: String?
    let selectedHotkey2RawValue: String?
    let launchAtLoginEnabled: Bool?
    let isMenuBarOnly: Bool?
    let useAppleScriptPaste: Bool?
    let recorderType: String?
    let isTranscriptionCleanupEnabled: Bool?
    let transcriptionRetentionMinutes: Int?
    let isAudioCleanupEnabled: Bool?
    let audioRetentionPeriod: Int?

    let isSoundFeedbackEnabled: Bool?
    let audioFeedbackSettings: AudioFeedbackSettings?
    let isSystemMuteEnabled: Bool?
    let isPauseMediaEnabled: Bool?
    let isTextFormattingEnabled: Bool?
    let isExperimentalFeaturesEnabled: Bool?
    let restoreClipboardAfterPaste: Bool?
    let clipboardRestoreDelay: Double?
}

struct VoiceLinkCommunityExportedSettings: Codable {
    let version: String
    let customPrompts: [CustomPrompt]
    let powerModeConfigs: [PowerModeConfig]
    let dictionaryItems: [DictionaryItem]?
    let wordReplacements: [String: String]?
    let generalSettings: GeneralSettings?
    let customEmojis: [String]?
    let customCloudModels: [CustomCloudModel]?
}

class ImportExportService {
    static let shared = ImportExportService()
    private let logger = Logger(subsystem: "com.tmm22.voicelinkcommunity", category: "ImportExportService")
    private let currentSettingsVersion: String

    private init() {
        if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
            self.currentSettingsVersion = version
        } else {
            self.currentSettingsVersion = "0.0.0"
        }
    }

    @MainActor
    func exportSettings(enhancementService: AIEnhancementService, whisperPrompt: WhisperPrompt, hotkeyManager: HotkeyManager, menuBarManager: MenuBarManager, mediaController: MediaController, playbackController: PlaybackController, soundManager: SoundManager, whisperState: WhisperState) {
        let powerModeManager = PowerModeManager.shared
        let emojiManager = EmojiManager.shared

        let exportablePrompts = enhancementService.customPrompts.filter { !$0.isPredefined }

        let powerConfigs = powerModeManager.configurations
        
        // Export custom models
        let customModels = CustomModelManager.shared.customModels

        var exportedDictionaryItems: [DictionaryItem]? = nil
        if let data = AppSettings.Dictionary.customVocabularyItemsData,
           let items = try? JSONDecoder().decode([DictionaryItem].self, from: data) {
            exportedDictionaryItems = items
        }

        let exportedWordReplacements = AppSettings.Dictionary.wordReplacements

        let generalSettingsToExport = GeneralSettings(
            toggleMiniRecorderShortcut: KeyboardShortcuts.getShortcut(for: .toggleMiniRecorder),
            toggleMiniRecorderShortcut2: KeyboardShortcuts.getShortcut(for: .toggleMiniRecorder2),
            retryLastTranscriptionShortcut: KeyboardShortcuts.getShortcut(for: .retryLastTranscription),
            selectedHotkey1RawValue: hotkeyManager.selectedHotkey1.rawValue,
            selectedHotkey2RawValue: hotkeyManager.selectedHotkey2.rawValue,
            launchAtLoginEnabled: LaunchAtLogin.isEnabled,
            isMenuBarOnly: menuBarManager.isMenuBarOnly,
            useAppleScriptPaste: AppSettings.Clipboard.useAppleScriptPaste,
            recorderType: whisperState.recorderType,
            isTranscriptionCleanupEnabled: AppSettings.Cleanup.isTranscriptionCleanupEnabled,
            transcriptionRetentionMinutes: AppSettings.Cleanup.transcriptionRetentionMinutes,
            isAudioCleanupEnabled: AppSettings.Audio.isAudioCleanupEnabled,
            audioRetentionPeriod: AppSettings.Audio.audioRetentionPeriod,

            isSoundFeedbackEnabled: soundManager.isEnabled,
            audioFeedbackSettings: soundManager.settings,
            isSystemMuteEnabled: mediaController.isSystemMuteEnabled,
            isPauseMediaEnabled: playbackController.isPauseMediaEnabled,
            isTextFormattingEnabled: AppSettings.TranscriptionSettings.isTextFormattingEnabled,
            isExperimentalFeaturesEnabled: AppSettings.General.isExperimentalFeaturesEnabled,
            restoreClipboardAfterPaste: AppSettings.Clipboard.restoreClipboardAfterPaste,
            clipboardRestoreDelay: AppSettings.Clipboard.clipboardRestoreDelay
        )

        let exportedSettings = VoiceLinkCommunityExportedSettings(
            version: currentSettingsVersion,
            customPrompts: exportablePrompts,
            powerModeConfigs: powerConfigs,
            dictionaryItems: exportedDictionaryItems,
            wordReplacements: exportedWordReplacements,
            generalSettings: generalSettingsToExport,
            customEmojis: emojiManager.customEmojis,
            customCloudModels: customModels
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted

        do {
            let jsonData = try encoder.encode(exportedSettings)

            let savePanel = NSSavePanel()
            savePanel.allowedContentTypes = [UTType.json]
            savePanel.nameFieldStringValue = "VoiceLinkCommunity_Settings_Backup.json"
            savePanel.title = "Export \(AppBrand.communityName) Settings"
            savePanel.message = "Choose a location to save your settings."

            Task { @MainActor in
                if savePanel.runModal() == .OK {
                    if let url = savePanel.url {
                        do {
                            try jsonData.write(to: url)
                            self.showAlert(title: "Export Successful", message: "Your settings have been successfully exported to \(url.lastPathComponent).")
                        } catch {
                            self.showAlert(title: "Export Error", message: "Could not save settings to file: \(error.localizedDescription)")
                        }
                    }
                } else {
                    self.showAlert(title: "Export Canceled", message: "The settings export operation was canceled.")
                }
            }
        } catch {
            self.showAlert(title: "Export Error", message: "Could not encode settings to JSON: \(error.localizedDescription)")
        }
    }

    @MainActor
    func importSettings(enhancementService: AIEnhancementService, whisperPrompt: WhisperPrompt, hotkeyManager: HotkeyManager, menuBarManager: MenuBarManager, mediaController: MediaController, playbackController: PlaybackController, soundManager: SoundManager, whisperState: WhisperState) {
        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = [UTType.json]
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = false
        openPanel.allowsMultipleSelection = false
        openPanel.title = "Import \(AppBrand.communityName) Settings"
        openPanel.message = "Choose a settings file to import. This will overwrite ALL settings (prompts, power modes, dictionary, general app settings)."

        Task { @MainActor in
            if openPanel.runModal() == .OK {
                guard let url = openPanel.url else {
                    self.showAlert(title: "Import Error", message: "Could not get the file URL from the open panel.")
                    return
                }

                Task { @MainActor in
                    do {
                        let jsonData = try await FileDataLoader.loadData(from: url)
                        let importedSettings = try await Task.detached(priority: .utility) {
                            let decoder = JSONDecoder()
                            return try decoder.decode(VoiceLinkCommunityExportedSettings.self, from: jsonData)
                        }.value
                    
                    if importedSettings.version != self.currentSettingsVersion {
                        self.showAlert(title: "Version Mismatch", message: "The imported settings file (version \(importedSettings.version)) is from a different version than your application (version \(self.currentSettingsVersion)). Proceeding with import, but be aware of potential incompatibilities.")
                    }

                    let predefinedPrompts = enhancementService.customPrompts.filter { $0.isPredefined }
                    enhancementService.customPrompts = predefinedPrompts + importedSettings.customPrompts
                    
                    let powerModeManager = PowerModeManager.shared
                    powerModeManager.configurations = importedSettings.powerModeConfigs
                    powerModeManager.saveConfigurations()

                    // Import Custom Models
                    if let modelsToImport = importedSettings.customCloudModels {
                        let customModelManager = CustomModelManager.shared
                        customModelManager.customModels = modelsToImport
                        customModelManager.saveCustomModels() // Ensure they are persisted
                        whisperState.refreshAllAvailableModels() // Refresh the UI
                        self.logger.info("Successfully imported \(modelsToImport.count) custom models.")
                    } else {
                        self.logger.info("No custom models found in the imported file.")
                    }

                    if let customEmojis = importedSettings.customEmojis {
                        let emojiManager = EmojiManager.shared
                        for emoji in customEmojis {
                            _ = emojiManager.addCustomEmoji(emoji)
                        }
                    }

                    if let itemsToImport = importedSettings.dictionaryItems {
                        if let encoded = try? JSONEncoder().encode(itemsToImport) {
                            AppSettings.Dictionary.customVocabularyItemsData = encoded
                        }
                    } else {
                        self.logger.info("No custom vocabulary items (for spelling) found in the imported file. Existing items remain unchanged.")
                    }

                    if let replacementsToImport = importedSettings.wordReplacements {
                        AppSettings.Dictionary.wordReplacements = replacementsToImport
                    } else {
                        self.logger.info("No word replacements found in the imported file. Existing replacements remain unchanged.")
                    }

                    if let general = importedSettings.generalSettings {
                        if let shortcut = general.toggleMiniRecorderShortcut {
                            KeyboardShortcuts.setShortcut(shortcut, for: .toggleMiniRecorder)
                        }
                        if let shortcut2 = general.toggleMiniRecorderShortcut2 {
                            KeyboardShortcuts.setShortcut(shortcut2, for: .toggleMiniRecorder2)
                        }
                        if let retryShortcut = general.retryLastTranscriptionShortcut {
                            KeyboardShortcuts.setShortcut(retryShortcut, for: .retryLastTranscription)
                        }
                        if let hotkeyRaw = general.selectedHotkey1RawValue,
                           let hotkey = HotkeyManager.HotkeyOption(rawValue: hotkeyRaw) {
                            hotkeyManager.selectedHotkey1 = hotkey
                        }
                        if let hotkeyRaw2 = general.selectedHotkey2RawValue,
                           let hotkey2 = HotkeyManager.HotkeyOption(rawValue: hotkeyRaw2) {
                            hotkeyManager.selectedHotkey2 = hotkey2
                        }
                        if let launch = general.launchAtLoginEnabled {
                            LaunchAtLogin.isEnabled = launch
                        }
                        if let menuOnly = general.isMenuBarOnly {
                            menuBarManager.isMenuBarOnly = menuOnly
                        }
                        if let appleScriptPaste = general.useAppleScriptPaste {
                            AppSettings.Clipboard.useAppleScriptPaste = appleScriptPaste
                        }
                        if let recType = general.recorderType {
                            whisperState.recorderType = recType
                        }
                        
                        if let transcriptionCleanup = general.isTranscriptionCleanupEnabled {
                            AppSettings.Cleanup.isTranscriptionCleanupEnabled = transcriptionCleanup
                        }
                        if let transcriptionMinutes = general.transcriptionRetentionMinutes {
                            AppSettings.Cleanup.transcriptionRetentionMinutes = transcriptionMinutes
                        }
                        if let audioCleanup = general.isAudioCleanupEnabled {
                            AppSettings.Audio.isAudioCleanupEnabled = audioCleanup
                        }
                        if let audioRetention = general.audioRetentionPeriod {
                            AppSettings.Audio.audioRetentionPeriod = audioRetention
                        }

                        if let soundFeedback = general.isSoundFeedbackEnabled {
                            soundManager.isEnabled = soundFeedback
                        }
                        if let audioSettings = general.audioFeedbackSettings {
                            soundManager.settings = audioSettings
                        }
                        if let muteSystem = general.isSystemMuteEnabled {
                            mediaController.isSystemMuteEnabled = muteSystem
                        }
                        if let pauseMedia = general.isPauseMediaEnabled {
                            playbackController.isPauseMediaEnabled = pauseMedia
                        }
                        if let experimentalEnabled = general.isExperimentalFeaturesEnabled {
                            AppSettings.General.isExperimentalFeaturesEnabled = experimentalEnabled
                            if experimentalEnabled == false {
                                playbackController.isPauseMediaEnabled = false
                            }
                        }
                        if let textFormattingEnabled = general.isTextFormattingEnabled {
                            AppSettings.TranscriptionSettings.isTextFormattingEnabled = textFormattingEnabled
                        }
                        if let restoreClipboard = general.restoreClipboardAfterPaste {
                            AppSettings.Clipboard.restoreClipboardAfterPaste = restoreClipboard
                        }
                        if let clipboardDelay = general.clipboardRestoreDelay {
                            AppSettings.Clipboard.clipboardRestoreDelay = clipboardDelay
                        }
                    }

                        self.showRestartAlert(message: "Settings imported successfully from \(url.lastPathComponent). All settings (including general app settings) have been applied.")

                    } catch {
                        self.showAlert(title: "Import Error", message: "Error importing settings: \(error.localizedDescription). The file might be corrupted or not in the correct format.")
                    }
                }
            } else {
                self.showAlert(title: "Import Canceled", message: "The settings import operation was canceled.")
            }
        }
    }

    private func showAlert(title: String, message: String) {
        Task { @MainActor in
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    private func showRestartAlert(message: String) {
        Task { @MainActor in
            let alert = NSAlert()
            alert.messageText = "Import Successful"
            alert.informativeText = message + "\n\nIMPORTANT: If you were using AI enhancement features, please make sure to reconfigure your API keys in the Enhancement section.\n\nIt is recommended to restart \(AppBrand.communityName) for all changes to take full effect."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "Configure API Keys")
            
            let response = alert.runModal()
            if response == .alertSecondButtonReturn {
                NotificationCenter.default.post(
                    name: .navigateToDestination,
                    object: nil,
                    userInfo: ["destination": "Enhancement"]
                )
            }
        }
    }
}
