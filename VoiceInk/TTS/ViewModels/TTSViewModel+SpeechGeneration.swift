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

    func generateLongFormSpeech(text: String,
                                providerType: TTSProviderType,
                                voice: Voice,
                                format: AudioSettings.AudioFormat,
                                shouldAutoplay: Bool) async {
        let cleanedText = stripBatchDelimiters(from: text)
        let limit = characterLimit(for: providerType)
        let segments = TextChunker.chunk(text: cleanedText, limit: limit)

        guard segments.count > 1 else {
            errorMessage = "Unable to automatically split the text for generation. Please shorten it and try again."
            isGenerating = false
            generationProgress = 0
            return
        }

        isGenerating = true
        errorMessage = nil
        generationProgress = 0

        var outputs: [GenerationOutput] = []
        var preparedSegments: [String] = []

        for (index, segment) in segments.enumerated() {
            let prepared = applyPronunciationRules(to: segment, provider: providerType)
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
                errorMessage = error.localizedDescription
                isGenerating = false
                generationProgress = 0
                return
            } catch {
                errorMessage = "Failed to generate segment \(index + 1): \(error.localizedDescription)"
                isGenerating = false
                generationProgress = 0
                return
            }

            generationProgress = Double(index + 1) / Double(segments.count)
        }

        do {
            let mergeResult = try await mergeAudioSegments(outputs: outputs, targetFormat: format)
            try await audioPlayer.loadAudio(from: mergeResult.data)

            audioData = mergeResult.data
            currentAudioFormat = mergeResult.format
            currentTime = 0
            duration = audioPlayer.duration

            let aggregatedText = preparedSegments.joined(separator: "\n\n")
            let transcript = TranscriptBuilder.makeTranscript(for: aggregatedText, duration: audioPlayer.duration)
            currentTranscript = transcript

            if shouldAutoplay {
                await play()
            } else {
                isPlaying = false
            }

            recordGenerationHistory(
                audioData: mergeResult.data,
                format: mergeResult.format,
                text: aggregatedText,
                voice: voice,
                provider: providerType,
                duration: audioPlayer.duration,
                transcript: transcript
            )

            generationProgress = 1.0
        } catch {
            errorMessage = "Failed to combine audio segments: \(error.localizedDescription)"
        }

        generationProgress = 0
        isGenerating = false
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

    func mergeAudioSegments(outputs: [GenerationOutput], targetFormat: AudioSettings.AudioFormat) async throws -> (data: Data, format: AudioSettings.AudioFormat) {
        guard !outputs.isEmpty else {
            throw TTSError.apiError("No audio segments to merge.")
        }

        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        var assets: [AVURLAsset] = []
        for (index, output) in outputs.enumerated() {
            let segmentURL = tempDirectory.appendingPathComponent("segment_\(index).\(targetFormat.fileExtension)")
            try output.audioData.write(to: segmentURL)
            let asset = AVURLAsset(url: segmentURL)
            assets.append(asset)
        }

        let composition = AVMutableComposition()
        guard let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw TTSError.apiError("Unable to prepare audio composition.")
        }

        var cursor = CMTime.zero
        for asset in assets {
            let assetTracks = try await asset.loadTracks(withMediaType: .audio)
            guard let assetTrack = assetTracks.first else { continue }
            let duration = try await asset.load(.duration)
            let timeRange = CMTimeRange(start: .zero, duration: duration)
            try track.insertTimeRange(timeRange, of: assetTrack, at: cursor)
            cursor = cursor + duration
        }

        let exportFormat: AVFileType
        let exportPreset: String
        let finalFormat: AudioSettings.AudioFormat

        if targetFormat == .wav {
            exportFormat = .wav
            exportPreset = AVAssetExportPresetPassthrough
            finalFormat = .wav
        } else {
            exportFormat = .m4a
            exportPreset = AVAssetExportPresetAppleM4A
            finalFormat = .aac
        }

        let outputURL = tempDirectory.appendingPathComponent("merged.\(finalFormat.fileExtension)")
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        guard let exporter = AVAssetExportSession(asset: composition, presetName: exportPreset) else {
            throw TTSError.apiError("Unable to export combined audio.")
        }

        do {
            try await exporter.export(to: outputURL, as: exportFormat)
        } catch let cancelError as CancellationError {
            throw cancelError
        } catch {
            throw TTSError.apiError(error.localizedDescription)
        }

        let data = try Data(contentsOf: outputURL)
        return (data, finalFormat)
    }
}