import Foundation
import OSLog
import SwiftData

@MainActor
final class TranscriptionAutoCleanupService {
    static let shared = TranscriptionAutoCleanupService()

    private let cleanupWorker = AudioFileCleanupWorker()
    private let logger = Logger(
        subsystem: "com.prakashjoshipax.voiceink",
        category: "TranscriptionAutoCleanupService"
    )
    private var modelContext: ModelContext?
    private var transcriptionObserver: NSObjectProtocol?

    private var recordingsDirectory: URL {
        AppBrand.applicationSupportDirectory()
            .appendingPathComponent("Recordings")
    }

    private init() {}

    deinit {
        if let transcriptionObserver {
            NotificationCenter.default.removeObserver(transcriptionObserver)
        }
    }

    func startMonitoring(modelContext: ModelContext) {
        self.modelContext = modelContext
        if let transcriptionObserver {
            NotificationCenter.default.removeObserver(transcriptionObserver)
        }
        transcriptionObserver = NotificationCenter.default.addObserver(
            forName: .transcriptionCompleted,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                self?.handleTranscriptionCompleted(notification)
            }
        }

        guard UserDefaults.standard.bool(forKey: CleanupSettingsKeys.isTranscriptionCleanupEnabled) else {
            return
        }
        Task { @MainActor [weak self] in
            guard let self, let modelContext = self.modelContext else { return }
            await self.sweepOldTranscriptions(modelContext: modelContext)
            await self.cleanupOrphanAudioFiles(modelContext: modelContext)
        }
    }

    func stopMonitoring() {
        if let transcriptionObserver {
            NotificationCenter.default.removeObserver(transcriptionObserver)
            self.transcriptionObserver = nil
        }
    }

    func runManualCleanup(modelContext: ModelContext) async {
        await sweepOldTranscriptions(modelContext: modelContext)
    }

    private func handleTranscriptionCompleted(_ notification: Notification) {
        guard UserDefaults.standard.bool(forKey: CleanupSettingsKeys.isTranscriptionCleanupEnabled) else {
            return
        }
        guard let modelContext else {
            logger.error("Missing model context for transcription cleanup")
            return
        }

        let retentionMinutes = UserDefaults.standard.integer(
            forKey: CleanupSettingsKeys.transcriptionRetentionMinutes
        )
        if retentionMinutes > 0 {
            Task { @MainActor [weak self] in
                await self?.sweepOldTranscriptions(modelContext: modelContext)
            }
            return
        }

        guard let transcription = notification.object as? Transcription else {
            logger.error("Invalid transcription cleanup notification")
            return
        }
        Task { @MainActor [weak self] in
            await self?.deleteTranscription(transcription, modelContext: modelContext)
        }
    }

    private func deleteTranscription(_ transcription: Transcription, modelContext: ModelContext) async {
        if let candidate = audioCandidate(from: transcription) {
            let results = await cleanupWorker.delete([candidate], allowedRoot: recordingsDirectory)
            if results.contains(where: { if case .failed = $0.deletion { return true }; return false }) {
                logger.error("Failed to delete an audio file during transcription cleanup")
            }
        }

        modelContext.delete(transcription)
        do {
            try modelContext.save()
            NotificationCenter.default.post(name: .transcriptionDeleted, object: nil)
        } catch {
            modelContext.rollback()
            logger.error(
                "Failed to save transcription cleanup: \(AppLogger.errorMetadata(error), privacy: .public)"
            )
        }
    }

    private func sweepOldTranscriptions(modelContext: ModelContext) async {
        guard UserDefaults.standard.bool(forKey: CleanupSettingsKeys.isTranscriptionCleanupEnabled) else {
            return
        }

        let retentionMinutes = max(
            UserDefaults.standard.integer(forKey: CleanupSettingsKeys.transcriptionRetentionMinutes),
            0
        )
        let cutoffDate = Date().addingTimeInterval(TimeInterval(-retentionMinutes * 60))

        do {
            let descriptor = FetchDescriptor<Transcription>(
                predicate: #Predicate<Transcription> { transcription in
                    transcription.timestamp < cutoffDate
                }
            )
            let transcriptions = try modelContext.fetch(descriptor)
            let candidates = transcriptions.compactMap(audioCandidate(from:))
            let deletionResults = await cleanupWorker.delete(candidates, allowedRoot: recordingsDirectory)
            let failures = deletionResults.reduce(into: 0) { count, result in
                if case .failed = result.deletion { count += 1 }
            }

            for transcription in transcriptions {
                modelContext.delete(transcription)
            }
            guard !transcriptions.isEmpty else { return }

            try modelContext.save()
            logger.notice(
                "Cleaned up transcriptions count=\(transcriptions.count, privacy: .public) audioFailures=\(failures, privacy: .public)"
            )
            NotificationCenter.default.post(name: .transcriptionDeleted, object: nil)
        } catch {
            modelContext.rollback()
            logger.error(
                "Transcription cleanup failed: \(AppLogger.errorMetadata(error), privacy: .public)"
            )
        }
    }

    private func cleanupOrphanAudioFiles(modelContext: ModelContext) async {
        guard UserDefaults.standard.bool(forKey: CleanupSettingsKeys.isTranscriptionCleanupEnabled) else {
            return
        }

        do {
            var descriptor = FetchDescriptor<Transcription>()
            descriptor.propertiesToFetch = [\.audioFileURL]
            let transcriptions = try modelContext.fetch(descriptor)
            let referencedFiles = Set(transcriptions.compactMap { transcription in
                transcription.audioFileURL.flatMap(URL.init(string:))?.lastPathComponent
            })
            let result = await cleanupWorker.deleteOrphans(
                referencedFileNames: referencedFiles,
                allowedRoot: recordingsDirectory
            )
            if result.deletedCount > 0 || result.failureCount > 0 {
                logger.notice(
                    "Cleaned orphan audio deleted=\(result.deletedCount, privacy: .public) failures=\(result.failureCount, privacy: .public)"
                )
            }
        } catch {
            logger.error(
                "Orphan audio cleanup failed: \(AppLogger.errorMetadata(error), privacy: .public)"
            )
        }
    }

    private func audioCandidate(from transcription: Transcription) -> AudioFileCandidate? {
        guard let urlString = transcription.audioFileURL,
            let url = URL(string: urlString)
        else {
            return nil
        }
        return AudioFileCandidate(id: transcription.id, url: url)
    }
}
