import Foundation

enum ContextAwarenessLevel: String, CaseIterable, Identifiable, Codable {
    case minimal
    case balanced
    case maximum
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .minimal: return "Minimal"
        case .balanced: return "Balanced"
        case .maximum: return "Maximum"
        }
    }
    
    var description: String {
        switch self {
        case .minimal: return "Optimized for lightning-fast dictation. Only essential signals (App & Time) are sent, ensuring maximum privacy and zero processing delay."
        case .balanced: return "The sweet spot for productivity. Enables web summarization, file awareness, and clipboard context without the performance cost of visual processing."
        case .maximum: return "Complete environmental awareness. The AI 'sees' your screen and checks your calendar to provide deeply contextualized assistance, with slightly increased processing time."
        }
    }
    
    var tradeOff: String {
        switch self {
        case .minimal: return "Instant • Max Privacy"
        case .balanced: return "Smart • Fast"
        case .maximum: return "Deep Context • Slower"
        }
    }
}

struct AIContextSettings: Codable {
    var includeClipboard: Bool = true
    var includeScreenCapture: Bool = true
    var includeSelectedText: Bool = true
    var includeApplicationContext: Bool = true
    var includeFocusedElement: Bool = true
    var includeSelectedFiles: Bool = true
    var includeBrowserContent: Bool = true
    var includeTemporalContext: Bool = true
    var includeCalendar: Bool = false               // Opt-in due to permissions
    var includeConversationHistory: Bool = false    // Opt-in
    var maxConversationItems: Int = 3
    var conversationWindowMinutes: Int = 5
    
    // NEW: User Bio for personal context
    var userBio: String = ""
    
    // Priority order for truncation (lower = higher priority)
    var contextPriorities: [ContextType: Int] = [
        .selectedText: 1,
        .focusedElement: 1,
        .clipboard: 2,
        .selectedFiles: 3,
        .browserContent: 3,
        .screenCapture: 4,
        .conversationHistory: 5
    ]
    
    mutating func applyLevel(_ level: ContextAwarenessLevel) {
        switch level {
        case .minimal:
            includeApplicationContext = true
            includeTemporalContext = true
            includeSelectedText = true
            includeFocusedElement = true
            
            includeClipboard = false
            includeScreenCapture = false
            includeSelectedFiles = false
            includeBrowserContent = false
            includeCalendar = false
            includeConversationHistory = false
            
        case .balanced:
            includeApplicationContext = true
            includeTemporalContext = true
            includeSelectedText = true
            includeFocusedElement = true
            includeClipboard = true
            includeSelectedFiles = true
            includeBrowserContent = true
            
            includeScreenCapture = false
            includeCalendar = false
            includeConversationHistory = false
            
        case .maximum:
            includeApplicationContext = true
            includeTemporalContext = true
            includeSelectedText = true
            includeFocusedElement = true
            includeClipboard = true
            includeSelectedFiles = true
            includeBrowserContent = true
            includeScreenCapture = true
            includeCalendar = true
            includeConversationHistory = true
        }
    }
    
    func matchesLevel(_ level: ContextAwarenessLevel) -> Bool {
        var temp = AIContextSettings()
        temp.applyLevel(level)
        
        // Compare structural settings (ignoring bio and scalar values like max items)
        return includeApplicationContext == temp.includeApplicationContext &&
               includeTemporalContext == temp.includeTemporalContext &&
               includeSelectedText == temp.includeSelectedText &&
               includeFocusedElement == temp.includeFocusedElement &&
               includeClipboard == temp.includeClipboard &&
               includeScreenCapture == temp.includeScreenCapture &&
               includeSelectedFiles == temp.includeSelectedFiles &&
               includeBrowserContent == temp.includeBrowserContent &&
               includeCalendar == temp.includeCalendar &&
               includeConversationHistory == temp.includeConversationHistory
    }
}

enum ContextType: String, Codable {
    case selectedText
    case clipboard
    case screenCapture
    case customVocabulary
    case conversationHistory
    case focusedElement
    case selectedFiles
    case browserContent
}
