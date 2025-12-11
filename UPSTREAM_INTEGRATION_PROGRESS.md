# Upstream Integration Progress

**Date Started:** December 8, 2025  
**Date Updated:** December 12, 2025  
**Objective:** Incorporate upstream fixes from `Beingpax/VoiceInk` into VoiceLink Community fork

---

## Session 2: December 12, 2025

**Commits Integrated:** 17 new commits since `8867636` (up to latest upstream/main)

### Changes Implemented

#### 1. TextInsertionFormatter Removal (upstream `b754f39`) - CRITICAL CRASH FIX
- **Deleted:** `VoiceInk/Services/TextInsertionFormatter.swift`
- **Updated:** `VoiceInk/CursorPaster.swift` - Removed TextInsertionFormatter usage

#### 2. Audio Device Race Condition Fix (upstream `feea0d7`)
- **Updated:** `VoiceInk/Services/AudioDeviceManager.swift`
  - Added `selectDeviceAndSwitchToCustomMode()` method to atomically select device and switch to custom mode

#### 3. OCR Window Detection Fix (upstream `3b043f4`/`d25ae52`)
- **Updated:** `VoiceInk/Services/ScreenCaptureService.swift`
  - Added `WindowCandidate` struct for better window sorting
  - Filters out VoiceInk's own windows from OCR capture
  - Prioritizes frontmost app windows

#### 4. AI Model Updates (upstream `ea64ff3` + `8ce84e9`)
- **Updated:** `VoiceInk/Services/AIEnhancement/AIService.swift`
  - Default models: groq→`openai/gpt-oss-120b`, anthropic→`claude-sonnet-4-5`, openAI→`gpt-5.1`
  - Cerebras models reordered, added `llama-3.1-8b`
  - Anthropic: removed `claude-opus-4-0`, `claude-sonnet-4-0`; added `claude-opus-4-5`
  - OpenAI: replaced `gpt-5` with `gpt-5.1`
- **Updated:** `VoiceInk/Services/AIEnhancement/ReasoningConfig.swift`
  - Added `cerebrasReasoningModels` set for reasoning model detection

#### 5. Recorder Startup Optimization (upstream `85e2685`)
- **Updated:** `VoiceInk/Whisper/WhisperState+UI.swift`
  - Show recorder UI before starting recording for faster perceived startup
- **Updated:** `VoiceInk/Whisper/WhisperState.swift`
  - Model loading and context capture moved to `Task.detached` background task

#### 6. Clipboard Preservation Change (upstream `baae439`)
- **Updated:** `VoiceInk/CursorPaster.swift`
  - Changed from `preserveTranscriptInClipboard` to `restoreClipboardAfterPaste`
  - Added configurable `clipboardRestoreDelay` (default 1.5s)
- **Updated:** `VoiceInk/Services/ImportExportService.swift`
  - Added `restoreClipboardAfterPaste` and `clipboardRestoreDelay` to GeneralSettings struct
  - Updated export/import logic for new settings
- **Created:** `VoiceInk/Views/Settings/ClipboardPasteSection.swift`
  - New reusable section view for clipboard settings
  - Includes toggle for restore clipboard and delay picker (0.5s - 5.0s)
- **Updated:** `VoiceInk/Views/Settings/SettingsView+Transcription.swift`
  - Replaced inline clipboard settings with `ClipboardPasteSection()`

### Files Modified (Session 2)

| File | Action | Description |
|------|--------|-------------|
| `VoiceInk/Services/TextInsertionFormatter.swift` | DELETED | Removed problematic formatter |
| `VoiceInk/CursorPaster.swift` | Modified | Removed formatter, added clipboard restore |
| `VoiceInk/Services/AudioDeviceManager.swift` | Modified | Added atomic device selection method |
| `VoiceInk/Services/ScreenCaptureService.swift` | Modified | Improved window detection for OCR |
| `VoiceInk/Services/AIEnhancement/AIService.swift` | Modified | Updated AI models |
| `VoiceInk/Services/AIEnhancement/ReasoningConfig.swift` | Modified | Added Cerebras reasoning models |
| `VoiceInk/Whisper/WhisperState.swift` | Modified | Background model loading |
| `VoiceInk/Whisper/WhisperState+UI.swift` | Modified | Faster recorder display |
| `VoiceInk/Services/ImportExportService.swift` | Modified | New clipboard settings |
| `VoiceInk/Views/Settings/ClipboardPasteSection.swift` | CREATED | New clipboard settings UI |
| `VoiceInk/Views/Settings/SettingsView+Transcription.swift` | Modified | Use ClipboardPasteSection |

