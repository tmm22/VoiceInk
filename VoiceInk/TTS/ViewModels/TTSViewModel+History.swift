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
                if let audioFileURL = item.audioFileURL, FileManager.default.fileExists(atPath: audioFileURL.path) {
                    if FileManager.default.fileExists(atPath: destinationURL.path) {
                        try FileManager.default.removeItem(at: destinationURL)
                    }
                    try FileManager.default.copyItem(at: audioFileURL, to: destinationURL)
                } else if let audioData = item.audioData {
                    try audioData.write(to: destinationURL, options: .atomic)
                } else {
                    throw TTSError.apiError("Missing audio data for export.")
                }
            } catch {
                errorMessage = "Failed to save audio: \(error.localizedDescription)"
            }
        }
    }

    func removeHistoryItem(_ item: GenerationHistoryItem) {
        deleteHistoryAudio(for: item)
        recentGenerations.removeAll { $0.id == item.id }
    }

    func clearHistory() {
        recentGenerations.forEach { deleteHistoryAudio(for: $0) }
        recentGenerations.removeAll()
        clearHistoryCacheDirectory()
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

        let duplicates = recentGenerations.filter {
            $0.matches(provider: provider, voiceID: voice.id, text: trimmedText)
        }
        duplicates.forEach { deleteHistoryAudio(for: $0) }
        recentGenerations.removeAll { $0.matches(provider: provider, voiceID: voice.id, text: trimmedText) }

        let storedAudio = storeHistoryAudio(audioData, format: format)

        let item = GenerationHistoryItem(
            provider: provider,
            voice: .init(id: voice.id, name: voice.name),
            format: format,
            text: trimmedText,
            audioData: storedAudio.data,
            audioFileURL: storedAudio.url,
            audioSizeBytes: storedAudio.sizeBytes,
            duration: duration,
            transcript: transcript
        )

        recentGenerations.insert(item, at: 0)

        if recentGenerations.count > maxHistoryItems {
            let overflow = recentGenerations.suffix(recentGenerations.count - maxHistoryItems)
            overflow.forEach { deleteHistoryAudio(for: $0) }
            recentGenerations.removeLast(recentGenerations.count - maxHistoryItems)
        }

        enforceHistoryDiskLimit()
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
            if let audioFileURL = item.audioFileURL, FileManager.default.fileExists(atPath: audioFileURL.path) {
                try await audioPlayer.loadAudio(from: audioFileURL)
                audioData = try await AudioFileLoader.loadData(from: audioFileURL)
            } else if let audioData = item.audioData {
                try await audioPlayer.loadAudio(from: audioData)
                self.audioData = audioData
            } else {
                throw TTSError.apiError("Missing audio data.")
            }
            applyPlaybackSettings()
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

extension TTSViewModel {
    func setupHistoryCache() {
        do {
            try FileManager.default.createDirectory(at: historyCacheDirectory, withIntermediateDirectories: true)
        } catch {
            AppLogger.storage.error("Failed to create history cache directory: \(error.localizedDescription)")
        }

        clearHistoryCacheDirectory()
    }

    func clearHistoryCacheDirectory() {
        Self.clearHistoryCacheDirectory(at: historyCacheDirectory)
    }

    private func storeHistoryAudio(_ audioData: Data, format: AudioSettings.AudioFormat) -> (data: Data?, url: URL?, sizeBytes: Int) {
        let sizeBytes = audioData.count
        guard sizeBytes > historyMemoryLimitBytes else {
            return (audioData, nil, sizeBytes)
        }

        let filename = "history-\(UUID().uuidString).\(format.fileExtension)"
        let fileURL = historyCacheDirectory.appendingPathComponent(filename)

        do {
            try audioData.write(to: fileURL, options: .atomic)
            return (nil, fileURL, sizeBytes)
        } catch {
            AppLogger.storage.error("Failed to cache history audio: \(error.localizedDescription)")
            return (audioData, nil, sizeBytes)
        }
    }

    private func deleteHistoryAudio(for item: GenerationHistoryItem) {
        guard let url = item.audioFileURL else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private func enforceHistoryDiskLimit() {
        var diskBytes = recentGenerations.reduce(0) { result, item in
            guard item.audioFileURL != nil else { return result }
            return result + item.audioSizeBytes
        }

        while diskBytes > historyDiskLimitBytes, let last = recentGenerations.last {
            deleteHistoryAudio(for: last)
            recentGenerations.removeLast()
            if last.audioFileURL != nil {
                diskBytes = recentGenerations.reduce(0) { result, item in
                    guard item.audioFileURL != nil else { return result }
                    return result + item.audioSizeBytes
                }
            } else {
                diskBytes = recentGenerations.reduce(0) { result, item in
                    guard item.audioFileURL != nil else { return result }
                    return result + item.audioSizeBytes
                }
            }
        }
    }

    nonisolated static func clearHistoryCacheDirectory(at url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let contents = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
            for fileURL in contents {
                try? FileManager.default.removeItem(at: fileURL)
            }
        } catch {
            AppLogger.storage.error("Failed to clear history cache directory: \(error.localizedDescription)")
        }
    }
}
