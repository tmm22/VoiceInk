import Foundation

/// A centralized string management system for VoiceInk.
/// This facilitates the migration from hardcoded strings to a localized system.
struct Localization {
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
        static let title = NSLocalizedString("Trash", comment: "Trash view title")
        static let emptyTrash = NSLocalizedString("Empty Trash", comment: "Empty trash button")
        static let restore = NSLocalizedString("Restore", comment: "Restore item from trash")
        static let deletePermanently = NSLocalizedString("Delete Permanently", comment: "Permanently delete item")
        static let trashIsEmpty = NSLocalizedString("Trash is Empty", comment: "Empty state title")
        static let trashEmptyDescription = NSLocalizedString("Deleted transcriptions will appear here", comment: "Empty state description")
        static let movedToTrash = NSLocalizedString("Moved to trash", comment: "Notification when item is moved to trash")
        static let restored = NSLocalizedString("Transcription restored", comment: "Notification when item is restored")
        static let restoredMultiple = NSLocalizedString("Transcriptions restored", comment: "Notification when multiple items are restored")
        static let permanentlyDeleted = NSLocalizedString("Permanently deleted", comment: "Notification when item is permanently deleted")
        static let itemCount = NSLocalizedString("%d item(s) in trash", comment: "Count of items in trash")
        static let daysUntilDeletion = NSLocalizedString("%d days until permanent deletion", comment: "Days remaining before permanent deletion")
        static let retentionInfo = NSLocalizedString("Items are permanently deleted after 30 days", comment: "Trash retention policy info")
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