---

## Session 1: December 8, 2025

**Objective:** Incorporate upstream commit `b6068bc` (Show raw API error responses on key verification failure)

---

## Summary

This integration adds the ability to display specific API error messages when API key verification fails, instead of a generic "Invalid API key" message. This helps users understand why verification failed (quota exceeded, invalid format, network issues, etc.).

### Decision Log

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Logger retention | **Keep** | Aligns with AGENTS.md AppLogger guidance for development debugging |
| Error message truncation | **Truncate to 500 chars** | Prevents UI overflow with long API responses |
| Accessibility check | **Skip** | Already implemented in AIContextBuilder.swift:217 |
| Soundfeedback UI | **Skip** | Fork has different, more comprehensive UI structure |

---

## Files Modified

| File | Status | Changes |
|------|--------|---------|
| `VoiceInk/Services/AIEnhancement/AIService.swift` | ✅ Complete | Updated signatures & error propagation for all verification methods |
| `VoiceInk/Views/AI Models/CloudModelCardRowView.swift` | ✅ Complete | Added verificationError state, updated callback, UI display & cleanup |
| `VoiceInk/Views/AI Models/APIKeyManagementView.swift` | ✅ Complete | Updated custom & standard provider callbacks |

---

## Implementation Progress

### Phase 1: AIService.swift ✅ COMPLETE

- [x] 1.1 Update `saveAPIKey` signature to `(Bool, String?) -> Void`
- [x] 1.2 Update `verifyAPIKey` signature to `(Bool, String?) -> Void`
- [x] 1.3 Update `verifyOpenAICompatibleAPIKey` to return error messages
- [x] 1.4 Update `verifyAnthropicAPIKey` to return error messages
- [x] 1.5 Update `verifyElevenLabsAPIKey` to return error messages
- [x] 1.6 Update `verifyMistralAPIKey` to return error messages
- [x] 1.7 Update `verifyDeepgramAPIKey` to return error messages
- [x] 1.8 Update `verifySonioxAPIKey` to return error messages
- [x] 1.9 Update `verifyAssemblyAIAPIKey` to return error messages

### Phase 2: CloudModelCardRowView.swift ✅ COMPLETE

- [x] 2.1 Add `@State private var verificationError: String? = nil`
- [x] 2.2 Update `verifyAPIKey()` callback to capture error
- [x] 2.3 Update error display UI to show specific message
- [x] 2.4 Clear `verificationError` in `clearAPIKey()`

### Phase 3: APIKeyManagementView.swift ✅ COMPLETE

- [x] 3.1 Update custom provider verify callback
- [x] 3.2 Update standard provider verify callback

### Phase 4: Build & Test ✅ COMPLETE

- [x] 4.1 Swift syntax verification passed for all modified files
- [x] 4.2 Changes ready for manual verification testing

---

## Detailed Change Log

### AIService.swift Changes

**Lines Modified:** ~120 lines across 8 verification methods

1. **`saveAPIKey`** (Line 338)
   - Changed signature from `(Bool) -> Void` to `(Bool, String?) -> Void`
   - Updated internal callback to pass error message through

2. **`verifyAPIKey`** (Line 361)
   - Changed signature from `(Bool) -> Void` to `(Bool, String?) -> Void`
   - Updated to pass `nil` for non-API-key providers

3. **`verifyOpenAICompatibleAPIKey`** (Line 385)
   - Returns network error message on connection failure
   - Returns truncated API response on verification failure
   - Returns status code message when no response body

