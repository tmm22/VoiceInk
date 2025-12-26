import Foundation
import SwiftUI
import os

// MARK: - UI Management Extension
extension WhisperState {
    
    // MARK: - Recorder Panel Management

    func showRecorderPanel() {
        // Show the appropriate recorder panel based on recorderType
        if recorderType == "notch" {
            if notchWindowManager == nil {
                notchWindowManager = NotchWindowManager(whisperState: self, recorder: recorder)
            }
            notchWindowManager?.show()
        } else {
            if miniWindowManager == nil {
                miniWindowManager = MiniWindowManager(whisperState: self, recorder: recorder)
            }
            miniWindowManager?.show()
        }
    }

    func hideRecorderPanel() {
        // Hide the appropriate recorder panel based on recorderType
        if recorderType == "notch" {
            notchWindowManager?.hide()
        } else {
            miniWindowManager?.hide()
        }
    }
    
    // MARK: - Mini Recorder Management

    func toggleMiniRecorder() async {
        // Toggle the mini recorder visibility and recording state
        if isMiniRecorderVisible {
            // Stop recording and hide the recorder
            await toggleRecord()
        } else {
            // Show the recorder and start recording
            isMiniRecorderVisible = true
            showRecorderPanel()
            SoundManager.shared.playStartSound()
            await toggleRecord()
        }
    }
    
    func dismissMiniRecorder() async {
        // Dismiss the mini recorder without stopping recording (recording already stopped)
        isMiniRecorderVisible = false
        hideRecorderPanel()
        
        // Clean up window managers
        if recorderType == "notch" {
            notchWindowManager = nil
        } else {
            miniWindowManager = nil
        }
        
        recordingState = .idle
    }
    
    func resetOnLaunch() async {
        // Reset state on app launch
        isMiniRecorderVisible = false
        recordingState = .idle
        miniWindowManager?.hide()
        notchWindowManager?.hide()
        miniWindowManager = nil
        notchWindowManager = nil
    }

    func cancelRecording() async {
        // Cancel the current recording
        shouldCancelRecording = true
        await recordingSessionManager.cancelRecording()
        await dismissMiniRecorder()
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
