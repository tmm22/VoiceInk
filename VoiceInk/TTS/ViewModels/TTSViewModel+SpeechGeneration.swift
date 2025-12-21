import SwiftUI
import AVFoundation

// MARK: - Speech Generation
extension TTSViewModel {
    func generateSpeech() async {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)

        let sanitized = stripBatchDelimiters(from: trimmed)

        guard !sanitized.isEmpty else {
            errorMessage = "Please enter some text"
            return
        }

        stopPreview()

        let providerType = selectedProvider
        let provider = getProvider(for: providerType)
        let voice = selectedVoice ?? provider.defaultVoice
        let format = currentFormatForGeneration()
        let providerLimit = characterLimit(for: providerType)

        if sanitized.count > providerLimit {
            await generateLongFormSpeech(
                text: sanitized,
                providerType: providerType,
                voice: voice,
                format: format,
                shouldAutoplay: true
            )
            return
        }

        guard sanitized.count <= providerLimit else {
            errorMessage = "Text exceeds maximum length of \(formattedCharacterLimit(for: providerType)) characters"
            return
        }

        isGenerating = true
        errorMessage = nil
        generationProgress = 0
        
        do {
            let preparedText = applyPronunciationRules(to: sanitized, provider: providerType)
            let output = try await performGeneration(
                text: preparedText,
                providerType: providerType,
                voice: voice,
                format: format,
                shouldAutoplay: true
            )
            currentTranscript = output.transcript
            recordGenerationHistory(
                audioData: output.audioData,
                format: format,
                text: preparedText,
                voice: voice,
                provider: providerType,
                duration: output.duration,
                transcript: output.transcript
            )
        } catch let error as TTSError {
            errorMessage = error.localizedDescription
        } catch {
            errorMessage = "Failed to generate speech: \(error.localizedDescription)"
        }

        isGenerating = false
        generationProgress = 0
    }

    func startBatchGeneration() {
        let segments = batchSegments(from: inputText)

        guard segments.count > 1 else {
            Task { await generateSpeech() }
            return
        }

        stopPreview()

        let providerType = selectedProvider
        let provider = getProvider(for: providerType)
        let voice = selectedVoice ?? provider.defaultVoice
        let voiceSnapshot = BatchGenerationItem.VoiceSnapshot(id: voice.id, name: voice.name)
        let format = currentFormatForGeneration()

        batchTask?.cancel()
        batchItems = segments.enumerated().map { index, text in
            BatchGenerationItem(
                index: index + 1,
                text: text,
                provider: providerType,
                voice: voiceSnapshot
            )
        }

        batchProgress = 0
        isBatchRunning = true
        errorMessage = nil
        currentTranscript = nil

        batchTask = Task { [weak self] in
            await self?.processBatch(
                segments: segments,
                providerType: providerType,
                voice: voice,
                format: format
            )
        }
    }

    func cancelBatchGeneration() {
        guard batchTask != nil || isBatchRunning else { return }

        batchTask?.cancel()
        batchTask = nil
        isBatchRunning = false
        isGenerating = false
        generationProgress = 0
        batchProgress = 0

        batchItems = batchItems.map { item in
            var updated = item
            switch item.status {
            case .pending, .inProgress:
                updated.status = .failed("Cancelled")
            default:
                break
            }
            return updated
        }

        audioPlayer.stop()
    }
}

// MARK: - Speech Generation Private Helpers
extension TTSViewModel {
    func synthesizeSpeechWithFallback(text: String,
                                      voice: Voice,
                                      provider: TTSProvider,
                                      providerType: TTSProviderType,
                                      settings baseSettings: AudioSettings) async throws -> Data {
        var attemptSettings = baseSettings
        var hasRetried = false

        while true {
            do {
                return try await provider.synthesizeSpeech(
                    text: text,
                    voice: voice,
                    settings: attemptSettings
                )
            } catch let error as TTSError {
                guard providerType == .elevenLabs,
                      case .apiError(let message) = error,
                      !hasRetried,
                      let context = elevenLabsFallbackContext(for: message, currentModelID: attemptSettings.providerOption(for: ElevenLabsProviderOptionKey.modelID))
                else {
                    throw error
                }

                hasRetried = true
                elevenLabsModel = context.fallback
                attemptSettings.providerOptions[ElevenLabsProviderOptionKey.modelID] = context.fallback.rawValue

                errorMessage = "\(context.current.displayName) isn't available on this ElevenLabs account yet. Switched to \(context.fallback.displayName)."
                continue
            }
        }
    }

