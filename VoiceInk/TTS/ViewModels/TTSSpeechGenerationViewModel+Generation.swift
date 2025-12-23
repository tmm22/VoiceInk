import Foundation
import AVFoundation

// MARK: - Generation Helpers
extension TTSSpeechGenerationViewModel {
    /// Synthesizes speech with retry logic for ElevenLabs model fallback scenarios.
    func synthesizeSpeechWithFallback(text: String,
                                      voice: Voice,
                                      provider: TTSProvider,
                                      providerType: TTSProviderType,
                                      settings baseSettings: AudioSettings) async throws -> Data {
        guard let coordinator else {
            throw TTSError.apiError("Speech coordinator unavailable.")
        }

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
                      let context = elevenLabsFallbackContext(
                        for: message,
                        currentModelID: attemptSettings.providerOption(for: ElevenLabsProviderOptionKey.modelID)
                      ) else {
                    throw error
                }

                hasRetried = true
                coordinator.elevenLabsModel = context.fallback
                attemptSettings.providerOptions[ElevenLabsProviderOptionKey.modelID] = context.fallback.rawValue

                coordinator.errorMessage = "\(context.current.displayName) isn't available on this ElevenLabs account yet. Switched to \(context.fallback.displayName)."
                continue
            }
        }
    }

    /// Parses an ElevenLabs error message to determine a fallback model option.
    func elevenLabsFallbackContext(for message: String,
                                   currentModelID: String?) -> (current: ElevenLabsModel, fallback: ElevenLabsModel)? {
        let lowered = message.lowercased()
        guard lowered.contains("model with model id"), lowered.contains("does not exist") else {
            return nil
        }

        let activeModelID = currentModelID ?? coordinator?.elevenLabsModel.rawValue ?? ElevenLabsModel.defaultSelection.rawValue
        guard let currentModel = ElevenLabsModel(rawValue: activeModelID),
              let fallback = currentModel.fallback else {
            return nil
        }

        return (currentModel, fallback)
    }

    @MainActor
    /// Processes batch segments sequentially, updating status and progress for each item.
    func processBatch(segments: [String],
                      providerType: TTSProviderType,
                      voice: Voice,
                      format: AudioSettings.AudioFormat) async {
        guard let coordinator else { return }

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
                let preparedText = coordinator.applyPronunciationRules(to: trimmedSegment, provider: providerType)
                let output = try await performGeneration(
                    text: preparedText,
                    providerType: providerType,
                    voice: voice,
                    format: format,
                    shouldAutoplay: false
                )

                batchItems[index].status = .completed
                history.recordGenerationHistory(
                    audioData: output.audioData,
                    format: format,
                    text: preparedText,
                    voice: voice,
                    provider: providerType,
                    duration: output.duration,
                    transcript: output.transcript
                )
                coordinator.currentTranscript = output.transcript
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
        playback.stop()

        if !Task.isCancelled {
            sendBatchCompletionNotification(successCount: successCount, failureCount: failureCount)
        }
    }

    /// Generates speech for a single segment, optionally loading audio into the player.
    func performGeneration(text: String,
                           providerType: TTSProviderType,
                           voice: Voice,
                           format: AudioSettings.AudioFormat,
                           shouldAutoplay: Bool,
                           loadIntoPlayer: Bool = true) async throws -> GenerationOutput {
        guard let coordinator else {
            throw TTSError.apiError("Speech coordinator unavailable.")
        }

        let provider = coordinator.getProvider(for: providerType)

        guard provider.hasValidAPIKey() else {
            throw TTSError.invalidAPIKey
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw TTSError.apiError("Segment text is empty.")
        }

        let limit = coordinator.characterLimit(for: providerType)
        if trimmed.count > limit {
            throw TTSError.textTooLong(limit)
        }

        var settings = AudioSettings(
            speed: playback.playbackSpeed,
            volume: playback.volume,
            format: format,
            sampleRate: coordinator.sampleRate(for: format),
            styleValues: coordinator.styleValues(for: providerType)
        )

        if providerType == .elevenLabs {
            settings.providerOptions[ElevenLabsProviderOptionKey.modelID] = coordinator.elevenLabsModel.rawValue
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
            try await playback.audioPlayer.loadAudio(from: data)
            playback.applyPlaybackSettings()
            coordinator.audioData = data
            coordinator.currentAudioFormat = format
            duration = playback.audioPlayer.duration
        } else {
            let tempPlayer = try AVAudioPlayer(data: data)
            duration = tempPlayer.duration
        }

        let transcript = TranscriptBuilder.makeTranscript(for: trimmed, duration: duration)
        if loadIntoPlayer {
            coordinator.currentTranscript = transcript
            generationProgress = 1.0

            if shouldAutoplay {
                await playback.play()
            } else {
                playback.pause()
            }
        }

        return GenerationOutput(audioData: data, transcript: transcript, duration: duration)
    }

    /// Generates speech for long-form text by chunking and merging multiple segments.
    func generateLongFormSpeech(text: String,
                                providerType: TTSProviderType,
                                voice: Voice,
                                format: AudioSettings.AudioFormat,
                                shouldAutoplay: Bool) async {
        guard let coordinator else { return }

        let cleanedText = coordinator.stripBatchDelimiters(from: text)
        let limit = coordinator.characterLimit(for: providerType)
        let segments = TextChunker.chunk(text: cleanedText, limit: limit)

        guard segments.count > 1 else {
            coordinator.errorMessage = "Unable to automatically split the text for generation. Please shorten it and try again."
            isGenerating = false
            generationProgress = 0
            return
        }

        isGenerating = true
        coordinator.errorMessage = nil
        generationProgress = 0

        var outputs: [GenerationOutput] = []
        var preparedSegments: [String] = []

        for (index, segment) in segments.enumerated() {
            let prepared = coordinator.applyPronunciationRules(to: segment, provider: providerType)
            preparedSegments.append(prepared)

            do {
                let output = try await performGeneration(
                    text: prepared,
                    providerType: providerType,
                    voice: voice,
                    format: format,
                    shouldAutoplay: false,
                    loadIntoPlayer: false
                )
                outputs.append(output)
            } catch let error as TTSError {
                coordinator.errorMessage = error.localizedDescription
                isGenerating = false
                generationProgress = 0
                return
            } catch {
                coordinator.errorMessage = "Failed to generate segment \(index + 1): \(error.localizedDescription)"
                isGenerating = false
                generationProgress = 0
                return
            }

            generationProgress = Double(index + 1) / Double(segments.count)
        }

        do {
            let mergeResult = try await mergeAudioSegments(outputs: outputs, targetFormat: format)
            try await playback.audioPlayer.loadAudio(from: mergeResult.data)

            coordinator.audioData = mergeResult.data
            coordinator.currentAudioFormat = mergeResult.format
            playback.seek(to: 0)

            let aggregatedText = preparedSegments.joined(separator: "\n\n")
            let transcript = TranscriptBuilder.makeTranscript(for: aggregatedText, duration: playback.audioPlayer.duration)
            coordinator.currentTranscript = transcript

            if shouldAutoplay {
                await playback.play()
            } else {
                playback.pause()
            }

            history.recordGenerationHistory(
                audioData: mergeResult.data,
                format: mergeResult.format,
                text: aggregatedText,
                voice: voice,
                provider: providerType,
                duration: playback.audioPlayer.duration,
                transcript: transcript
            )

            generationProgress = 1.0
        } catch {
            coordinator.errorMessage = "Failed to combine audio segments: \(error.localizedDescription)"
        }

        generationProgress = 0
        isGenerating = false
    }
}
