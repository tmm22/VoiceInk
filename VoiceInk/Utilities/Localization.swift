import Foundation

/// A centralized string management system for VoiceInk.
/// This facilitates the migration from hardcoded strings to a localized system.
struct Localization {
    
    /// Returns the app's display name dynamically from the bundle
    static var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? "VoiceInk"
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
        static let learnMore = NSLocalizedString("Learn more", comment: "General learn more action")
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

    enum Enhancement {
        static let failedTitle = NSLocalizedString("Enhancement failed", comment: "Notification title when AI enhancement fails")
    }

    enum TTS {
        static let translation = NSLocalizedString("Translation", comment: "TTS translation card title")
        static let useTranslation = NSLocalizedString("Use Translation", comment: "Use translated text action")
        static let viewDetails = NSLocalizedString("View Details", comment: "View translation details action")
        static let costEstimate = NSLocalizedString("Cost Estimate", comment: "TTS cost estimate title")
        static let costEstimateDescription = NSLocalizedString("Estimate reflects your current provider and text length.", comment: "TTS cost estimate description")
        static let openInspector = NSLocalizedString("Open Inspector", comment: "Open TTS inspector action")
        static let smartImport = NSLocalizedString("Smart Import", comment: "Smart article import title")
        static let cleaningArticle = NSLocalizedString("Cleaning the article with AI…", comment: "Article cleanup progress")
        static let importArticleHint = NSLocalizedString("Use Import to pull a web article and see an AI summary here.", comment: "Smart import empty-state hint")
        static let useConciseArticle = NSLocalizedString("Use Concise Article", comment: "Use condensed article action")
        static let insertSummary = NSLocalizedString("Insert Summary", comment: "Insert article summary action")
        static let speakSummary = NSLocalizedString("Speak Summary", comment: "Speak article summary action")
        static let generating = NSLocalizedString("Generating…", comment: "Speech generation progress")
        static let detailedCostEstimateHelp = NSLocalizedString("View detailed cost estimate", comment: "Cost estimate button help")

        static let apiKeys = NSLocalizedString("API Keys", comment: "TTS API keys settings title")
        static let keychainStorageDescription = NSLocalizedString("Your API keys are stored securely in the macOS Keychain.", comment: "API key storage description")
        static let elevenLabs = NSLocalizedString("ElevenLabs", comment: "ElevenLabs provider name")
        static let openAI = NSLocalizedString("OpenAI", comment: "OpenAI provider name")
        static let googleCloudTTS = NSLocalizedString("Google Cloud TTS", comment: "Google Cloud TTS provider name")
        static let getAPIKey = NSLocalizedString("Get API Key", comment: "Open provider API key page action")
        static let elevenLabsKeyPlaceholder = NSLocalizedString("Enter your ElevenLabs API key", comment: "ElevenLabs API key field placeholder")
        static let openAIKeyPlaceholder = NSLocalizedString("Enter your OpenAI API key", comment: "OpenAI API key field placeholder")
        static let googleKeyPlaceholder = NSLocalizedString("Enter your Google Cloud API key", comment: "Google Cloud API key field placeholder")
        static let maskedKeyFormat = NSLocalizedString("Key: %@", comment: "Masked API key label")
        static let managedProvisioning = NSLocalizedString("Managed Provisioning", comment: "Managed credentials settings title")
        static let managedAccountStatusFormat = NSLocalizedString("Plan: %@ • Status: %@", comment: "Managed account plan and status")
        static let enableManagedCredentials = NSLocalizedString("Enable managed credentials", comment: "Managed credentials toggle")
        static let baseURL = NSLocalizedString("Base URL", comment: "Managed service base URL field")
        static let accountID = NSLocalizedString("Account ID", comment: "Managed account identifier field")
        static let planTier = NSLocalizedString("Plan Tier", comment: "Managed account plan tier field")
        static let planStatus = NSLocalizedString("Plan Status", comment: "Managed account plan status field")
        static let refreshAccount = NSLocalizedString("Refresh Account", comment: "Refresh managed account action")
        static let clear = NSLocalizedString("Clear", comment: "Clear content action")

