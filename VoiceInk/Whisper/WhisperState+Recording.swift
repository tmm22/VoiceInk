import Foundation
import AVFoundation

// MARK: - Recording and Transcription
extension WhisperState {
    func toggleRecord() async {
        if recordingState == .recording {
            recorder.stopRecording()
            if let recordedFile {
                if !shouldCancelRecording {
                    let audioAsset = AVURLAsset(url: recordedFile)
                    let duration: TimeInterval
                    do {
                        let assetDuration = try await audioAsset.load(.duration)
                        duration = CMTimeGetSeconds(assetDuration)
                    } catch {
                        logger.error("Failed to load recording duration: \(error.localizedDescription)")
                        duration = 0.0
                    }

                    let transcription = Transcription(
                        text: "",
                        duration: duration,
                        audioFileURL: recordedFile.absoluteString,
                        transcriptionStatus: .pending
                    )
                    modelContext.insert(transcription)
                    do {
                        try modelContext.save()
                    } catch {
                        logger.error("Failed to save transcription: \(error.localizedDescription)")
                    }
                    NotificationCenter.default.post(name: .transcriptionCreated, object: transcription)

                    await transcribeAudio(on: transcription)
                } else {
                    recordingState = .idle
                    await cleanupModelResources()
                }
            } else {
                logger.error("❌ No recorded file found after stopping recording")
                recordingState = .idle
            }
        } else {
            guard currentTranscriptionModel != nil else {
                NotificationManager.shared.showNotification(
                    title: Localization.Models.noModelSelected,
                    type: .error
                )
                return
            }
            shouldCancelRecording = false
            requestRecordPermission { [weak self] granted in
                guard let self else { return }
                if granted {
                    Task { [weak self] in
                        guard let self = self else { return }
                        do {
                            let fileName = "\(UUID().uuidString).wav"
                            let permanentURL = self.recordingsDirectory.appendingPathComponent(fileName)
                            self.recordedFile = permanentURL

                            try await self.recorder.startRecording(toOutputFile: permanentURL)

                            self.recordingState = .recording

                            await ActiveWindowService.shared.applyConfigurationForCurrentApp()

                            Task.detached { [weak self] in
                                guard let self = self else { return }

                                if let model = await self.currentTranscriptionModel, model.provider == .local {
                                    if let localWhisperModel = await self.availableModels.first(where: { $0.name == model.name }),
                                       await self.whisperContext == nil {
                                        do {
                                            try await self.loadModel(localWhisperModel)
                                        } catch {
                                            self.logger.error("❌ Model loading failed: \(error.localizedDescription)")
                                        }
                                    }
                                } else if let parakeetModel = await self.currentTranscriptionModel as? ParakeetModel {
                                    do {
                                        try await self.parakeetTranscriptionService.loadModel(for: parakeetModel)
                                    } catch {
                                        self.logger.error("❌ Failed to load Parakeet model: \(error.localizedDescription)")
                                    }
                                }

                                if let enhancementService = self.enhancementService {
                                    await enhancementService.captureClipboardContext()
                                    await enhancementService.captureScreenContext()
                                }
                            }

                        } catch {
                            self.logger.error("❌ Failed to start recording: \(error.localizedDescription)")
                            NotificationManager.shared.showNotification(title: Localization.Recording.failedToStart, type: .error)
                            await self.dismissMiniRecorder()
                            self.recordedFile = nil
                        }
                    }
                } else {
                    self.logger.error("❌ Recording permission denied.")
                }
            }
        }
    }

