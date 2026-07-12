import Foundation

extension WhisperState {
    @discardableResult
    func persistTranscription(_ transcription: Transcription) -> Bool {
        do {
            try modelContext.save()
            return true
        } catch {
            logger.error("Failed to persist transcription: \(AppLogger.errorMetadata(error), privacy: .public)")
            NotificationManager.shared.showNotification(
                title: Localization.Transcription.saveFailed,
                type: .error
            )
            return false
        }
    }
}
