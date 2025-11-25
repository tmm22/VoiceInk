import SwiftUI
import SwiftData

@MainActor
final class TranscriptionHistoryViewModel: ObservableObject {
    @Published private(set) var displayedTranscriptions: [Transcription] = []
    @Published private(set) var isLoading = false
    @Published private(set) var hasMoreContent = true

    private let pageSize: Int
    private var lastTimestamp: Date?
    private let modelContext: ModelContext

    init(modelContext: ModelContext, pageSize: Int = 20) {
        self.modelContext = modelContext
        self.pageSize = pageSize
    }

    func reset() {
        displayedTranscriptions = []
        lastTimestamp = nil
        hasMoreContent = true
        isLoading = false
    }

    func loadInitialContent(searchText: String) async {
        await loadContent(after: nil, searchText: searchText, shouldReset: true)
    }

    func loadMoreContent(searchText: String) async {
        guard hasMoreContent else { return }
        await loadContent(after: lastTimestamp, searchText: searchText, shouldReset: false)
    }

    /// Soft-deletes a transcription (moves to trash)
    func deleteTranscription(_ transcription: Transcription) async {
        transcription.moveToTrash()
        displayedTranscriptions.removeAll { $0.id == transcription.id }

        do {
            try modelContext.save()
        } catch {
            AppLogger.storage.error("Failed to save context after soft deletion: \(error.localizedDescription)")
        }
    }

    /// Soft-deletes multiple transcriptions (moves to trash)
    func deleteTranscriptions(_ transcriptions: [Transcription]) async {
        transcriptions.forEach { $0.moveToTrash() }
        displayedTranscriptions.removeAll { transcription in
            transcriptions.contains(where: { $0.id == transcription.id })
        }

        do {
            try modelContext.save()
        } catch {
            AppLogger.storage.error("Failed to save context after bulk soft deletion: \(error.localizedDescription)")
        }
    }
    
    /// Permanently deletes a transcription (removes from database and audio file)
    func permanentlyDeleteTranscription(_ transcription: Transcription) async {
        removeAssociatedAudio(for: transcription)
        modelContext.delete(transcription)
        displayedTranscriptions.removeAll { $0.id == transcription.id }

        do {
            try modelContext.save()
        } catch {
            AppLogger.storage.error("Failed to save context after permanent deletion: \(error.localizedDescription)")
        }
    }
    
    /// Permanently deletes multiple transcriptions
    func permanentlyDeleteTranscriptions(_ transcriptions: [Transcription]) async {
        transcriptions.forEach(removeAssociatedAudio)
        transcriptions.forEach(modelContext.delete)
        displayedTranscriptions.removeAll { transcription in
            transcriptions.contains(where: { $0.id == transcription.id })
        }

        do {
            try modelContext.save()
        } catch {
            AppLogger.storage.error("Failed to save context after bulk permanent deletion: \(error.localizedDescription)")
        }
    }
    
    /// Restores a soft-deleted transcription
    func restoreTranscription(_ transcription: Transcription) async {
        transcription.restore()
        displayedTranscriptions.removeAll { $0.id == transcription.id }

        do {
            try modelContext.save()
        } catch {
            AppLogger.storage.error("Failed to save context after restoration: \(error.localizedDescription)")
        }
    }
    
    /// Restores multiple soft-deleted transcriptions
    func restoreTranscriptions(_ transcriptions: [Transcription]) async {
        transcriptions.forEach { $0.restore() }
        displayedTranscriptions.removeAll { transcription in
            transcriptions.contains(where: { $0.id == transcription.id })
        }

        do {
            try modelContext.save()
        } catch {
            AppLogger.storage.error("Failed to save context after bulk restoration: \(error.localizedDescription)")
        }
    }

    private func loadContent(after timestamp: Date?, searchText: String, shouldReset: Bool) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let descriptor = descriptor(after: timestamp, searchText: searchText)
            let items = try modelContext.fetch(descriptor)

            if shouldReset {
                displayedTranscriptions = items
            } else {
                displayedTranscriptions.append(contentsOf: items)
            }

            lastTimestamp = items.last?.timestamp
            hasMoreContent = items.count == pageSize
        } catch {
            AppLogger.storage.error("Failed to load transcription history: \(error.localizedDescription)")
        }
    }

    private func descriptor(after timestamp: Date?, searchText: String) -> FetchDescriptor<Transcription> {
        var descriptor = FetchDescriptor<Transcription>(
            sortBy: [SortDescriptor(\Transcription.timestamp, order: .reverse)]
        )

        if let timestamp {
            if searchText.isEmpty {
                descriptor.predicate = #Predicate<Transcription> { transcription in
                    transcription.timestamp < timestamp && transcription.isDeleted == false
                }
            } else {
                descriptor.predicate = #Predicate<Transcription> { transcription in
                    (transcription.text.localizedStandardContains(searchText) ||
                     (transcription.enhancedText?.localizedStandardContains(searchText) ?? false)) &&
                    transcription.timestamp < timestamp && transcription.isDeleted == false
                }
            }
        } else if !searchText.isEmpty {
            descriptor.predicate = #Predicate<Transcription> { transcription in
                (transcription.text.localizedStandardContains(searchText) ||
                (transcription.enhancedText?.localizedStandardContains(searchText) ?? false)) &&
                transcription.isDeleted == false
            }
        } else {
            descriptor.predicate = #Predicate<Transcription> { transcription in
                transcription.isDeleted == false
            }
        }

        descriptor.fetchLimit = pageSize
        return descriptor
    }

    private func removeAssociatedAudio(for transcription: Transcription) {
        guard let urlString = transcription.audioFileURL,
              let url = URL(string: urlString) else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
