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
