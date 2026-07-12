import Foundation
import SwiftData
import OSLog

/// A utility class that manages automatic cleanup of audio files while preserving transcript data
@MainActor
class AudioCleanupManager {
    static let shared = AudioCleanupManager()
    
    private let logger = Logger(subsystem: "com.tmm22.voicelinkcommunity", category: "AudioCleanupManager")
    private var cleanupTimer: Timer?
    private var modelContext: ModelContext?
    private let fileWorker = AudioFileCleanupWorker()
    private let recordingsDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("com.prakashjoshipax.VoiceInk")
        .appendingPathComponent("Recordings")
    
    // Default cleanup settings
    private let defaultRetentionDays = 7
    private let cleanupCheckInterval: TimeInterval = 86400 // Check once per day (in seconds)
    
    private init() {}
    
    /// Start the automatic cleanup process
    func startAutomaticCleanup(modelContext: ModelContext) {
        logger.info("Starting automatic audio cleanup")
        self.modelContext = modelContext
        
        // Cancel any existing timer
        cleanupTimer?.invalidate()

        // Perform initial cleanup
        Task {
            await performCleanup()
        }

        // Schedule regular cleanup
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: cleanupCheckInterval, repeats: true) { [weak self] _ in
            Task { [weak self] in
                await self?.performCleanup()
            }
        }
    }
    
    /// Stop the automatic cleanup process
    func stopAutomaticCleanup() {
        cleanupTimer?.invalidate()
        cleanupTimer = nil
    }
    
    /// Get information about the files that would be cleaned up
    func getCleanupInfo(modelContext: ModelContext) async -> (fileCount: Int, totalSize: Int64, transcriptions: [Transcription]) {
        // Get retention period from UserDefaults
        let retentionDays = AppSettings.Audio.audioRetentionPeriod
        let effectiveRetentionDays = retentionDays > 0 ? retentionDays : defaultRetentionDays
        
        // Calculate the cutoff date
        let calendar = Calendar.current
        guard let cutoffDate = calendar.date(byAdding: .day, value: -effectiveRetentionDays, to: Date()) else {
            return (0, 0, [])
        }

        do {
            // Create a predicate to find transcriptions with audio files older than the cutoff date
            let descriptor = FetchDescriptor<Transcription>(
                predicate: #Predicate<Transcription> { transcription in
                    transcription.timestamp < cutoffDate &&
                    transcription.audioFileURL != nil
                }
            )

            let transcriptions = try modelContext.fetch(descriptor)

            let candidates = makeCandidates(from: transcriptions)
            let inspections = await fileWorker.inspect(candidates)
            let presentByID = inspections.reduce(into: [UUID: Int64]()) { result, inspection in
                if case .present(let size) = inspection.inspection {
                    result[inspection.candidate.id] = size
                }
            }
            let totalSize = presentByID.values.reduce(0, +)
            let eligibleTranscriptions = transcriptions.filter { presentByID[$0.id] != nil }
            let fileCount = eligibleTranscriptions.count

            logger.info("Found \(fileCount) files eligible for cleanup, totaling \(self.formatFileSize(totalSize))")
            return (fileCount, totalSize, eligibleTranscriptions)
        } catch {
            logger.error("Failed to fetch audio cleanup information: \(AppLogger.errorMetadata(error), privacy: .public)")
            return (0, 0, [])
        }
    }
    
    /// Perform the cleanup operation
    private func performCleanup() async {
        logger.info("Performing audio cleanup")
        guard let modelContext = modelContext else {
            logger.error("Missing model context for audio cleanup")
            return
        }
        
        // Get retention period from UserDefaults
        let retentionDays = AppSettings.Audio.audioRetentionPeriod
        let effectiveRetentionDays = retentionDays > 0 ? retentionDays : defaultRetentionDays
        
        // Check if automatic cleanup is enabled
        let isCleanupEnabled = AppSettings.Audio.isAudioCleanupEnabled
        guard isCleanupEnabled else {
            logger.info("Audio cleanup is disabled, skipping")
            return
        }
        
        logger.info("Audio retention period: \(effectiveRetentionDays) days")
        
        // Calculate the cutoff date
        let calendar = Calendar.current
        guard let cutoffDate = calendar.date(byAdding: .day, value: -effectiveRetentionDays, to: Date()) else {
            return
        }

        do {
            // Create a predicate to find transcriptions with audio files older than the cutoff date
            let descriptor = FetchDescriptor<Transcription>(
                predicate: #Predicate<Transcription> { transcription in
                    transcription.timestamp < cutoffDate &&
                    transcription.audioFileURL != nil
                }
            )

            let transcriptions = try modelContext.fetch(descriptor)
            logger.info("Found \(transcriptions.count) transcriptions with audio files to clean up")

            let results = await fileWorker.delete(makeCandidates(from: transcriptions), allowedRoot: recordingsDirectory)
            let counts = reconcile(results, with: transcriptions)
            let deletedCount = counts.deletedCount
            let errorCount = counts.errorCount

            if counts.referencesChanged > 0 || errorCount > 0 {
                try modelContext.save()
                logger.info("Cleanup complete. Deleted \(deletedCount) files. Failed: \(errorCount)")
            }
        } catch {
            logger.error("Automatic audio cleanup failed: \(AppLogger.errorMetadata(error), privacy: .public)")
        }
    }
    
    /// Run cleanup manually - can be called from settings
    func runManualCleanup(modelContext: ModelContext) async {
        self.modelContext = modelContext
        await performCleanup()
    }
    
    /// Run cleanup on the specified transcriptions
    func runCleanupForTranscriptions(modelContext: ModelContext, transcriptions: [Transcription]) async -> (deletedCount: Int, errorCount: Int) {
        logger.info("Running cleanup for \(transcriptions.count) specific transcriptions")
        
        let results = await fileWorker.delete(makeCandidates(from: transcriptions), allowedRoot: recordingsDirectory)
        let counts = reconcile(results, with: transcriptions)
        let deletedCount = counts.deletedCount
        let errorCount = counts.errorCount

        if counts.referencesChanged > 0 || errorCount > 0 {
            do {
                try modelContext.save()
                logger.info("Cleanup complete. Deleted \(deletedCount) files. Failed: \(errorCount)")
            } catch {
                logger.error("Error saving model context after cleanup: \(AppLogger.errorMetadata(error), privacy: .public)")
            }
        }

        return (deletedCount, errorCount)
    }

    private func makeCandidates(from transcriptions: [Transcription]) -> [AudioFileCandidate] {
        transcriptions.compactMap { transcription in
            guard let urlString = transcription.audioFileURL,
                  let url = URL(string: urlString) else { return nil }
            return AudioFileCandidate(id: transcription.id, url: url)
        }
    }

    private func reconcile(
        _ results: [AudioFileDeletionResult],
        with transcriptions: [Transcription]
    ) -> (deletedCount: Int, errorCount: Int, referencesChanged: Int) {
        var transcriptionsByID: [UUID: Transcription] = [:]
        for transcription in transcriptions where transcriptionsByID[transcription.id] == nil {
            transcriptionsByID[transcription.id] = transcription
        }
        var deletedCount = 0
        var errorCount = 0
        var referencesChanged = 0

        for result in results {
            switch result.deletion {
            case .deleted:
                let transcription = transcriptionsByID[result.candidate.id]
                if transcription?.audioFileURL == result.candidate.url.absoluteString {
                    transcription?.audioFileURL = nil
                    deletedCount += 1
                    referencesChanged += 1
                }
            case .missing:
                let transcription = transcriptionsByID[result.candidate.id]
                if transcription?.audioFileURL == result.candidate.url.absoluteString {
                    transcription?.audioFileURL = nil
                    referencesChanged += 1
                }
            case .failed(let message):
                errorCount += 1
                logger.error("Failed to delete audio file during cleanup: \(message, privacy: .private)")
            }
        }
        return (deletedCount, errorCount, referencesChanged)
    }
    
    /// Format file size in human-readable form
    func formatFileSize(_ size: Int64) -> String {
        let byteCountFormatter = ByteCountFormatter()
        byteCountFormatter.allowedUnits = [.useKB, .useMB, .useGB]
        byteCountFormatter.countStyle = .file
        return byteCountFormatter.string(fromByteCount: size)
    }
} 