        static let skipBackward = NSLocalizedString("Skip backward 10 seconds", comment: "Playback skip-back action and accessibility label")
        static let skipBackwardHelp = NSLocalizedString("Skip backward 10 seconds (⌘←)", comment: "Playback skip-back keyboard shortcut help")
        static let play = NSLocalizedString("Play", comment: "Playback play action")
        static let pause = NSLocalizedString("Pause", comment: "Playback pause action")
        static let playPauseHelp = NSLocalizedString("Play/Pause (Space)", comment: "Playback play/pause keyboard shortcut help")
        static let skipForward = NSLocalizedString("Skip forward 10 seconds", comment: "Playback skip-forward action and accessibility label")
        static let skipForwardHelp = NSLocalizedString("Skip forward 10 seconds (⌘→)", comment: "Playback skip-forward keyboard shortcut help")
        static let stop = NSLocalizedString("Stop", comment: "Playback stop action")
        static let stopHelp = NSLocalizedString("Stop playback (⌘.)", comment: "Playback stop keyboard shortcut help")
        static let playbackPosition = NSLocalizedString("Playback position", comment: "Playback position slider accessibility label")
        static let playbackPositionValueFormat = NSLocalizedString("%@ of %@", comment: "Current and total playback time accessibility value")
        static let speed = NSLocalizedString("Speed:", comment: "Playback speed label")
        static let playbackSpeed = NSLocalizedString("Playback speed", comment: "Playback speed picker label")
        static let speedHalf = NSLocalizedString("0.5×", comment: "Half playback speed option")
        static let speedThreeQuarters = NSLocalizedString("0.75×", comment: "Three-quarter playback speed option")
        static let speedNormal = NSLocalizedString("1.0×", comment: "Normal playback speed option")
        static let speedOneAndQuarter = NSLocalizedString("1.25×", comment: "One-and-a-quarter playback speed option")
        static let speedOneAndHalf = NSLocalizedString("1.5×", comment: "One-and-a-half playback speed option")
        static let speedOneAndThreeQuarters = NSLocalizedString("1.75×", comment: "One-and-three-quarter playback speed option")
        static let speedDouble = NSLocalizedString("2.0×", comment: "Double playback speed option")
        static let decreaseSpeed = NSLocalizedString("Decrease speed", comment: "Decrease playback speed action")
        static let decreaseSpeedHelp = NSLocalizedString("Decrease speed (⌘[)", comment: "Decrease speed keyboard shortcut help")
        static let increaseSpeed = NSLocalizedString("Increase speed", comment: "Increase playback speed action")
        static let increaseSpeedHelp = NSLocalizedString("Increase speed (⌘])", comment: "Increase speed keyboard shortcut help")
        static let volume = NSLocalizedString("Volume:", comment: "Playback volume label")
        static let volumeAccessibility = NSLocalizedString("Volume", comment: "Volume slider accessibility label")
        static let percentFormat = NSLocalizedString("%d percent", comment: "Percentage accessibility value")
        static let compactPercentFormat = NSLocalizedString("%d%%", comment: "Compact percentage display")
        static let mute = NSLocalizedString("Mute", comment: "Mute playback action")
        static let unmute = NSLocalizedString("Unmute", comment: "Unmute playback action")
        static let toggleMuteHelp = NSLocalizedString("Toggle mute", comment: "Mute button help")
        static let audioReady = NSLocalizedString("Audio Ready", comment: "Generated audio status")

        static let editorPlaceholder = NSLocalizedString("Enter text to convert to speech...", comment: "TTS editor placeholder")
        static let copyAll = NSLocalizedString("Copy All", comment: "Copy all editor text action")
        static let paste = NSLocalizedString("Paste", comment: "Paste editor text action")
        static let insertSampleText = NSLocalizedString("Insert Sample Text", comment: "Sample text menu title")
        static let shortSample = NSLocalizedString("Short Sample", comment: "Short sample text action")
        static let mediumSample = NSLocalizedString("Medium Sample", comment: "Medium sample text action")
        static let longSample = NSLocalizedString("Long Sample", comment: "Long sample text action")
        static let shortSampleText = NSLocalizedString("Hello! This is a sample text to demonstrate the text-to-speech functionality. The app supports multiple providers and voices, allowing you to create natural-sounding speech from any text.", comment: "Short TTS sample content")
        static let mediumSampleText = NSLocalizedString("Welcome to the Text-to-Speech Converter! This powerful application transforms your written text into natural-sounding speech using advanced AI technology.\n\nYou can choose from multiple providers including OpenAI, ElevenLabs, and Google Cloud Text-to-Speech. Each provider offers unique voices with different characteristics and languages.\n\nThe app features comprehensive playback controls, allowing you to play, pause, adjust speed, and control volume. You can also export the generated audio in various formats for use in your projects.", comment: "Medium TTS sample content")
        static let longSampleText = NSLocalizedString("The art of text-to-speech synthesis has evolved dramatically over the past decade. What once sounded robotic and unnatural has transformed into voices that are nearly indistinguishable from human speech.\n\nModern TTS systems use deep learning models trained on vast amounts of human speech data. These neural networks learn the subtle patterns of human vocalization, including intonation, rhythm, and emotional expression.\n\nThe applications are endless: from accessibility tools for the visually impaired, to audiobook narration, virtual assistants, and content creation. Educational institutions use TTS to make learning materials more accessible, while businesses employ it for customer service automation.\n\nAs we look to the future, the boundary between synthetic and human speech continues to blur. Voice cloning technology can now recreate specific voices with remarkable accuracy, opening new possibilities for preserving voices and creating personalized experiences.\n\nThis convergence of technology and human expression represents not just a technical achievement, but a fundamental shift in how we interact with information and each other in the digital age.", comment: "Long TTS sample content")
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
        static let failed = NSLocalizedString("Recording Failed", comment: "Title shown when recording fails")
        static let failedToStart = NSLocalizedString("Recording failed to start", comment: "Error when recording cannot start")
        static let noAudioDetected = NSLocalizedString("No Audio Detected", comment: "Warning when no audio input is detected")
        static let noAudioDescription = NSLocalizedString("Please check your microphone and try again.", comment: "Description for no audio detected")
        static let fileCorrupted = NSLocalizedString("Recording failed - audio file corrupted", comment: "Error when audio file is corrupted")
        static let encodeError = NSLocalizedString("Recording error: %@", comment: "Error during recording encode")
        static let cancelled = NSLocalizedString("Recording cancelled", comment: "Recording was cancelled")
        static let escToCancelHint = NSLocalizedString("Press ESC again to cancel recording", comment: "Hint for cancelling recording")
        static let switchedDevice = NSLocalizedString("Switched to: %@", comment: "Notification showing which audio device recording switched to")
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
