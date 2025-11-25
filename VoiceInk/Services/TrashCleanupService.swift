import Foundation
import SwiftData

@MainActor
final class TrashCleanupService {
    static let shared = TrashCleanupService()
    
    private let logger = AppLogger.storage
    
    /// Number of days before items in trash are permanently deleted
    static let retentionDays: Int = 30
    
    private init() {}
    
    /// Cleans up transcriptions that have been in trash longer than the retention period
    func cleanupExpiredTrashItems(modelContext: ModelContext) async {
        let calendar = Calendar.current
        guard let cutoffDate = calendar.date(byAdding: .day, value: -Self.retentionDays, to: Date()) else {
            logger.error("Failed to calculate trash cleanup cutoff date")
            return
        }
        
        do {
            let descriptor = FetchDescriptor<Transcription>(
                predicate: #Predicate<Transcription> { transcription in
                    transcription.isDeleted == true
                }
            )
            
            let deletedTranscriptions = try modelContext.fetch(descriptor)
            
            var cleanedCount = 0
            var freedBytes: Int64 = 0
            
            for transcription in deletedTranscriptions {
                guard let deletedAt = transcription.deletedAt, deletedAt < cutoffDate else {
                    continue
                }
                
                if let urlString = transcription.audioFileURL,
                   let url = URL(string: urlString),
                   FileManager.default.fileExists(atPath: url.path) {
                    do {
                        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                        if let fileSize = attributes[.size] as? Int64 {
                            freedBytes += fileSize
                        }
                        try FileManager.default.removeItem(at: url)
                    } catch {
                        logger.error("Failed to delete audio file during trash cleanup: \(error.localizedDescription)")
                    }
                }
                
                modelContext.delete(transcription)
                cleanedCount += 1
            }
            
            if cleanedCount > 0 {
                try modelContext.save()
                let freedMB = Double(freedBytes) / 1_000_000
                logger.info("Trash cleanup: Permanently deleted \(cleanedCount) items, freed \(String(format: "%.2f", freedMB)) MB")
            }
        } catch {
            logger.error("Failed to cleanup expired trash items: \(error.localizedDescription)")
        }
    }
    
    /// Returns the count of items currently in trash
    func getTrashCount(modelContext: ModelContext) -> Int {
        do {
            let descriptor = FetchDescriptor<Transcription>(
                predicate: #Predicate<Transcription> { transcription in
                    transcription.isDeleted == true
                }
            )
            return try modelContext.fetchCount(descriptor)
        } catch {
            logger.error("Failed to get trash count: \(error.localizedDescription)")
            return 0
        }
    }
}
