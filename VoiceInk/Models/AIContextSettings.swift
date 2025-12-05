import Foundation

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
