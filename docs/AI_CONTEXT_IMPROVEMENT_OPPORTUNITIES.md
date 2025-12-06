# AI Context Improvement Opportunities

This document captures potential enhancements to the VoiceInk AI Context system identified during the December 2025 review. These improvements are categorized by priority and impact.

---

## Completed Improvements

### Browser Content Support Expansion ✅
**Status:** Implemented (December 2025)

Expanded browser content extraction from 4 browsers to 11 browsers:
- **Full support added:** Edge, Opera, Vivaldi, Orion, Yandex
- **Partial support added:** Firefox, Zen (title only due to AppleScript limitations)
- **Bonus fix:** `ApplicationContext.pageTitle` now populated from browser content

**Impact:** Browser content coverage improved from 36% to 82%

---

## Tier 1: High-Impact Accuracy Improvements

### 1. Programming Language Detection for FocusedElementContext

**Problem:** When users dictate code, the AI doesn't know what programming language they're using. The 500-character `valueSnippet` shows code but the language isn't identified.

**Proposed Solution:** Add a `detectedLanguage: String?` field to `FocusedElementContext` based on:
- File extension from window title (e.g., `.swift`, `.py`, `.js`)
- Heuristic syntax analysis of `valueSnippet`
- Application name inference (Xcode → Swift, PyCharm → Python)

**Implementation Location:**
- `VoiceInk/Services/AIEnhancement/FocusedElementService.swift`
- `VoiceInk/Models/AIContext.swift` (add field to `FocusedElementContext`)

**Impact:** Dramatically improves code dictation accuracy (correct syntax, casing conventions, language-specific keywords).

**Estimated Effort:** Medium (2-4 hours)

---

### 2. Enriched Calendar Context

**Problem:** `CalendarEventContext` only captures title, dates, and all-day status. Missing meeting attendees and location limits context for phrases like "Draft follow-up to Jane from the meeting."

**Proposed Solution:** Add optional fields to `CalendarEventContext`:
```swift
struct CalendarEventContext: Codable {
    // Existing fields...
    let location: String?       // "Conference Room B" or Zoom link
    let attendees: [String]?    // ["John Smith", "Jane Doe"]
    let notes: String?          // First 200 chars of meeting notes
}
```

**Implementation Location:**
- `VoiceInk/Services/AIEnhancement/CalendarService.swift`
- `VoiceInk/Models/AIContext.swift`

**Privacy Consideration:** Attendees and notes are sensitive - should remain opt-in and only available at "Maximum" awareness level.

**Impact:** Enables natural references to meeting participants and locations.

**Estimated Effort:** Low-Medium (1-2 hours)

---

### 3. File Content Preview for Text Files

**Problem:** `FileContext` only captures metadata (name, size, dates). For text files, a content preview would help the AI understand what the file contains, enabling "summarize this file" commands.

**Proposed Solution:** Add optional `contentPreview: String?` field (first 500 characters) for text-based files:
```swift
struct FileContext: Codable {
    // Existing fields...
    let contentPreview: String?  // First 500 chars for text files
    let fileType: FileType       // .text, .code, .image, .document, .other
}

enum FileType: String, Codable {
    case text       // .txt, .md, .rtf
    case code       // .swift, .py, .js, .ts, .rb, .go, etc.
    case image      // .png, .jpg, .gif, .svg
    case document   // .pdf, .doc, .docx
    case other
}
```

**Implementation Location:**
- `VoiceInk/Services/AIEnhancement/SelectedFileService.swift`
- `VoiceInk/Models/AIContext.swift`

**Security Consideration:** Only preview files under a certain size limit (e.g., 1MB) to prevent performance issues.

**Impact:** Enables file-aware commands without requiring full OCR.

**Estimated Effort:** Medium (2-3 hours)

---

## Tier 2: Medium-Impact Improvements

### 4. Clipboard History

**Problem:** Only the current clipboard item is captured. Recent clipboard history could provide more context for multi-step workflows.

**Proposed Solution:** Add `recentClipboardItems: [ContextSection]?` with last 3-5 items.

**Privacy Consideration:** This is highly sensitive - should be opt-in with clear user consent.

**Implementation Approach:** 
- Use `NSPasteboard.general.changeCount` to track clipboard changes
- Store recent items in memory (not persisted)
- Clear on app restart

**Estimated Effort:** Medium (2-3 hours)

---

### 5. Smarter Truncation with Semantic Preservation

**Problem:** `TokenBudgetManager` uses character-based truncation with boundary awareness, but still loses semantic meaning from long content.

**Proposed Solution:** 
- For browser content: Extract key sentences using TextRank or similar algorithm
- For conversation history: Prioritize recent items and questions
- Add semantic summarization pass before hard truncation

**Implementation Location:**
- `VoiceInk/Services/AIEnhancement/TokenBudgetManager.swift`

**Estimated Effort:** High (4-6 hours) - requires NLP integration

---

### 6. Notification Context (Opt-in)

**Problem:** Recent macOS notifications could provide relevant context (e.g., Slack message just received, calendar reminder).

**Proposed Solution:** Add `NotificationContext` struct:
```swift
struct NotificationContext: Codable {
    let recentNotifications: [NotificationItem]
}

struct NotificationItem: Codable {
    let appName: String
    let title: String
    let body: String?
    let timestamp: Date
}
```

**Privacy Consideration:** Extremely sensitive - must be opt-in with granular per-app controls.

**Technical Challenge:** Requires User Notifications framework access and may need accessibility permissions.

**Estimated Effort:** High (4-6 hours)

---

### 7. Improved Conversation History

**Problem:** Each transcription in `ConversationContext` is truncated to 200 characters, potentially losing important context. No topic awareness.

