import SwiftUI
import AVFoundation
import AppKit

@MainActor
protocol TTSHistoryCoordinating: AnyObject {
    var selectedProvider: TTSProviderType { get set }
    var selectedVoice: Voice? { get set }
    var selectedFormat: AudioSettings.AudioFormat { get set }
    var availableVoices: [Voice] { get }
    var audioData: Data? { get set }
    var currentAudioFormat: AudioSettings.AudioFormat { get set }
    var currentTranscript: TranscriptBundle? { get set }
    var errorMessage: String? { get set }

    func updateAvailableVoices()
    func stopPreview()
}

@MainActor
final class TTSHistoryViewModel: ObservableObject {
    @Published var recentGenerations: [GenerationHistoryItem] = []

    weak var coordinator: (any TTSHistoryCoordinating)?

    let playback: TTSPlaybackViewModel

    private let maxHistoryItems = 5
    private let historyMemoryLimitBytes = 2 * 1024 * 1024
    private let historyDiskLimitBytes = 50 * 1024 * 1024
    
    /// Cached total disk usage in bytes for history items stored on disk.
    /// Updated incrementally when items are added/removed to avoid recalculating on every operation.
    private var cachedDiskBytes: Int = 0
    private let historyCacheDirectory: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("VoiceInk/RecentGenerations", isDirectory: true)
    }()

    init(playback: TTSPlaybackViewModel) {
        self.playback = playback
    }

    deinit {
        Self.clearHistoryCacheDirectory(at: historyCacheDirectory)
    }

    // MARK: - Public API
    func playHistoryItem(_ item: GenerationHistoryItem) async {
        do {
            try await loadHistoryItem(item, shouldAutoplay: true)
        } catch {
            coordinator?.errorMessage = "Failed to play saved audio: \(error.localizedDescription)"
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
                coordinator?.errorMessage = "Failed to save audio: \(error.localizedDescription)"
            }
        }
    }

    func removeHistoryItem(_ item: GenerationHistoryItem) {
        // Update cached disk bytes before deletion
        if item.audioFileURL != nil {
            cachedDiskBytes = max(0, cachedDiskBytes - item.audioSizeBytes)
        }
        deleteHistoryAudio(for: item)
        recentGenerations.removeAll { $0.id == item.id }
    }

    func clearHistory() {
        recentGenerations.forEach { deleteHistoryAudio(for: $0) }
        recentGenerations.removeAll()
        cachedDiskBytes = 0
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

        // Find and remove duplicates, updating cached disk bytes
        let duplicates = recentGenerations.filter {
            $0.matches(provider: provider, voiceID: voice.id, text: trimmedText)
        }
        for duplicate in duplicates {
            if duplicate.audioFileURL != nil {
                cachedDiskBytes = max(0, cachedDiskBytes - duplicate.audioSizeBytes)
            }
            deleteHistoryAudio(for: duplicate)
        }
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
        
        // Update cached disk bytes for new item stored on disk
        if storedAudio.url != nil {
            cachedDiskBytes += storedAudio.sizeBytes
        }

        // Handle overflow items, updating cached disk bytes
        if recentGenerations.count > maxHistoryItems {
            let overflow = recentGenerations.suffix(recentGenerations.count - maxHistoryItems)
            for overflowItem in overflow {
                if overflowItem.audioFileURL != nil {
                    cachedDiskBytes = max(0, cachedDiskBytes - overflowItem.audioSizeBytes)
                }
                deleteHistoryAudio(for: overflowItem)
            }
            recentGenerations.removeLast(recentGenerations.count - maxHistoryItems)
        }

        enforceHistoryDiskLimit()
    }

    func loadHistoryItem(_ item: GenerationHistoryItem, shouldAutoplay: Bool) async throws {
        guard let coordinator else {
            throw TTSError.apiError("History coordinator unavailable.")
        }

        coordinator.stopPreview()

        let previousProvider = coordinator.selectedProvider
        let previousVoice = coordinator.selectedVoice
        let previousFormat = coordinator.selectedFormat
        let previousAudioData = coordinator.audioData

        coordinator.selectedProvider = item.provider
        coordinator.updateAvailableVoices()

        if let matchedVoice = coordinator.availableVoices.first(where: { $0.id == item.voice.id }) {
            coordinator.selectedVoice = matchedVoice
        } else {
            coordinator.selectedVoice = nil
        }

        coordinator.selectedFormat = item.format

        do {
            if let audioFileURL = item.audioFileURL, FileManager.default.fileExists(atPath: audioFileURL.path) {
                try await playback.audioPlayer.loadAudio(from: audioFileURL)
                coordinator.audioData = try await AudioFileLoader.loadData(from: audioFileURL)
            } else if let audioData = item.audioData {
                try await playback.audioPlayer.loadAudio(from: audioData)
                coordinator.audioData = audioData
            } else {
                throw TTSError.apiError("Missing audio data.")
            }
            playback.applyPlaybackSettings()
            coordinator.currentAudioFormat = item.format
            coordinator.currentTranscript = item.transcript

            if shouldAutoplay {
                await playback.play()
            } else {
                playback.pause()
            }
        } catch {
            coordinator.selectedProvider = previousProvider
            coordinator.selectedVoice = previousVoice
            coordinator.selectedFormat = previousFormat
            coordinator.audioData = previousAudioData
            throw error
        }
    }

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

    // MARK: - Private Helpers
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
        // Best-effort cleanup; cache files may already be missing.
        try? FileManager.default.removeItem(at: url)
    }

    /// Enforces the disk limit by removing oldest items until under the limit.
    /// Uses the cached disk bytes value for O(1) lookup instead of recalculating.
    private func enforceHistoryDiskLimit() {
        while cachedDiskBytes > historyDiskLimitBytes, let last = recentGenerations.last {
            if last.audioFileURL != nil {
                cachedDiskBytes = max(0, cachedDiskBytes - last.audioSizeBytes)
            }
            deleteHistoryAudio(for: last)
            recentGenerations.removeLast()
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