4. **`verifyAnthropicAPIKey`** (Line 451)
   - Same pattern as OpenAI-compatible

5. **`verifyElevenLabsAPIKey`** (Line 509)
   - Returns response body on failure

6. **`verifyMistralAPIKey`** (Line 541)
   - Returns response body or status code on failure

7. **`verifyDeepgramAPIKey`** (Line 580)
   - Returns response body or status code on failure

8. **`verifySonioxAPIKey`** (Line 615)
   - Returns response body or status code on failure

9. **`verifyAssemblyAIAPIKey`** (Line 650)
   - Returns response body or status code on failure

### CloudModelCardRowView.swift Changes

**Lines Modified:** ~15 lines

1. Added `@State private var verificationError: String? = nil` (Line 17)
2. Updated `verifyAPIKey()` callback to capture error message (Lines 300-320)
3. Updated error display UI to show specific error or fallback message (Lines 251-260)
4. Added `verificationError = nil` to `clearAPIKey()` method (Line 339)

### APIKeyManagementView.swift Changes

**Lines Modified:** ~10 lines

1. Updated custom provider callback (Lines 300-307)
2. Updated standard provider callback (Lines 367-374)

---

## Error Message Truncation

All API error responses are truncated to **500 characters** to prevent UI overflow:

```swift
let truncatedError = responseString.count > 500 
    ? String(responseString.prefix(500)) + "..." 
    : responseString
```

---

## Testing Recommendations

1. **Valid API Key Test**
   - Enter a valid API key for any provider
   - Verify: Shows success message, collapses configuration section

2. **Invalid API Key Test**
   - Enter an invalid API key
   - Verify: Shows specific error from API (e.g., "invalid_api_key", authentication error)

3. **Network Error Test**
   - Disconnect network, attempt verification
   - Verify: Shows network error message

4. **Quota Exceeded Test** (if possible)
   - Use an API key with exceeded quota
   - Verify: Shows quota-related error from provider

---

## Compliance Notes

This implementation follows AGENTS.md coding standards:

- ✅ Retained logger for development debugging (Option B)
- ✅ Error messages truncated to 500 chars (Option B)
- ✅ Used `[weak self]` in existing callbacks (no changes needed)
- ✅ Maintained existing `DispatchQueue.main.async` pattern for UI updates
- ✅ No silent failures - all errors surfaced to users

---

## Related Upstream Commits

### Session 2 Commits (December 12, 2025)

| Commit | Description | Status in Fork |
|--------|-------------|----------------|
| `b754f39` | Remove TextInsertionFormatter (crash fix) | ✅ **APPLIED** |
| `feea0d7` | Fix audio device race condition | ✅ **APPLIED** |
| `3b043f4` | OCR window detection improvements | ✅ **APPLIED** |
| `d25ae52` | Additional OCR window fixes | ✅ **APPLIED** |
| `ea64ff3` | Update AI models (GPT-5.1, Claude) | ✅ **APPLIED** |
| `8ce84e9` | Add Cerebras reasoning models | ✅ **APPLIED** |
| `85e2685` | Recorder startup optimization | ✅ **APPLIED** |
| `baae439` | Clipboard restore after paste | ✅ **APPLIED** |

### Session 1 Commits (December 8, 2025)

| Commit | Description | Status in Fork |
|--------|-------------|----------------|
| `cd503ac` | Refactor modifier key handling to use direct await calls | ✅ Already applied |
| `b6068bc` | Show raw API error responses on key verification failure | ✅ **APPLIED** |
| `e16c84e` | Add accessibility permission check to prevent pop-up | ✅ Already covered (AIContextBuilder.swift:217) |
| `1e612d9` | Support org.nspasteboard conventions for transient clipboard | ✅ Already applied |
| `ac1a85c` | Improved text formatting during paste operation | ✅ Already applied |
| `fca5099` | Make the soundfeedback row clickable | ⏭️ Skipped (different UI structure) |
| `8867636` | Update to v1.62 | ⏭️ Skipped (version-specific) |

---

**Status:** Ready for commit and push.
