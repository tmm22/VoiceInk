import SwiftUI
import AVFoundation
import AppKit
import UniformTypeIdentifiers

// MARK: - Export Methods
extension TTSViewModel {
    func exportAudio() {
        guard audioData != nil else { return }

        guard let panelChoice = configuredSavePanel(
            defaultFormat: currentAudioFormat,
            provider: selectedProvider
        ) else { return }

        let (savePanel, orderedFormats) = panelChoice

        if savePanel.runModal() == .OK, let url = savePanel.url {
            let chosenExtension = url.pathExtension.isEmpty ? currentAudioFormat.fileExtension : url.pathExtension
            let chosenFormat = AudioSettings.AudioFormat(fileExtension: chosenExtension) ?? orderedFormats.first ?? currentAudioFormat

            Task { [weak self] in
                await self?.performExport(to: url, format: chosenFormat)
            }
        }
    }

    func exportTranscript(format: TranscriptFormat) {
        guard let transcript = currentTranscript else { return }
        exportTranscriptBundle(transcript, format: format, suggestedName: "transcript")
    }

    func exportTranscript(for item: GenerationHistoryItem, format: TranscriptFormat) {
        guard let transcript = item.transcript else { return }
        let baseName = item.voice.name.replacingOccurrences(of: " ", with: "-").lowercased()
        exportTranscriptBundle(transcript, format: format, suggestedName: "transcript-\(baseName)")
    }

    func configuredSavePanel(defaultFormat: AudioSettings.AudioFormat,
                             provider: TTSProviderType) -> (NSSavePanel, [AudioSettings.AudioFormat])? {
        let savePanel = NSSavePanel()
        let providerFormats = supportedFormats(for: provider)
        let orderedFormats: [AudioSettings.AudioFormat]

        if let currentIndex = providerFormats.firstIndex(of: defaultFormat) {
            var formats = providerFormats
            formats.swapAt(0, currentIndex)
            orderedFormats = formats
        } else {
            orderedFormats = providerFormats
        }

        let contentTypes = orderedFormats.compactMap { $0.contentType }
        if !contentTypes.isEmpty {
            savePanel.allowedContentTypes = contentTypes
            savePanel.allowsOtherFileTypes = false
        }

        savePanel.canCreateDirectories = true
        savePanel.nameFieldStringValue = "speech.\(defaultFormat.fileExtension)"
        savePanel.title = "Export Audio"
        savePanel.message = "Choose where to save the audio file"

        return (savePanel, orderedFormats)
    }

    func exportTranscriptBundle(_ transcript: TranscriptBundle,
                                format: TranscriptFormat,
                                suggestedName: String) {
        let savePanel = NSSavePanel()
        if let contentType = format.contentType {
            savePanel.allowedContentTypes = [contentType]
            savePanel.allowsOtherFileTypes = false
        }
        savePanel.canCreateDirectories = true
        savePanel.nameFieldStringValue = "\(suggestedName).\(format.fileExtension)"
        savePanel.title = "Export Transcript"
        savePanel.message = "Choose where to save the transcript file"

        if savePanel.runModal() == .OK, let url = savePanel.url {
            var destination = url
            let expectedExtension = format.fileExtension
            if destination.pathExtension.lowercased() != expectedExtension {
                destination = url.deletingPathExtension().appendingPathExtension(expectedExtension)
            }

            let content: String = {
                switch format {
                case .srt:
                    return transcript.srt
                case .vtt:
                    return transcript.vtt
                }
            }()

            do {
                try Data(content.utf8).write(to: destination, options: .atomic)
            } catch {
                errorMessage = "Failed to save transcript: \(error.localizedDescription)"
            }
        }
    }

    func performExport(to url: URL, format: AudioSettings.AudioFormat) async {
        do {
            let data = try await dataForExport(using: format)
            var destinationURL = url
            let expectedExtension = format.fileExtension

            if destinationURL.pathExtension.lowercased() != expectedExtension {
                destinationURL = url.deletingPathExtension().appendingPathExtension(expectedExtension)
            }

            try data.write(to: destinationURL, options: .atomic)
        } catch let error as TTSError {
            errorMessage = error.localizedDescription
        } catch {
            errorMessage = "Failed to save audio: \(error.localizedDescription)"
        }
    }

    func dataForExport(using format: AudioSettings.AudioFormat) async throws -> Data {
        if format == currentAudioFormat, let data = audioData {
            return data
        }

        guard !inputText.isEmpty else {
            throw TTSError.apiError("No text available to regenerate audio for export.")
        }

        let provider = getCurrentProvider()
        let providerType = selectedProvider
        guard provider.hasValidAPIKey() else {
            throw TTSError.invalidAPIKey
        }

        let voice = selectedVoice ?? provider.defaultVoice
        var settings = AudioSettings(
            speed: playbackSpeed,
            volume: volume,
            format: format,
            sampleRate: sampleRate(for: format),
            styleValues: styleValues(for: selectedProvider)
        )

        if selectedProvider == .elevenLabs {
            settings.providerOptions[ElevenLabsProviderOptionKey.modelID] = elevenLabsModel.rawValue
        }

        let previousAudioData = audioData
        let previousFormat = currentAudioFormat

        isGenerating = true
        generationProgress = 0.2
        errorMessage = nil

        defer {
            isGenerating = false
            generationProgress = 0
        }

        do {
            let newData = try await synthesizeSpeechWithFallback(
                text: inputText,
                voice: voice,
                provider: provider,
                providerType: providerType,
                settings: settings
            )

            generationProgress = 0.9
            try await audioPlayer.loadAudio(from: newData)

            audioData = newData
            currentAudioFormat = format

            if selectedFormat != format {
                selectedFormat = format
            }

            return newData
        } catch let error as TTSError {
            audioData = previousAudioData
            currentAudioFormat = previousFormat

            if let previousAudioData {
                try? await audioPlayer.loadAudio(from: previousAudioData)
            } else {
                stop()
            }

            throw error
        } catch {
            audioData = previousAudioData
            currentAudioFormat = previousFormat

            if let previousAudioData {
                try? await audioPlayer.loadAudio(from: previousAudioData)
            } else {
                stop()
            }

            throw TTSError.apiError("Failed to regenerate audio: \(error.localizedDescription)")
        }
    }
}
