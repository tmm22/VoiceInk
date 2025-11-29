import Foundation
import SwiftData
import OSLog

@MainActor
class LastTranscriptionService: ObservableObject {
    
    static func getLastTranscription(from modelContext: ModelContext) -> Transcription? {
        var descriptor = FetchDescriptor<Transcription>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        
        do {
            let transcriptions = try modelContext.fetch(descriptor)
            return transcriptions.first
        } catch {
            AppLogger.transcription.error("Error fetching last transcription: \(error)")
            return nil
        }
    }
    
    static func copyLastTranscription(from modelContext: ModelContext) {
        guard let lastTranscription = getLastTranscription(from: modelContext) else {
            Task { @MainActor in
                NotificationManager.shared.showNotification(
                    title: Localization.Transcription.noTranscriptionAvailable,
                    type: .error
                )
            }
            return
        }
        
        // Prefer enhanced text; fallback to original text
        let textToCopy: String = {
            if let enhancedText = lastTranscription.enhancedText, !enhancedText.isEmpty {
                return enhancedText
            } else {
                return lastTranscription.text
            }
        }()
        
        let success = ClipboardManager.copyToClipboard(textToCopy)
        
        Task { @MainActor in
            if success {
                NotificationManager.shared.showNotification(
                    title: Localization.Transcription.lastTranscriptionCopied,
                    type: .success
                )
            } else {
                NotificationManager.shared.showNotification(
                    title: Localization.Transcription.failedToCopy,
                    type: .error
                )
            }
        }
    }

    static func pasteLastTranscription(from modelContext: ModelContext) {
        guard let lastTranscription = getLastTranscription(from: modelContext) else {
            Task { @MainActor in
                NotificationManager.shared.showNotification(
                    title: Localization.Transcription.noTranscriptionAvailable,
                    type: .error
                )
            }
            return
        }
        
        let textToPaste = lastTranscription.text

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            CursorPaster.pasteAtCursor(textToPaste)
        }
    }
    
    static func pasteLastEnhancement(from modelContext: ModelContext) {
        guard let lastTranscription = getLastTranscription(from: modelContext) else {
            Task { @MainActor in
                NotificationManager.shared.showNotification(
                    title: Localization.Transcription.noTranscriptionAvailable,
                    type: .error
                )
            }
            return
        }
        
        // Prefer enhanced text; if unavailable, fallback to original text (which may contain an error message)
        let textToPaste: String = {
            if let enhancedText = lastTranscription.enhancedText, !enhancedText.isEmpty {
                return enhancedText
            } else {
                return lastTranscription.text
            }
        }()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            CursorPaster.pasteAtCursor(textToPaste)
        }
    }
    
    static func retryLastTranscription(from modelContext: ModelContext, whisperState: WhisperState) {
        Task { @MainActor in
            guard let lastTranscription = getLastTranscription(from: modelContext),
                  let audioURLString = lastTranscription.audioFileURL,
                  let audioURL = URL(string: audioURLString),
                  FileManager.default.fileExists(atPath: audioURL.path) else {
                NotificationManager.shared.showNotification(
                    title: Localization.Transcription.audioFileNotFound,
                    type: .error
                )
                return
            }
            
            guard let currentModel = whisperState.currentTranscriptionModel else {
                NotificationManager.shared.showNotification(
                    title: Localization.Transcription.noModelSelected,
                    type: .error
                )
                return
            }
            
            let transcriptionService = AudioTranscriptionService(modelContext: modelContext, whisperState: whisperState)
            do {
                let newTranscription = try await transcriptionService.retranscribeAudio(from: audioURL, using: currentModel)
                
                let textToCopy: String
                if let enhanced = newTranscription.enhancedText, !enhanced.isEmpty {
                    textToCopy = enhanced
                } else {
                    textToCopy = newTranscription.text
                }
                
                ClipboardManager.copyToClipboard(textToCopy)
                
                NotificationManager.shared.showNotification(
                    title: Localization.Transcription.copiedToClipboard,
                    type: .success
                )
            } catch {
                NotificationManager.shared.showNotification(
                    title: String(format: Localization.Transcription.retryFailed, error.localizedDescription),
                    type: .error
                )
            }
        }
    }
}