    private func requestRecordPermission(response: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            response(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                response(granted)
            }
        case .denied, .restricted:
            response(false)
        @unknown default:
            response(false)
        }
    }

    private func transcribeAudio(on transcription: Transcription) async {
        guard let urlString = transcription.audioFileURL, let url = URL(string: urlString) else {
            logger.error("❌ Invalid audio file URL in transcription object.")
            recordingState = .idle
            transcription.text = "Transcription Failed: Invalid audio file URL"
            transcription.transcriptionStatus = TranscriptionStatus.failed.rawValue
            do {
                try modelContext.save()
            } catch {
                logger.error("Failed to save failed transcription: \(error.localizedDescription)")
            }
            return
        }

        if shouldCancelRecording {
            recordingState = .idle
            await cleanupModelResources()
            return
        }

        recordingState = .transcribing

        Task { @MainActor [weak self] in
            guard self != nil else { return }
            let isSystemMuteEnabled = AppSettings.Audio.isSystemMuteEnabled
            if isSystemMuteEnabled {
                // Best-effort delay; cancellation is non-critical here.
                try? await Task.sleep(nanoseconds: 200_000_000) // 200 milliseconds delay
            }
            SoundManager.shared.playStopSound()
        }

        defer {
            if shouldCancelRecording {
                Task { [weak self] in
                    await self?.cleanupModelResources()
                }
            }
        }

        logger.notice("🔄 Starting transcription...")

        var finalPastedText: String?
        var promptDetectionResult: PromptDetectionService.PromptDetectionResult?

        do {
            guard let model = currentTranscriptionModel else {
                throw WhisperStateError.transcriptionFailed
            }

            let transcriptionService: TranscriptionService
            switch model.provider {
            case .local:
                guard let service = localTranscriptionService else {
                    throw WhisperStateError.transcriptionFailed
                }
                transcriptionService = service
            case .parakeet:
                transcriptionService = parakeetTranscriptionService
            case .fastConformer:
                transcriptionService = fastConformerTranscriptionService
            case .senseVoice:
                transcriptionService = senseVoiceTranscriptionService
            case .nativeApple:
                transcriptionService = nativeAppleTranscriptionService
            default:
                transcriptionService = cloudTranscriptionService
            }

            let transcriptionStart = Date()
            var text = try await transcriptionService.transcribe(audioURL: url, model: model)
            logger.notice("📝 Raw transcript: \(text, privacy: .public)")
            text = TranscriptionOutputFilter.filter(text)
            logger.notice("📝 Output filter result: \(text, privacy: .public)")
            let transcriptionDuration = Date().timeIntervalSince(transcriptionStart)

            let powerModeManager = PowerModeManager.shared
            let activePowerModeConfig = powerModeManager.currentActiveConfiguration
            let powerModeName = (activePowerModeConfig?.isEnabled == true) ? activePowerModeConfig?.name : nil
            let powerModeEmoji = (activePowerModeConfig?.isEnabled == true) ? activePowerModeConfig?.emoji : nil

            if await checkCancellationAndCleanup() { return }

            text = text.trimmingCharacters(in: .whitespacesAndNewlines)

            if AppSettings.TranscriptionSettings.isTextFormattingEnabled {
                text = WhisperTextFormatter.format(text)
                logger.notice("📝 Formatted transcript: \(text, privacy: .public)")
            }

            text = WordReplacementService.shared.applyReplacements(to: text)
            logger.notice("📝 WordReplacement: \(text, privacy: .public)")

            let audioAsset = AVURLAsset(url: url)
            let actualDuration: TimeInterval
            do {
                let assetDuration = try await audioAsset.load(.duration)
                actualDuration = CMTimeGetSeconds(assetDuration)
            } catch {
                logger.error("Failed to load transcription duration: \(error.localizedDescription)")
                actualDuration = 0.0
            }

            transcription.text = text
            transcription.duration = actualDuration
            transcription.transcriptionModelName = model.displayName
            transcription.transcriptionDuration = transcriptionDuration
            transcription.powerModeName = powerModeName
            transcription.powerModeEmoji = powerModeEmoji
            finalPastedText = text

            if let enhancementService = enhancementService, enhancementService.isConfigured {
                let detectionResult = promptDetectionService.analyzeText(text, with: enhancementService)
                promptDetectionResult = detectionResult
                await promptDetectionService.applyDetectionResult(detectionResult, to: enhancementService)
            }

            if let enhancementService = enhancementService,
               enhancementService.isEnhancementEnabled,
               enhancementService.isConfigured {
                if await checkCancellationAndCleanup() { return }

                self.recordingState = .enhancing
                let textForAI = promptDetectionResult?.processedText ?? text

                do {
                    let selectedLanguage = AppSettings.TranscriptionSettings.selectedLanguage ?? "en"
                    let (enhancedText, enhancementDuration, promptName) = try await enhancementService.enhance(
                        textForAI,
                        transcriptionModel: model.displayName,
                        recordingDuration: transcription.duration,
                        language: selectedLanguage
                    )
                    logger.notice("📝 AI enhancement: \(enhancedText, privacy: .public)")
                    transcription.enhancedText = enhancedText
                    transcription.aiEnhancementModelName = enhancementService.getAIService()?.currentModel
                    transcription.promptName = promptName
                    transcription.enhancementDuration = enhancementDuration
                    transcription.aiRequestSystemMessage = enhancementService.lastSystemMessageSent
                    transcription.aiRequestUserMessage = enhancementService.lastUserMessageSent
                    transcription.aiContextJSON = enhancementService.lastCapturedContextJSON
                    finalPastedText = enhancedText
                } catch {
                    transcription.enhancedText = "Enhancement failed: \(error)"

                    if await checkCancellationAndCleanup() { return }
                }
            }

            transcription.transcriptionStatus = TranscriptionStatus.completed.rawValue

        } catch {
            let errorDescription = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            let recoverySuggestion = (error as? LocalizedError)?.recoverySuggestion ?? ""
            let fullErrorText = recoverySuggestion.isEmpty ? errorDescription : "\(errorDescription) \(recoverySuggestion)"

            transcription.text = "Transcription Failed: \(fullErrorText)"
            transcription.transcriptionStatus = TranscriptionStatus.failed.rawValue
        }

        do {
            try modelContext.save()
        } catch {
            logger.error("Failed to save transcription: \(error.localizedDescription)")
        }

        if transcription.transcriptionStatus == TranscriptionStatus.completed.rawValue {
            NotificationCenter.default.post(name: .transcriptionCompleted, object: transcription)
        }

        if await checkCancellationAndCleanup() { return }

        if var textToPaste = finalPastedText, transcription.transcriptionStatus == TranscriptionStatus.completed.rawValue {
            let shouldAddSpace = AppSettings.TranscriptionSettings.appendTrailingSpace
            if shouldAddSpace {
                textToPaste += " "
            }

            Task { @MainActor [weak self] in
                guard self != nil else { return }
                // Best-effort delay; ignore cancellation.
                try? await Task.sleep(nanoseconds: 50_000_000) // 0.05 seconds
                CursorPaster.pasteAtCursor(textToPaste)

                let powerMode = PowerModeManager.shared
                if let activeConfig = powerMode.currentActiveConfiguration, activeConfig.isAutoSendEnabled {
                    // Best-effort delay; ignore cancellation.
                    try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
                    CursorPaster.pressEnter()
                }
            }
        }

        if let result = promptDetectionResult,
           let enhancementService = enhancementService,
           result.shouldEnableAI {
            await promptDetectionService.restoreOriginalSettings(result, to: enhancementService)
        }

        await self.dismissMiniRecorder()

        shouldCancelRecording = false
    }

    func getEnhancementService() -> AIEnhancementService? {
        enhancementService
    }

    private func checkCancellationAndCleanup() async -> Bool {
        if shouldCancelRecording {
            await cleanupModelResources()
            return true
        }
        return false
    }

    private func cleanupAndDismiss() async {
        await dismissMiniRecorder()
    }
}
