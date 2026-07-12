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

    func toggleMiniRecorder(powerModeId: UUID? = nil) async {
        logger.notice("toggleMiniRecorder called – visible=\(self.isMiniRecorderVisible), state=\(String(describing: self.recordingState))")
        if isMiniRecorderVisible {
            if recordingState == .recording {
                logger.notice("toggleMiniRecorder: stopping recording (was recording)")
                await toggleRecord(powerModeId: powerModeId)
            } else {
                logger.notice("toggleMiniRecorder: cancelling (was not recording)")
                await cancelRecording()
            }
        } else {
            SoundManager.shared.playStartSound()

            isMiniRecorderVisible = true // This will call showRecorderPanel() via didSet

            await toggleRecord(powerModeId: powerModeId)
        }
    }

    func dismissMiniRecorder() async {
        logger.notice("dismissMiniRecorder called – state=\(String(describing: self.recordingState))")
        if recordingState == .busy {
            logger.notice("dismissMiniRecorder: early return, state is busy")
            return
        }

        let wasRecording = recordingState == .recording

        recordingState = .busy

        // Cancel and release any active streaming session to prevent resource leaks.
        currentSession?.cancel()
        currentSession = nil

        if wasRecording {
            recorder.stopRecording()
        }

        hideRecorderPanel()

        // Clear captured context when the recorder is dismissed
        if let enhancementService = enhancementService {
            enhancementService.clearCapturedContexts()
        }

        isMiniRecorderVisible = false

        await cleanupModelResources()

        if UserDefaults.standard.bool(forKey: PowerModeDefaults.autoRestoreKey) {
            await PowerModeSessionManager.shared.endSession()
            PowerModeManager.shared.setActiveConfiguration(nil)
        }

        recordingState = .idle
        logger.notice("dismissMiniRecorder completed")
    }

    func resetOnLaunch() async {
        logger.notice("🔄 Resetting recording state on launch")
        recorder.stopRecording()
        hideRecorderPanel()
        isMiniRecorderVisible = false
        shouldCancelRecording = false
        miniRecorderError = nil
        recordingState = .idle
        await cleanupModelResources()
    }

    func cancelRecording() async {
        logger.notice("cancelRecording called")
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
        logger.notice("handleToggleMiniRecorder: .toggleMiniRecorder notification received")
        Task {
            await toggleMiniRecorder()
        }
    }

    @objc public func handleDismissMiniRecorder() {
        logger.notice("handleDismissMiniRecorder: .dismissMiniRecorder notification received")
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
        let currentPrompt = UserDefaults.standard.string(forKey: "TranscriptionPrompt") ?? whisperPrompt.transcriptionPrompt

        if let modelName = loadedLocalModel?.name {
            await WhisperContextManager.shared.updatePrompt(currentPrompt, for: modelName)
        }
    }
}
