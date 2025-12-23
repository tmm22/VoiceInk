import AppKit
import UniformTypeIdentifiers

extension TTSImportExportViewModel {
    func exportAudio() {
        guard let coordinator else { return }
        guard coordinator.audioData != nil else { return }

        guard let panelChoice = configuredSavePanel(
            defaultFormat: coordinator.currentAudioFormat,
            provider: settings.selectedProvider
        ) else { return }

        let (savePanel, orderedFormats) = panelChoice

        if savePanel.runModal() == .OK, let url = savePanel.url {
            let chosenExtension = url.pathExtension.isEmpty ? coordinator.currentAudioFormat.fileExtension : url.pathExtension
            let chosenFormat = AudioSettings.AudioFormat(fileExtension: chosenExtension) ?? orderedFormats.first ?? coordinator.currentAudioFormat

            Task { [weak self] in
                await self?.performExport(to: url, format: chosenFormat)
            }
        }
    }

    func exportTranscript(format: TranscriptFormat) {
        guard let coordinator else { return }
        guard let transcript = coordinator.currentTranscript else { return }
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
        let providerFormats = settings.supportedFormats(for: provider)
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
                coordinator?.errorMessage = "Failed to save transcript: \(error.localizedDescription)"
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
            coordinator?.errorMessage = error.localizedDescription
        } catch {
            coordinator?.errorMessage = "Failed to save audio: \(error.localizedDescription)"
        }
    }

    func dataForExport(using format: AudioSettings.AudioFormat) async throws -> Data {
        guard let coordinator else {
            throw TTSError.apiError("Export coordinator unavailable.")
        }

        if format == coordinator.currentAudioFormat, let data = coordinator.audioData {
            return data
        }

        guard !coordinator.inputText.isEmpty else {
            throw TTSError.apiError("No text available to regenerate audio for export.")
        }

        let provider = settings.getCurrentProvider()
        let providerType = settings.selectedProvider
        guard provider.hasValidAPIKey() else {
            throw TTSError.invalidAPIKey
        }

        let voice = settings.selectedVoice ?? provider.defaultVoice
        var settingsPayload = AudioSettings(
            speed: playback.playbackSpeed,
            volume: playback.volume,
            format: format,
            sampleRate: settings.sampleRate(for: format),
            styleValues: settings.styleValues(for: settings.selectedProvider)
        )

        if settings.selectedProvider == .elevenLabs {
            settingsPayload.providerOptions[ElevenLabsProviderOptionKey.modelID] = settings.elevenLabsModel.rawValue
        }

        let previousAudioData = coordinator.audioData
        let previousFormat = coordinator.currentAudioFormat

        generation.isGenerating = true
        generation.generationProgress = 0.2
        coordinator.errorMessage = nil

        defer {
            generation.isGenerating = false
            generation.generationProgress = 0
        }

        do {
            let newData = try await generation.synthesizeSpeechWithFallback(
                text: coordinator.inputText,
                voice: voice,
                provider: provider,
                providerType: providerType,
                settings: settingsPayload
            )

            generation.generationProgress = 0.9
            try await playback.audioPlayer.loadAudio(from: newData)

            coordinator.audioData = newData
            coordinator.currentAudioFormat = format

            if settings.selectedFormat != format {
                settings.selectedFormat = format
            }

            return newData
        } catch let error as TTSError {
            coordinator.audioData = previousAudioData
            coordinator.currentAudioFormat = previousFormat

            if let previousAudioData {
                do {
                    try await playback.audioPlayer.loadAudio(from: previousAudioData)
                } catch {
                    AppLogger.audio.error("Failed to restore previous audio after regeneration error: \(error.localizedDescription)")
                    playback.stop()
                }
            } else {
                playback.stop()
            }

            throw error
        } catch {
            coordinator.audioData = previousAudioData
            coordinator.currentAudioFormat = previousFormat

            if let previousAudioData {
                do {
                    try await playback.audioPlayer.loadAudio(from: previousAudioData)
                } catch {
                    AppLogger.audio.error("Failed to restore previous audio after regeneration failure: \(error.localizedDescription)")
                    playback.stop()
                }
            } else {
                playback.stop()
            }

            throw TTSError.apiError("Failed to regenerate audio: \(error.localizedDescription)")
        }
    }
}