    func elevenLabsFallbackContext(for message: String,
                                   currentModelID: String?) -> (current: ElevenLabsModel, fallback: ElevenLabsModel)? {
        let lowered = message.lowercased()
        guard lowered.contains("model with model id"), lowered.contains("does not exist") else {
            return nil
        }

        let activeModelID = currentModelID ?? elevenLabsModel.rawValue
        guard let currentModel = ElevenLabsModel(rawValue: activeModelID),
              let fallback = currentModel.fallback else {
            return nil
        }

        return (currentModel, fallback)
    }

    @MainActor
    func processBatch(segments: [String],
                      providerType: TTSProviderType,
                      voice: Voice,
                      format: AudioSettings.AudioFormat) async {
        var successCount = 0
        var failureCount = 0

        for index in batchItems.indices {
            if Task.isCancelled { break }

            let segmentText = segments[index]
            let trimmedSegment = segmentText.trimmingCharacters(in: .whitespacesAndNewlines)
            batchItems[index].status = .inProgress
            isGenerating = true
            generationProgress = 0

            if trimmedSegment.isEmpty {
                batchItems[index].status = .failed("Segment \(index + 1) is empty.")
                batchProgress = Double(index + 1) / Double(batchItems.count)
                isGenerating = false
                generationProgress = 0
                failureCount += 1
                continue
            }

            do {
                let preparedText = applyPronunciationRules(to: trimmedSegment, provider: providerType)
                let output = try await performGeneration(
                    text: preparedText,
                    providerType: providerType,
                    voice: voice,
                    format: format,
                    shouldAutoplay: false
                )

                batchItems[index].status = .completed
                recordGenerationHistory(
                    audioData: output.audioData,
                    format: format,
                    text: preparedText,
                    voice: voice,
                    provider: providerType,
                    duration: output.duration,
                    transcript: output.transcript
                )
                currentTranscript = output.transcript
                successCount += 1
            } catch is CancellationError {
                batchItems[index].status = .failed("Cancelled")
                isGenerating = false
                generationProgress = 0
                break
            } catch let error as TTSError {
                batchItems[index].status = .failed(error.localizedDescription)
                failureCount += 1
            } catch {
                batchItems[index].status = .failed(error.localizedDescription)
                failureCount += 1
            }

            batchProgress = Double(index + 1) / Double(batchItems.count)
            isGenerating = false
            generationProgress = 0
        }

        if Task.isCancelled {
            isBatchRunning = false
            batchTask = nil
            return
        }

        batchProgress = batchItems.isEmpty ? 0 : 1
        isGenerating = false
        generationProgress = 0
        isBatchRunning = false
        batchTask = nil
        audioPlayer.stop()

        if !Task.isCancelled {
            sendBatchCompletionNotification(successCount: successCount, failureCount: failureCount)
        }
    }

    func performGeneration(text: String,
                           providerType: TTSProviderType,
                           voice: Voice,
                           format: AudioSettings.AudioFormat,
                           shouldAutoplay: Bool,
                           loadIntoPlayer: Bool = true) async throws -> GenerationOutput {
        let provider = getProvider(for: providerType)

        guard provider.hasValidAPIKey() else {
            throw TTSError.invalidAPIKey
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw TTSError.apiError("Segment text is empty.")
        }

        let limit = characterLimit(for: providerType)
        if trimmed.count > limit {
            throw TTSError.textTooLong(limit)
        }

        var settings = AudioSettings(
            speed: playbackSpeed,
            volume: volume,
            format: format,
            sampleRate: sampleRate(for: format),
            styleValues: styleValues(for: providerType)
        )

        if providerType == .elevenLabs {
            settings.providerOptions[ElevenLabsProviderOptionKey.modelID] = elevenLabsModel.rawValue
        }

        if loadIntoPlayer {
            generationProgress = 0.3
        }

        let data = try await synthesizeSpeechWithFallback(
            text: trimmed,
            voice: voice,
            provider: provider,
            providerType: providerType,
            settings: settings
        )

        let duration: TimeInterval
        if loadIntoPlayer {
            generationProgress = 0.7
            try await audioPlayer.loadAudio(from: data)
            applyPlaybackSettings()
            audioData = data
            currentAudioFormat = format
            duration = audioPlayer.duration
        } else {
            let tempPlayer = try AVAudioPlayer(data: data)
            duration = tempPlayer.duration
        }

        let transcript = TranscriptBuilder.makeTranscript(for: trimmed, duration: duration)
        if loadIntoPlayer {
            currentTranscript = transcript
            generationProgress = 1.0

            if shouldAutoplay {
                await play()
            } else {
                isPlaying = false
            }
        }

        return GenerationOutput(audioData: data, transcript: transcript, duration: duration)
    }
}
