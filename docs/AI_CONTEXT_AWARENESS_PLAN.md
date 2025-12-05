# AI Context Awareness Enhancement Plan

## Executive Summary

This plan transforms VoiceInk's AI context system from ad-hoc string concatenation into a **structured, extensible, and intelligent context engine**. The AI will receive comprehensive operational awareness including application context, temporal information, conversation continuity, and user-configurable context priorities.

## Part 1: Foundation - Structured Context System

### 1.1 Create `AIContext` Model

**File:** `VoiceInk/Models/AIContext.swift`

Comprehensive context object passed to AI enhancement.

```swift
struct AIContext: Codable {
    // Core content contexts
    let selectedText: ContextSection?
    let clipboard: ContextSection?
    let screenCapture: ScreenCaptureContext?
    let customVocabulary: [String]
    
    // NEW: Operational contexts
    let application: ApplicationContext?
    let temporal: TemporalContext
    let session: SessionContext
    let powerMode: PowerModeContext?
    let conversationHistory: ConversationContext?
    
    // Metadata
    let capturedAt: Date
    let contextVersion: String = "1.0"
}
```

### 1.2 Create `AIContextSettings` Model

**File:** `VoiceInk/Models/AIContextSettings.swift`

User-configurable settings for what context to include.

```swift
struct AIContextSettings: Codable {
    var includeClipboard: Bool = true
    var includeScreenCapture: Bool = true
    var includeSelectedText: Bool = true
    var includeApplicationContext: Bool = true
    var includeTemporalContext: Bool = true
    var includeConversationHistory: Bool = false    // Opt-in
    var maxConversationItems: Int = 3
    var conversationWindowMinutes: Int = 5
    
    // Priority order for truncation (lower = higher priority)
    var contextPriorities: [ContextType: Int] = [
        .selectedText: 1,
        .clipboard: 2,
        .screenCapture: 3,
        .conversationHistory: 4
    ]
}
```

## Part 2: Enhanced Context Capture

### 2.1 Enhance `ActiveWindowService`

**File:** `VoiceInk/PowerMode/ActiveWindowService.swift`

Add method to capture full application context including URL if browser.

### 2.2 Enhance `ScreenCaptureService`

**File:** `VoiceInk/Services/ScreenCaptureService.swift`

Return structured data (`ScreenCaptureResult`) instead of formatted string.

### 2.3 Create `ConversationHistoryService`

**File:** `VoiceInk/Services/AIEnhancement/ConversationHistoryService.swift`

Fetches recent transcriptions for conversation continuity (Opt-in).

## Part 3: Intelligent Token Management

### 3.1 Create `TokenBudgetManager`

**File:** `VoiceInk/Services/AIEnhancement/TokenBudgetManager.swift`

Manages context size to prevent API failures by truncating lower priority contexts.

## Part 4: Context Building & Rendering

### 4.1 Create `AIContextBuilder` Service

**File:** `VoiceInk/Services/AIEnhancement/AIContextBuilder.swift`

Orchestrates context gathering, applies settings, and enforces token budgets.

### 4.2 Create `AIContextRenderer`

**File:** `VoiceInk/Services/AIEnhancement/AIContextRenderer.swift`

Renders `AIContext` to XML for prompt injection.

## Part 5: Integration

### 5.1 Refactor `AIEnhancementService`

**File:** `VoiceInk/Services/AIEnhancement/AIEnhancementService.swift`

Replace existing string concatenation logic with `AIContextBuilder` and `AIContextRenderer`.

### 5.2 Update `AIPrompts.swift`

**File:** `VoiceInk/Models/AIPrompts.swift`

Update the template to document and reference new context sections.

### 5.3 Store Rich Context in Transcription

**File:** `VoiceInk/Models/Transcription.swift`

Add field `aiContextJSON` to store the full context for debugging.

## Part 6: Settings UI

### 6.1 Update AI Enhancement Settings

Add UI for configuring context behavior (toggles for each context type, conversation history settings).

---

## New Context Tags Reference

| Tag | Content | Example |
|-----|---------|---------|
| `<APPLICATION_CONTEXT>` | Active app, bundle ID, URL | `Active Application: Slack` |
| `<TEMPORAL_CONTEXT>` | Date, time, timezone | `Date: 2025-12-05 (Friday)` |
| `<SESSION_CONTEXT>` | Recording duration, model, language | `Recording Duration: 45s` |
| `<POWER_MODE>` | Active config name and match reason | `Config: Coding, Matched: app` |
| `<CURRENTLY_SELECTED_TEXT>` | User's text selection | (existing) |
| `<CLIPBOARD_CONTEXT>` | Clipboard contents | (existing) |
| `<CURRENT_WINDOW_CONTEXT>` | Window title + OCR text | (existing, enhanced) |
| `<CUSTOM_VOCABULARY>` | User dictionary | (existing) |
| `<RECENT_CONVERSATION>` | Last N transcriptions | `[1] Fixed the bug...` |
