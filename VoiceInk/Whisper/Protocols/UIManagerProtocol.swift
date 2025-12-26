import Foundation

/// Protocol for managing UI state and interactions
@MainActor
protocol UIManagerProtocol {
    /// Show recording UI
    func showRecordingUI()

    /// Hide recording UI
    func hideRecordingUI()

    /// Update recording progress
    func updateRecordingProgress(_ progress: Double)

    /// Show transcription result
    func showTranscriptionResult(_ text: String)

    /// Show error message
    func showError(_ error: Error)

    /// Update model loading state
    func updateModelLoadingState(isLoading: Bool)
}