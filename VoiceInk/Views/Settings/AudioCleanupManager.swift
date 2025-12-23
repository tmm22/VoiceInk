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
    
    // Default cleanup settings
    private let defaultRetentionDays = 7
    private let cleanupCheckInterval: TimeInterval = 86400 // Check once per day (in seconds)
    
    private init() {
        logger.info("AudioCleanupManager initialized")
    }
    
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
        
        logger.info("Automatic cleanup scheduled")
    }
    
    /// Stop the automatic cleanup process
    func stopAutomaticCleanup() {
        logger.info("Stopping automatic audio cleanup")
        cleanupTimer?.invalidate()
        cleanupTimer = nil
    }
    
    /// Get information about the files that would be cleaned up
    func getCleanupInfo(modelContext: ModelContext) async -> (fileCount: Int, totalSize: Int64, transcriptions: [Transcription]) {
        logger.info("Analyzing potential audio cleanup")
        
        // Get retention period from UserDefaults
        let retentionDays = AppSettings.Audio.audioRetentionPeriod
        let effectiveRetentionDays = retentionDays > 0 ? retentionDays : defaultRetentionDays
        
        // Calculate the cutoff date
        let calendar = Calendar.current
        guard let cutoffDate = calendar.date(byAdding: .day, value: -effectiveRetentionDays, to: Date()) else {
            logger.error("Failed to calculate cutoff date")
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

            // Calculate stats (can be done on any thread)
            var fileCount = 0
            var totalSize: Int64 = 0
            var eligibleTranscriptions: [Transcription] = []

            for transcription in transcriptions {
                if let urlString = transcription.audioFileURL,
                   let url = URL(string: urlString),
                   FileManager.default.fileExists(atPath: url.path) {
                    do {
                        // Get file attributes to determine size
                        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                        if let fileSize = attributes[.size] as? Int64 {
                            totalSize += fileSize
                            fileCount += 1
                            eligibleTranscriptions.append(transcription)
                        }
                    } catch {
                        logger.error("Failed to get attributes for \(url.lastPathComponent): \(error.localizedDescription)")
                    }
                }
            }

            logger.info("Found \(fileCount) files eligible for cleanup, totaling \(self.formatFileSize(totalSize))")
            return (fileCount, totalSize, eligibleTranscriptions)
        } catch {
            logger.error("Error analyzing files for cleanup: \(error.localizedDescription)")
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
            logger.error("Failed to calculate cutoff date")
            return
        }
        
        logger.info("Cutoff date for audio cleanup: \(cutoffDate)")
        
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

            var deletedCount = 0
            var errorCount = 0

            for transcription in transcriptions {
                if let urlString = transcription.audioFileURL,
                   let url = URL(string: urlString),
                   FileManager.default.fileExists(atPath: url.path) {
                    do {
                        // Delete the audio file
                        try FileManager.default.removeItem(at: url)

                        // Update the transcription to remove the audio file reference
                        transcription.audioFileURL = nil

                        deletedCount += 1
                        logger.debug("Deleted audio file: \(url.lastPathComponent)")
                    } catch {
                        errorCount += 1
                        logger.error("Failed to delete audio file \(url.lastPathComponent): \(error.localizedDescription)")
                    }
                }
            }

            if deletedCount > 0 || errorCount > 0 {
                try modelContext.save()
                logger.info("Cleanup complete. Deleted \(deletedCount) files. Failed: \(errorCount)")
            }
        } catch {
            logger.error("Error during audio cleanup: \(error.localizedDescription)")
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
        
        var deletedCount = 0
        var errorCount = 0

        for transcription in transcriptions {
            if let urlString = transcription.audioFileURL,
               let url = URL(string: urlString),
               FileManager.default.fileExists(atPath: url.path) {
                do {
                    // Delete the audio file
                    try FileManager.default.removeItem(at: url)

                    // Update the transcription to remove the audio file reference
                    transcription.audioFileURL = nil

                    deletedCount += 1
                    logger.debug("Deleted audio file: \(url.lastPathComponent)")
                } catch {
                    errorCount += 1
                    logger.error("Failed to delete audio file \(url.lastPathComponent): \(error.localizedDescription)")
                }
            }
        }

        if deletedCount > 0 || errorCount > 0 {
            do {
                try modelContext.save()
                logger.info("Cleanup complete. Deleted \(deletedCount) files. Failed: \(errorCount)")
            } catch {
                logger.error("Error saving model context after cleanup: \(error.localizedDescription)")
            }
        }

        return (deletedCount, errorCount)
    }
    
    /// Format file size in human-readable form
    func formatFileSize(_ size: Int64) -> String {
        let byteCountFormatter = ByteCountFormatter()
        byteCountFormatter.allowedUnits = [.useKB, .useMB, .useGB]
        byteCountFormatter.countStyle = .file
        return byteCountFormatter.string(fromByteCount: size)
    }
} 
