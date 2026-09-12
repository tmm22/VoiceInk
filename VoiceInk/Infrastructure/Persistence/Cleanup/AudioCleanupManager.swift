import Foundation
import SwiftData

/// Manages audio cleanup while keeping SwiftData on the main actor and file I/O off it.
@MainActor
final class AudioCleanupManager {
    static let shared = AudioCleanupManager()

    private let cleanupWorker = AudioFileCleanupWorker()
    private let cleanupCheckInterval: TimeInterval = 86_400
    private let logger = AppLogger.storage
    private var cleanupTimer: Timer?
    private weak var scheduledModelContext: ModelContext?

    private var recordingsDirectory: URL {
        AppBrand.applicationSupportDirectory()
            .appendingPathComponent("Recordings")
    }

    private init() {}

    deinit {
        cleanupTimer?.invalidate()
    }

    func startAutomaticCleanup(modelContext: ModelContext) {
        scheduledModelContext = modelContext
        cleanupTimer?.invalidate()
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: cleanupCheckInterval, repeats: true) {
            [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let modelContext = self.scheduledModelContext else { return }
                await self.runAutomaticCleanupIfNeeded(modelContext: modelContext)
            }
        }
    }

    func runAutomaticCleanupIfNeeded(modelContext: ModelContext) async {
        guard UserDefaults.standard.bool(forKey: CleanupSettingsKeys.isAudioCleanupEnabled),
            !UserDefaults.standard.bool(forKey: CleanupSettingsKeys.isTranscriptionCleanupEnabled),
            shouldRunAutomaticCleanup()
        else {
            return
        }

        await performCleanup(modelContext: modelContext)
        UserDefaults.standard.set(Date(), forKey: CleanupSettingsKeys.lastAutomaticAudioCleanupDate)
    }

    func stopAutomaticCleanup() {
        cleanupTimer?.invalidate()
        cleanupTimer = nil
    }

    func getCleanupInfo(modelContext: ModelContext) async -> (
        fileCount: Int, totalSize: Int64, transcriptions: [Transcription]
    ) {
        guard let cutoffDate = cutoffDate() else { return (0, 0, []) }

        do {
            let descriptor = FetchDescriptor<Transcription>(
                predicate: #Predicate<Transcription> { transcription in
                    transcription.timestamp < cutoffDate && transcription.audioFileURL != nil
                }
            )
            let transcriptions = try modelContext.fetch(descriptor)
            let candidates = audioCandidates(from: transcriptions)
            let inspections = await cleanupWorker.inspect(candidates)
            let presentPairs: [(UUID, Int64)] = inspections.compactMap { result in
                guard case .present(let size) = result.inspection else { return nil }
                return (result.candidate.id, size)
            }
            let presentByID = Dictionary(uniqueKeysWithValues: presentPairs)
            let eligible = transcriptions.filter { presentByID[$0.id] != nil }
            let totalSize = presentByID.values.reduce(Int64(0), +)
            return (eligible.count, totalSize, eligible)
        } catch {
            logger.error("Failed to inspect cleanup candidates: \(AppLogger.errorMetadata(error), privacy: .public)")
            return (0, 0, [])
        }
    }

    func runManualCleanup(modelContext: ModelContext) async {
        await performCleanup(modelContext: modelContext)
    }

    func runCleanupForTranscriptions(
        modelContext: ModelContext,
        transcriptions: [Transcription]
    ) async -> (deletedCount: Int, errorCount: Int) {
        let results = await cleanupWorker.delete(
            audioCandidates(from: transcriptions),
            allowedRoot: recordingsDirectory
        )
        return applyDeletionResults(results, to: transcriptions, modelContext: modelContext)
    }

    func formatFileSize(_ size: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }

    private func performCleanup(modelContext: ModelContext) async {
        guard UserDefaults.standard.bool(forKey: CleanupSettingsKeys.isAudioCleanupEnabled),
            let cutoffDate = cutoffDate()
        else {
            return
        }

        do {
            let descriptor = FetchDescriptor<Transcription>(
                predicate: #Predicate<Transcription> { transcription in
                    transcription.timestamp < cutoffDate && transcription.audioFileURL != nil
                }
            )
            let transcriptions = try modelContext.fetch(descriptor)
            let results = await cleanupWorker.delete(
                audioCandidates(from: transcriptions),
                allowedRoot: recordingsDirectory
            )
            _ = applyDeletionResults(results, to: transcriptions, modelContext: modelContext)
        } catch {
            logger.error("Automatic audio cleanup failed: \(AppLogger.errorMetadata(error), privacy: .public)")
        }
    }

    private func applyDeletionResults(
        _ results: [AudioFileDeletionResult],
        to transcriptions: [Transcription],
        modelContext: ModelContext
    ) -> (deletedCount: Int, errorCount: Int) {
        let transcriptionByID = Dictionary(uniqueKeysWithValues: transcriptions.map { ($0.id, $0) })
        var deletedCount = 0
        var errorCount = 0

        for result in results {
            switch result.deletion {
            case .deleted, .missing:
                transcriptionByID[result.candidate.id]?.audioFileURL = nil
                deletedCount += 1
            case .failed:
                errorCount += 1
            }
        }

        guard deletedCount > 0 else { return (deletedCount, errorCount) }
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            logger.error("Failed to save audio cleanup: \(AppLogger.errorMetadata(error), privacy: .public)")
            return (0, errorCount + deletedCount)
        }
        return (deletedCount, errorCount)
    }

    private func audioCandidates(from transcriptions: [Transcription]) -> [AudioFileCandidate] {
        transcriptions.compactMap { transcription in
            guard let urlString = transcription.audioFileURL,
                let url = URL(string: urlString)
            else {
                return nil
            }
            return AudioFileCandidate(id: transcription.id, url: url)
        }
    }

    private func cutoffDate() -> Date? {
        let retentionDays = UserDefaults.standard.integer(forKey: CleanupSettingsKeys.audioRetentionPeriod)
        return Calendar.current.date(byAdding: .day, value: -retentionDays, to: Date())
    }

    private func shouldRunAutomaticCleanup() -> Bool {
        guard let lastCleanupDate = UserDefaults.standard.object(
            forKey: CleanupSettingsKeys.lastAutomaticAudioCleanupDate
        ) as? Date else {
            return true
        }
        return Date().timeIntervalSince(lastCleanupDate) >= cleanupCheckInterval
    }
}
