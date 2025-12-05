import Foundation

/// Comprehensive context object passed to AI enhancement
struct AIContext: Codable {
    // Core content contexts
    let selectedText: ContextSection?
    let clipboard: ContextSection?
    let screenCapture: ScreenCaptureContext?
    let customVocabulary: [String]
    let focusedElement: FocusedElementContext?
    let selectedFiles: [FileContext]?
    let browserContent: BrowserContentContext?
    
    // Operational contexts
    let application: ApplicationContext?
    let calendar: CalendarContext?
    let temporal: TemporalContext
    let session: SessionContext
    let powerMode: PowerModeContext?
    let conversationHistory: ConversationContext?
    let userBio: String?
    
    // Metadata
    let capturedAt: Date
    var contextVersion: String { "1.0" }
}

struct ContextSection: Codable {
    let content: String
    let source: String           // e.g., "clipboard", "selected_text"
    let capturedAt: Date
    let characterCount: Int
    let wasTruncated: Bool
}

struct ScreenCaptureContext: Codable {
    let windowTitle: String
    let applicationName: String
    let ocrText: String?
    let capturedAt: Date
    let wasTruncated: Bool
}

struct FocusedElementContext: Codable {
    let role: String
    let roleDescription: String
    let title: String?
    let description: String?
    let placeholderValue: String?
    let valueSnippet: String?
    let textBeforeCursor: String?
    let textAfterCursor: String?
    let nearbyLabels: [String]
    let capturedAt: Date
}

struct ApplicationContext: Codable {
    let name: String              // "Slack"
    let bundleIdentifier: String  // "com.tinyspeck.slackmacgap"
    let isBrowser: Bool
    let currentURL: String?       // Only if browser
    let pageTitle: String?        // Browser tab title (future)
}

struct TemporalContext: Codable {
    let date: String              // "2025-12-05"
    let time: String              // "14:30"
    let dayOfWeek: String         // "Friday"
    let timezone: String          // "America/New_York"
    let isWeekend: Bool
}

struct SessionContext: Codable {
    let recordingDuration: TimeInterval
    let transcriptionModel: String
    let language: String
    let isEnhancementEnabled: Bool
    let promptName: String?
}

struct PowerModeContext: Codable {
    let configName: String
    let emoji: String
    let matchedBy: String         // "app", "url", or "default"
    let matchedPattern: String?   // The bundle ID or URL that matched
}

struct ConversationContext: Codable {
    let recentTranscriptions: [TranscriptionSummary]
    let windowSeconds: Int        // How far back we looked
}

struct TranscriptionSummary: Codable {
    let text: String              // Truncated to ~200 chars
    let timestamp: Date
    let wasEnhanced: Bool
}

struct CalendarContext: Codable {
    let upcomingEvents: [CalendarEventContext]
}
