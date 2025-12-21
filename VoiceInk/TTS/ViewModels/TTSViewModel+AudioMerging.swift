import SwiftUI
import AVFoundation

// MARK: - Audio Merging & Long-Form Generation
extension TTSViewModel {
    /// Generates speech for text that exceeds the provider's character limit by splitting
    /// into chunks, generating each segment, and merging the results.
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

    /// Merges multiple audio segments into a single audio file.
    /// - Parameters:
    ///   - outputs: Array of generation outputs containing audio data
    ///   - targetFormat: The desired output format
    /// - Returns: Tuple containing merged audio data and the final format
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

        let data = try await AudioFileLoader.loadData(from: outputURL)
        return (data, finalFormat)
    }
}
