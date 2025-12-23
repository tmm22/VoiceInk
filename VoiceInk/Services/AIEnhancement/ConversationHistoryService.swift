import Foundation
import SwiftData

@MainActor
class ConversationHistoryService {
    private let modelContext: ModelContext
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    /// Fetches recent transcriptions within time window
    func getRecentTranscriptions(
        windowSeconds: Int,
        maxItems: Int
    ) -> [TranscriptionSummary] {
        let cutoffDate = Date().addingTimeInterval(-Double(windowSeconds))
        
        let descriptor = FetchDescriptor<Transcription>(
            predicate: #Predicate<Transcription> { transcription in
                transcription.timestamp >= cutoffDate && !transcription.isDeleted
            },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        
        // Fetch and limit manually since FetchDescriptor limit is not always reliable or available depending on context
        do {
            let transcriptions = try modelContext.fetch(descriptor)
            
            return transcriptions.prefix(maxItems).map { transcription in
                let text = transcription.enhancedText ?? transcription.text
                // Truncate to ~200 characters to save tokens
                let truncatedText = text.count > 200 ? String(text.prefix(200)) + "..." : text
                
                return TranscriptionSummary(
                    text: truncatedText,
                    timestamp: transcription.timestamp,
                    wasEnhanced: transcription.enhancedText != nil
                )
            }
        } catch {
            AppLogger.storage.error("Failed to fetch conversation history: \(error.localizedDescription)")
            return []
        }
    }
}
