import Foundation
import SwiftUI
import os

/// Manages UI state and interactions for Whisper transcription
@MainActor
class UIManager: ObservableObject, UIManagerProtocol {
    // MARK: - Published State

    @Published var isRecordingUIVisible = false
    @Published var recordingProgress: Double = 0.0
    @Published var isModelLoading = false

    // MARK: - Dependencies

    private weak var whisperState: AnyObject?

    private let logger = Logger(subsystem: "com.tmm22.voicelinkcommunity", category: "UIManager")

    // MARK: - Initialization

    init(whisperState: AnyObject) {
        self.whisperState = whisperState
    }

    // MARK: - UIManagerProtocol Implementation

    func showRecordingUI() {
        // Delegate to existing window managers through WhisperState
        // This will be implemented when we update WhisperState
        isRecordingUIVisible = true
        logger.notice("📱 Showing recording UI")
    }

    func hideRecordingUI() {
        // Delegate to existing window managers through WhisperState
        // This will be implemented when we update WhisperState
        isRecordingUIVisible = false
        logger.notice("📱 Hiding recording UI")
    }

    func updateRecordingProgress(_ progress: Double) {
        recordingProgress = progress
    }

    func showTranscriptionResult(_ text: String) {
        // Copy to clipboard - this can be done without external dependencies
        #if os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        #endif

        // Notification will be handled by existing NotificationManager
        logger.info("📋 Transcription result shown: \(text.count) characters")
    }

    func showError(_ error: Error) {
        // Error display will be handled by existing NotificationManager
        logger.error("❌ Error to display: \(error.localizedDescription)")
    }

    func updateModelLoadingState(isLoading: Bool) {
        isModelLoading = isLoading
    }

    // MARK: - Additional UI Management Methods

    func toggleRecordingUI() async {
        // Implementation will delegate to WhisperState methods
        logger.info("🔄 Toggling recording UI")
    }

    func dismissRecordingUI() async {
        // Implementation will delegate to WhisperState methods
        logger.info("🔄 Dismissing recording UI")
    }

    func cancelRecording() async {
        // Implementation will delegate to WhisperState methods
        logger.info("🚫 Cancelling recording")
    }

    func resetOnLaunch() async {
        // Implementation will delegate to WhisperState methods
        logger.info("🔄 Resetting on launch")
    }

    // MARK: - Window Management

    func handleRecorderTypeChange(from oldType: String, to newType: String) {
        logger.info("🔄 Recorder type changed from \(oldType) to \(newType)")
    }

    // MARK: - Notification Handling

    func setupNotifications() {
        // Notification setup will be handled by WhisperState
        logger.info("🔄 Setting up notifications")
    }

    deinit {
        logger.info("🗑️ UIManager deallocated")
    }
}