**Proposed Solution:**
- Increase per-item limit to 400-500 characters
- Add `topic: String?` field with auto-detected topic
- Add `isQuestion: Bool` to identify questions vs statements
- Add `sentiment: String?` for emotional context

```swift
struct TranscriptionSummary: Codable {
    let text: String              // Increased to 400 chars
    let timestamp: Date
    let wasEnhanced: Bool
    let topic: String?            // Auto-detected topic
    let isQuestion: Bool          // Question detection
}
```

**Estimated Effort:** Medium (2-4 hours)

---

### 8. Git/Project Context for Code Editors

**Problem:** No awareness of current git branch, project name, or recent file changes when working in IDEs.

**Proposed Solution:** Add `ProjectContext` struct:
```swift
struct ProjectContext: Codable {
    let projectName: String?
    let gitBranch: String?
    let recentFiles: [String]?    // Last 5 modified files
    let workspacePath: String?
}
```

**Implementation Approach:**
- Parse window title for project/workspace name
- Run `git branch --show-current` in workspace directory
- Use file system monitoring for recent files

**Estimated Effort:** Medium-High (3-5 hours)

---

## Tier 3: Lower-Priority Enhancements

### 9. Music/Media Context

**Problem:** No awareness of currently playing media. Users dictating about songs or podcasts can't reference "this song" accurately.

**Proposed Solution:** Integrate with MediaRemote framework (already a dependency) to capture:
```swift
struct MediaContext: Codable {
    let trackName: String?
    let artistName: String?
    let albumName: String?
    let isPlaying: Bool
    let appName: String?          // Spotify, Apple Music, etc.
}
```

**Estimated Effort:** Low (1-2 hours) - MediaRemoteAdapter already integrated

---

### 10. Browser Tab Awareness

**Problem:** Only the active browser tab is captured. Other open tabs could provide broader context.

**Proposed Solution:** Capture list of open tab titles (not content):
```swift
struct BrowserContentContext: Codable {
    // Existing fields...
    let otherTabs: [String]?      // Titles of other open tabs
}
```

**Privacy Consideration:** Tab titles could reveal sensitive browsing - should be opt-in.

**Estimated Effort:** Medium (2-3 hours) - requires additional AppleScript

---

### 11. System State Context

**Problem:** No awareness of macOS system state that might affect dictation behavior.

**Proposed Solution:** Add `SystemContext` struct:
```swift
struct SystemContext: Codable {
    let isDoNotDisturbEnabled: Bool
    let isScreenSharing: Bool
    let connectedDisplays: Int
    let batteryLevel: Int?
    let isOnPower: Bool
}
```

**Use Case:** Adjust AI behavior when user is in a meeting (screen sharing) or low battery.

**Estimated Effort:** Low (1-2 hours)

---

## Implementation Priority Matrix

| Improvement | Impact | Effort | Privacy Risk | Recommended Priority |
|-------------|--------|--------|--------------|---------------------|
| Programming Language Detection | High | Medium | Low | **1st** |
| Enriched Calendar Context | High | Low | Medium | **2nd** |
| File Content Preview | High | Medium | Low | **3rd** |
| Clipboard History | Medium | Medium | High | 4th |
| Smarter Truncation | Medium | High | Low | 5th |
| Notification Context | Medium | High | Very High | 6th |
| Conversation History Improvements | Medium | Medium | Low | 7th |
| Git/Project Context | Medium | Medium-High | Low | 8th |
| Music/Media Context | Low | Low | Low | 9th |
| Browser Tab Awareness | Low | Medium | Medium | 10th |
| System State Context | Low | Low | Low | 11th |

---

## Architecture Considerations

### Adding New Context Types

When implementing any of these improvements, follow this pattern:

1. **Define Model**: Add fields to `AIContext.swift` or create new struct
2. **Create Service**: Implement data fetching service in `VoiceInk/Services/AIEnhancement/`
3. **Update Builder**: Inject service into `AIContextBuilder` and capture data
4. **Update Renderer**: Add XML tag rendering in `AIContextRenderer`
5. **Update Settings**: Add toggle in `AIContextSettings` and `ContextSettingsView`
6. **Update Prompts**: Document new tag usage in `AIPrompts.swift`

### Privacy Guidelines

For any new context source:
- **Low Privacy Risk**: Can be enabled by default (e.g., temporal, session)
- **Medium Privacy Risk**: Enabled in "Balanced" mode, toggle available (e.g., files, browser)
- **High Privacy Risk**: Opt-in only, disabled by default (e.g., calendar, clipboard history)
- **Very High Privacy Risk**: Explicit user consent required, clear warning (e.g., notifications)

### Performance Guidelines

- Heavy operations (file reading, AppleScript) should use timeouts (2-3 seconds max)
- Use caching via `ContextCacheManager` for expensive operations
- Run independent context captures in parallel via `TaskGroup`
- Respect token budgets via `TokenBudgetManager`

---

## Related Documentation

- `VoiceInk/Models/AIContext.swift` - Core context model
- `VoiceInk/Models/AIContextSettings.swift` - User preferences
- `VoiceInk/Services/AIEnhancement/AIContextBuilder.swift` - Context aggregation
- `VoiceInk/Services/AIEnhancement/AIContextRenderer.swift` - XML formatting
- `docs/AI_CONTEXT_AWARENESS_PLAN.md` - Original implementation plan
- `AGENTS.md` - AI Context System section

---

## Changelog

| Date | Change |
|------|--------|
| 2025-12-06 | Initial document created with 11 improvement opportunities |
| 2025-12-06 | Browser Content Support Expansion marked as completed |

---

*This document should be updated as improvements are implemented or new opportunities are identified.*
