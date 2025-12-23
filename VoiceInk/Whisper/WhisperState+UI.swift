import Foundation
import SwiftUI
import os

// MARK: - UI Management Extension
extension WhisperState {
    
    // MARK: - Recorder Panel Management
    
    func showRecorderPanel() {
        logger.notice("📱 Showing \(self.recorderType) recorder")
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
        if recorderType == "notch" {
            notchWindowManager?.hide()
        } else {
            miniWindowManager?.hide()
        }
    }
    
    // MARK: - Mini Recorder Management
    
    func toggleMiniRecorder() async {
        if isMiniRecorderVisible {
            if recordingState == .recording {
                await toggleRecord()
            } else {
                await cancelRecording()
            }
        } else {
            SoundManager.shared.playStartSound()

            // No need for MainActor.run - WhisperState is already @MainActor
            isMiniRecorderVisible = true // This will call showRecorderPanel() via didSet

            await toggleRecord()
        }
    }
    
    func dismissMiniRecorder() async {
        if recordingState == .busy { return }

        let wasRecording = recordingState == .recording
 
        // No need for MainActor.run - WhisperState is already @MainActor
        self.recordingState = .busy
        
        if wasRecording {
            recorder.stopRecording()
        }
        
        hideRecorderPanel()
        
        // Clear captured context when the recorder is dismissed
        if let enhancementService = enhancementService {
            // No need for MainActor.run - WhisperState is already @MainActor
            enhancementService.clearCapturedContexts()
        }
        
        // No need for MainActor.run - WhisperState is already @MainActor
        isMiniRecorderVisible = false
        
        await cleanupModelResources()
        
        if AppSettings.PowerMode.autoRestoreEnabled ?? false {
            await PowerModeSessionManager.shared.endSession()
            // No need for MainActor.run - WhisperState is already @MainActor
            PowerModeManager.shared.setActiveConfiguration(nil)
        }
        
        // No need for MainActor.run - WhisperState is already @MainActor
        recordingState = .idle
    }
    
    func resetOnLaunch() async {
        logger.notice("🔄 Resetting recording state on launch")
        recorder.stopRecording()
        hideRecorderPanel()
        // No need for MainActor.run - WhisperState is already @MainActor
        isMiniRecorderVisible = false
        shouldCancelRecording = false
        miniRecorderError = nil
        recordingState = .idle
        await cleanupModelResources()
    }
    
    func cancelRecording() async {
        SoundManager.shared.playEscSound()
        shouldCancelRecording = true
        await dismissMiniRecorder()
    }
    
    // MARK: - Notification Handling
    
    func setupNotifications() {
        NotificationCenter.default.addObserver(self, selector: #selector(handleToggleMiniRecorder), name: .toggleMiniRecorder, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleDismissMiniRecorder), name: .dismissMiniRecorder, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleLicenseStatusChanged), name: .licenseStatusChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handlePromptChange), name: .promptDidChange, object: nil)
    }
    
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
