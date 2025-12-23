import Foundation

/// A centralized string management system for VoiceInk.
/// This facilitates the migration from hardcoded strings to a localized system.
struct Localization {
    
    /// Returns the app's display name dynamically from the bundle
    static var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? "VoiceLink Community"
    }
    
    /// Returns true if user's region prefers "Bin" over "Trash"
    /// Commonwealth countries typically use "Bin" while US/Canada use "Trash"
    private static var usesBinTerminology: Bool {
        let regionCode = Locale.current.region?.identifier ?? ""
        // Commonwealth countries that use "Bin"
        let binRegions = ["GB", "AU", "NZ", "IE", "ZA", "IN", "SG", "HK", "MY", "PK"]
        return binRegions.contains(regionCode)
    }
    enum General {
        static let done = NSLocalizedString("Done", comment: "General done action")
        static let cancel = NSLocalizedString("Cancel", comment: "General cancel action")
        static let error = NSLocalizedString("Error", comment: "General error label")
        static let success = NSLocalizedString("Success", comment: "General success label")
    }
    
    enum Transcription {
        static let noTranscriptionAvailable = NSLocalizedString("No transcription available", comment: "Error when no transcription is found")
        static let lastTranscriptionCopied = NSLocalizedString("Last transcription copied", comment: "Success message after copying")
        static let failedToCopy = NSLocalizedString("Failed to copy transcription", comment: "Error message when copy fails")
        static let copiedToClipboard = NSLocalizedString("Copied to clipboard", comment: "General copy success message")
        static let retryFailed = NSLocalizedString("Retry failed: %@", comment: "Error message when retry fails")
        static let noModelSelected = NSLocalizedString("No transcription model selected", comment: "Error when no model is active")
        static let audioFileNotFound = NSLocalizedString("Cannot retry: Audio file not found", comment: "Error when audio file is missing")
    }
    
    enum API {
        static let missingKey = NSLocalizedString("API Key is missing", comment: "Error when API key is not found")
        static let invalidKey = NSLocalizedString("Invalid API Key", comment: "Error when API key is invalid")
    }
    
    enum Trash {
        static var title: String { usesBinTerminology ? "Bin" : "Trash" }
        static var emptyTrash: String { usesBinTerminology ? "Empty Bin" : "Empty Trash" }
        static let restore = NSLocalizedString("Restore", comment: "Restore item from trash")
        static let deletePermanently = NSLocalizedString("Delete Permanently", comment: "Permanently delete item")
        static var trashIsEmpty: String { usesBinTerminology ? "Bin is Empty" : "Trash is Empty" }
        static let trashEmptyDescription = NSLocalizedString("Deleted transcriptions will appear here", comment: "Empty state description")
        static var movedToTrash: String { usesBinTerminology ? "Moved to bin" : "Moved to trash" }
        static let restored = NSLocalizedString("Transcription restored", comment: "Notification when item is restored")
        static let restoredMultiple = NSLocalizedString("Transcriptions restored", comment: "Notification when multiple items are restored")
        static let permanentlyDeleted = NSLocalizedString("Permanently deleted", comment: "Notification when item is permanently deleted")
        static var itemCount: String { usesBinTerminology ? "%d item(s) in bin" : "%d item(s) in trash" }
        static let daysUntilDeletion = NSLocalizedString("%d days until permanent deletion", comment: "Days remaining before permanent deletion")
        static let retentionInfo = NSLocalizedString("Items are permanently deleted after 30 days", comment: "Trash retention policy info")
        static var openTrash: String { usesBinTerminology ? "Open Bin" : "Open Trash" }
        static var moveToTrash: String { usesBinTerminology ? "Move to Bin" : "Move to Trash" }
        static var moveToTrashConfirmTitle: String { usesBinTerminology ? "Move to Bin?" : "Move to Trash?" }
        static func moveToTrashConfirmMessage(count: Int) -> String {
            let items = count == 1 ? "item" : "items"
            let destination = usesBinTerminology ? "bin" : "trash"
            return "\(count) \(items) will be moved to \(destination). You can restore them within 30 days."
        }
        static func deletedTimeAgo(_ timeAgo: String) -> String {
            usesBinTerminology ? "Deleted \(timeAgo)" : "Deleted \(timeAgo)"
        }
    }
    
    enum Recording {
        static let failedToStart = NSLocalizedString("Recording failed to start", comment: "Error when recording cannot start")
        static let noAudioDetected = NSLocalizedString("No Audio Detected", comment: "Warning when no audio input is detected")
        static let noAudioDescription = NSLocalizedString("Please check your microphone and try again.", comment: "Description for no audio detected")
        static let fileCorrupted = NSLocalizedString("Recording failed - audio file corrupted", comment: "Error when audio file is corrupted")
        static let encodeError = NSLocalizedString("Recording error: %@", comment: "Error during recording encode")
        static let cancelled = NSLocalizedString("Recording cancelled", comment: "Recording was cancelled")
        static let escToCancelHint = NSLocalizedString("Press ESC again to cancel recording", comment: "Hint for cancelling recording")
        static let usingDevice = NSLocalizedString("Using: %@", comment: "Notification showing which audio device is being used")
    }
    
    enum Models {
        static let noModelSelected = NSLocalizedString("No AI Model Selected", comment: "Error when no AI model is selected")
        static let noModelDescription = NSLocalizedString("Please select a model in Settings > AI Models", comment: "Description for no model selected")
        static let importSuccess = NSLocalizedString("Imported %@", comment: "Success message when model is imported")
        static let importFailed = NSLocalizedString("Failed to import model: %@", comment: "Error when model import fails")
        static let modelExists = NSLocalizedString("A model named %@ already exists", comment: "Error when model with same name exists")
        static let downloadSuccess = NSLocalizedString("FastConformer ready", comment: "Success when FastConformer is downloaded")
        static let downloadFailed = NSLocalizedString("FastConformer download failed", comment: "Error when FastConformer download fails")
        static let downloadFailedForModel = NSLocalizedString("Failed to download %@", comment: "Error when model download fails")
    }

    enum PowerMode {
        static let selectPowerMode = NSLocalizedString("Select Power Mode", comment: "Title for the Power Mode popover")
        static let noPowerModesAvailable = NSLocalizedString("No Power Modes Available", comment: "Empty state when no Power Modes are enabled")
        static let noPowerModes = NSLocalizedString("No Power Modes", comment: "Empty state title for Power Modes list")
        static let noPowerModesDescription = NSLocalizedString("Add customized power modes for different contexts", comment: "Empty state description for Power Modes list")
        static let defaultLabel = NSLocalizedString("Default", comment: "Default Power Mode label")
        static let autoSendLabel = NSLocalizedString("Auto Send", comment: "Auto-send toggle label")
        static let contextAwarenessLabel = NSLocalizedString("Context Awareness", comment: "Context awareness section label")
        static let editAction = NSLocalizedString("Edit", comment: "Edit action label")
        static let deleteAction = NSLocalizedString("Delete", comment: "Delete action label")
        static let emojiTip = NSLocalizedString("Tip: Use ⌃⌘Space for emoji picker.", comment: "Tip for emoji input")
        static let emojiInUseMessage = NSLocalizedString("The emoji \"%@\" is currently used by one or more Power Modes and cannot be removed.", comment: "Alert when emoji is in use")
        static let emojiInUseTitle = NSLocalizedString("Emoji in Use", comment: "Alert title when emoji is in use")
        static let emojiAlreadyExists = NSLocalizedString("Emoji already exists!", comment: "Duplicate emoji error message")
        static let emojiInvalid = NSLocalizedString("Invalid emoji.", comment: "Invalid emoji error message")
        static let emojiEmpty = NSLocalizedString("Emoji cannot be empty.", comment: "Empty emoji error message")
        static let emojiInvalidCharacter = NSLocalizedString("Invalid emoji character.", comment: "Invalid emoji character error message")
        static let emojiAddFailed = NSLocalizedString("Could not add emoji.", comment: "Emoji add failure message")
        static let addCustomEmojiHelp = NSLocalizedString("Add custom emoji", comment: "Help text for add emoji button")
        static let addEmojiLabel = NSLocalizedString("Add Emoji", comment: "Add emoji button label")
        static let addButton = NSLocalizedString("Add", comment: "Generic add button label")
        static let cancelButton = NSLocalizedString("Cancel", comment: "Generic cancel button label")
        static let okButton = NSLocalizedString("OK", comment: "Generic OK button label")
        static let doneButton = NSLocalizedString("Done", comment: "Generic done button label")
        static let namePlaceholder = NSLocalizedString("Name your power mode", comment: "Placeholder for Power Mode name")
        static let applicationsTitle = NSLocalizedString("Applications", comment: "Applications section title")
        static let addAppLabel = NSLocalizedString("Add App", comment: "Add application button label")
        static let noApplications = NSLocalizedString("No applications added", comment: "Empty state for applications list")
        static let websitesTitle = NSLocalizedString("Websites", comment: "Websites section title")
        static let websitePlaceholder = NSLocalizedString("Enter website URL (e.g., google.com)", comment: "Placeholder for website URL entry")
        static let noWebsites = NSLocalizedString("No websites added", comment: "Empty state for websites list")
        static let noTranscriptionModels = NSLocalizedString("No transcription models available. Please connect to a cloud service or download a local model in the AI Models tab.", comment: "Empty state for transcription model selection")
        static let modelLabel = NSLocalizedString("Model", comment: "Model selection label")
        static let languageLabel = NSLocalizedString("Language", comment: "Language selection label")
        static let autodetectedLabel = NSLocalizedString("Autodetected", comment: "Autodetected language label")
        static let aiProviderLabel = NSLocalizedString("AI Provider", comment: "AI provider section label")
        static let noProvidersConnected = NSLocalizedString("No providers connected", comment: "Empty state for AI providers list")
        static let aiModelLabel = NSLocalizedString("AI Model", comment: "AI model label")
        static let enhancementPromptLabel = NSLocalizedString("Enhancement Prompt", comment: "Enhancement prompt label")
        static let setAsDefaultLabel = NSLocalizedString("Set as default power mode", comment: "Toggle to set default Power Mode")
        static let defaultPowerModeTitle = NSLocalizedString("Default Power Mode", comment: "Info tip title for default Power Mode")
        static let defaultPowerModeMessage = NSLocalizedString("Default power mode is used when no specific app or website matches are found", comment: "Info tip message for default Power Mode")
        static let whenToTriggerTitle = NSLocalizedString("When to Trigger", comment: "Section title for Power Mode triggers")
        static let transcriptionSectionTitle = NSLocalizedString("Transcription", comment: "Section title for transcription settings")
        static let aiEnhancementSectionTitle = NSLocalizedString("AI Enhancement", comment: "Section title for AI enhancement settings")
        static let advancedSectionTitle = NSLocalizedString("Advanced", comment: "Section title for advanced settings")
        static let enableAIEnhancementLabel = NSLocalizedString("Enable AI Enhancement", comment: "Toggle label for AI enhancement")
        static let noModelsLoaded = NSLocalizedString("No models loaded", comment: "Empty state when no models are loaded")
        static let noModelsAvailable = NSLocalizedString("No models available", comment: "Empty state when no models are available")
        static let refreshModelsHelp = NSLocalizedString("Refresh models", comment: "Help text for refresh models button")
        static let saveChangesLabel = NSLocalizedString("Save Changes", comment: "Save changes button label")
        static let autoSendMessage = NSLocalizedString("Automatically presses the Return/Enter key after pasting text. This is useful for chat applications or forms where its not necessary to to make changes to the transcribed text", comment: "Info tip message for auto send")
        static let validationErrorsMessage = NSLocalizedString("Please fix the validation errors before saving.", comment: "Validation errors alert message")
        static let cannotSaveTitle = NSLocalizedString("Cannot Save Power Mode", comment: "Alert title when Power Mode cannot be saved")
        static let validationEmptyName = NSLocalizedString("Power mode name cannot be empty.", comment: "Validation error when Power Mode name is empty")
        static let validationDuplicateName = NSLocalizedString("A power mode with the name '%@' already exists.", comment: "Validation error for duplicate Power Mode name")
        static let validationDuplicateAppTrigger = NSLocalizedString("The app '%@' is already configured in the '%@' power mode.", comment: "Validation error for duplicate app trigger")
        static let validationDuplicateWebsiteTrigger = NSLocalizedString("The website '%@' is already configured in the '%@' power mode.", comment: "Validation error for duplicate website trigger")
        static let deletePowerModeTitle = NSLocalizedString("Delete Power Mode?", comment: "Delete Power Mode confirmation title")
        static let deletePowerModeMessage = NSLocalizedString("Are you sure you want to delete the '%@' power mode? This action cannot be undone.", comment: "Delete Power Mode confirmation message")
        static let selectApplicationsTitle = NSLocalizedString("Select Applications", comment: "Title for app picker sheet")
        static let searchApplicationsPlaceholder = NSLocalizedString("Search applications...", comment: "Search placeholder for applications list")
        static let powerModesTitle = NSLocalizedString("Power Modes", comment: "Power Modes view title")
        static let powerModesSubtitle = NSLocalizedString("Automate your workflows with context-aware configurations.", comment: "Power Modes subtitle")
        static let addPowerModeLabel = NSLocalizedString("Add Power Mode", comment: "Add Power Mode button label")
        static let addNewPowerModeLabel = NSLocalizedString("Add New Power Mode", comment: "Add new Power Mode button label")
        static let editPowerModeLabel = NSLocalizedString("Edit Power Mode", comment: "Edit Power Mode label")
        static let reorderLabel = NSLocalizedString("Reorder", comment: "Reorder button label")
        static let whatIsPowerModeTitle = NSLocalizedString("What is Power Mode?", comment: "Info tip title for Power Mode")
        static let whatIsPowerModeMessage = NSLocalizedString("Automatically apply custom configurations based on the app/website you are using", comment: "Info tip description for Power Mode")
        static let disabledLabel = NSLocalizedString("Disabled", comment: "Disabled label")
        static let noPowerModesYet = NSLocalizedString("No Power Modes Yet", comment: "Empty state title for Power Modes view")
        static let createFirstPowerMode = NSLocalizedString("Create first power mode to automate your %@ workflow based on apps/website you are using", comment: "Empty state description for Power Modes view")
        static let autoLabel = NSLocalizedString("Auto", comment: "Auto language label")
        static let englishLabel = NSLocalizedString("English", comment: "English language label")
        static let appCountSingle = NSLocalizedString("1 App", comment: "Single app count label")
        static let appCountMultiple = NSLocalizedString("%d Apps", comment: "Multiple app count label")
        static let websiteCountSingle = NSLocalizedString("1 Website", comment: "Single website count label")
        static let websiteCountMultiple = NSLocalizedString("%d Websites", comment: "Multiple website count label")
        static let aiLabel = NSLocalizedString("AI", comment: "AI label")
    }
    
    enum Export {
        static let success = NSLocalizedString("Export successful - Saved to %@", comment: "Success message when export completes")
        static let failed = NSLocalizedString("Export failed: %@", comment: "Error when export fails")
    }
}

// MARK: - String Extension for Easy Localization
extension String {
    var localized: String {
        return NSLocalizedString(self, comment: "")
    }
    
    func localized(with arguments: CVarArg...) -> String {
        return String(format: self.localized, arguments: arguments)
    }
}
