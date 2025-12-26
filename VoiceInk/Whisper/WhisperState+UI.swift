import Foundation
import SwiftUI
import os

// MARK: - UI Management Extension
extension WhisperState {
    
    // MARK: - Recorder Panel Management

    func showRecorderPanel() {
        // Delegate to UIManager (Phase 4 refactoring)
        uiManager?.showRecordingUI()
    }

    func hideRecorderPanel() {
        // Delegate to UIManager (Phase 4 refactoring)
        uiManager?.hideRecordingUI()
    }
    
    // MARK: - Mini Recorder Management

    func toggleMiniRecorder() async {
        // Delegate to UIManager (Phase 4 refactoring)
        await uiManager?.toggleRecordingUI()
    }
    
    func dismissMiniRecorder() async {
        // Delegate to UIManager (Phase 4 refactoring)
        await uiManager?.dismissRecordingUI()
    }
    
    func resetOnLaunch() async {
        // Delegate to UIManager (Phase 4 refactoring)
        await uiManager?.resetOnLaunch()
    }

    func cancelRecording() async {
        // Delegate to UIManager (Phase 4 refactoring)
        await uiManager?.cancelRecording()
    }
    
    // MARK: - Notification Handling

    // Note: setupNotifications() is now handled by UIManager (Phase 4 refactoring)
    // Keeping these methods for backward compatibility

    @objc public func handleToggleMiniRecorder() {
        Task {
            await toggleMiniRecorder()
        }
    }

    @objc public func handleDismissMiniRecorder() {
        Task {
            await dismissMiniRecorder()
        }
    }

    @objc func handleLicenseStatusChanged() {
        self.licenseViewModel = LicenseViewModel()
    }

    @objc func handlePromptChange() {
        // Update the whisper context with the new prompt
        Task {
            await updateContextPrompt()
        }
    }

    private func updateContextPrompt() async {
        // Always reload the prompt from UserDefaults to ensure we have the latest
        let currentPrompt = AppSettings.TranscriptionSettings.prompt ?? whisperPrompt.transcriptionPrompt

        if let context = whisperContext {
            await context.setPrompt(currentPrompt)
        }
    }
} 
