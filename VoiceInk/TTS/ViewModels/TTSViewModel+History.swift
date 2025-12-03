import SwiftUI
import AVFoundation
import AppKit

// MARK: - Generation History Management
extension TTSViewModel {
    func playHistoryItem(_ item: GenerationHistoryItem) async {
        do {
            try await loadHistoryItem(item, shouldAutoplay: true)
        } catch {
            errorMessage = "Failed to play saved audio: \(error.localizedDescription)"
        }
    }

    func exportHistoryItem(_ item: GenerationHistoryItem) {
        let savePanel = NSSavePanel()
        if let contentType = item.format.contentType {
            savePanel.allowedContentTypes = [contentType]
            savePanel.allowsOtherFileTypes = false
        }
        savePanel.canCreateDirectories = true
        savePanel.nameFieldStringValue = "speech.\(item.format.fileExtension)"
        savePanel.title = "Export Saved Audio"
        savePanel.message = "Choose where to save the audio file"

        if savePanel.runModal() == .OK, let url = savePanel.url {
            var destinationURL = url
            let expectedExtension = item.format.fileExtension

            if destinationURL.pathExtension.lowercased() != expectedExtension {
                destinationURL = url.deletingPathExtension().appendingPathExtension(expectedExtension)
            }

            do {
                try item.audioData.write(to: destinationURL, options: .atomic)
            } catch {
                errorMessage = "Failed to save audio: \(error.localizedDescription)"
            }
        }
    }

    func removeHistoryItem(_ item: GenerationHistoryItem) {
        recentGenerations.removeAll { $0.id == item.id }
    }

    func clearHistory() {
        recentGenerations.removeAll()
    }

    func recordGenerationHistory(audioData: Data,
                                 format: AudioSettings.AudioFormat,
                                 text: String,
                                 voice: Voice,
                                 provider: TTSProviderType,
                                 duration: TimeInterval,
                                 transcript: TranscriptBundle?) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }

        recentGenerations.removeAll {
            $0.matches(provider: provider, voiceID: voice.id, text: trimmedText)
        }

        let item = GenerationHistoryItem(
            provider: provider,
            voice: .init(id: voice.id, name: voice.name),
            format: format,
            text: trimmedText,
            audioData: audioData,
            duration: duration,
            transcript: transcript
        )

        recentGenerations.insert(item, at: 0)

        if recentGenerations.count > maxHistoryItems {
            recentGenerations.removeLast(recentGenerations.count - maxHistoryItems)
        }
    }

    func loadHistoryItem(_ item: GenerationHistoryItem, shouldAutoplay: Bool) async throws {
        stopPreview()

        let previousProvider = selectedProvider
        let previousVoice = selectedVoice
        let previousFormat = selectedFormat
        let previousAudioData = audioData

        selectedProvider = item.provider
        updateAvailableVoices()

        if let matchedVoice = availableVoices.first(where: { $0.id == item.voice.id }) {
            selectedVoice = matchedVoice
        } else {
            selectedVoice = nil
        }

        selectedFormat = item.format

        do {
            try await audioPlayer.loadAudio(from: item.audioData)
            applyPlaybackSettings()
            audioData = item.audioData
            currentAudioFormat = item.format
            currentTranscript = item.transcript

            if shouldAutoplay {
                await play()
            } else {
                isPlaying = false
            }
        } catch {
            selectedProvider = previousProvider
            selectedVoice = previousVoice
            selectedFormat = previousFormat
            audioData = previousAudioData
            throw error
        }
    }
}