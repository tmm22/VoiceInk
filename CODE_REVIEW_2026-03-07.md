# Code Review Report: VoiceInk

**Date:** March 7, 2026  
**Reviewer:** Codex  
**Scope:** Performance, security, and reduction review of recent transcription, AI enhancement, Power Mode, and history-view code paths

---

## Executive Summary

This review focused on six concrete issues surfaced during a targeted code audit:

1. Sensitive AI system prompts were being logged publicly.
2. Transcript and enhanced text were being logged publicly.
3. Active browser URLs were being logged publicly.
4. `LOCAL_BUILD` downgraded secret storage to plaintext `UserDefaults`.
5. Cloud transcription providers bypassed the hardened networking layer and loaded large uploads fully into memory.
6. The history UI had duplicate implementations that were already drifting apart.

All six issues were fixed in the same pass. The remediation concentrated on privacy-safe logging, Keychain-only secret handling, streamed audio uploads over hardened sessions, and reduction of duplicate UI implementations. The pass also added explicit guidance to `AGENTS.md` so these patterns are less likely to recur.

---

## Findings Summary

| Priority | Finding | Status |
|----------|---------|--------|
| P1 | Sensitive AI context logged publicly | Fixed |
| P1 | Transcript and enhanced text logged publicly | Fixed |
| P1 | Active browser URLs exposed in logs | Fixed |
| P1 | `LOCAL_BUILD` stored secrets in plaintext | Fixed |
| P2 | Cloud upload path bypassed hardened networking and duplicated audio in RAM | Fixed |
| P3 | Duplicate history view implementations were drifting | Fixed |

---

## Detailed Findings and Resolutions

### P1. Sensitive AI context logged publicly

**Problem**  
`AIEnhancementService+Requests.swift` logged the full AI system prompt with `privacy: .public`. In VoiceInk, that prompt can contain clipboard contents, browser content, focused-element text, calendar context, or screen-derived text.

**Resolution**  
The log statement now records metadata only: provider, model, and character counts. The user payload is no longer written to OSLog.

**Files Updated**
- `VoiceInk/Services/AIEnhancement/AIEnhancementService+Requests.swift`

### P1. Transcript and enhanced text logged publicly

**Problem**  
The transcription pipeline logged raw transcript text and post-processed/enhanced text to production OSLog, creating a privacy regression for dictated content.

**Resolution**  
The reviewed paths now log only metadata such as character counts. This change was applied across the primary and recording-specific transcription flows, raw-transcription processing, and the output filter.

**Files Updated**
- `VoiceInk/Whisper/WhisperState.swift`
- `VoiceInk/Whisper/WhisperState+Recording.swift`
- `VoiceInk/Whisper/Processors/TranscriptionProcessor.swift`
- `VoiceInk/Services/TranscriptionOutputFilter.swift`

### P1. Active browser URLs exposed in logs

**Problem**  
`BrowserURLService.swift` logged successful and failed URL retrievals with the active tab URL available in log payloads.

**Resolution**  
The logging now records only browser identity and execution status. Active URLs are still returned to the feature, but they are no longer persisted to logs.

**Files Updated**
- `VoiceInk/PowerMode/BrowserURLService.swift`

### P1. `LOCAL_BUILD` downgraded secrets to plaintext storage

**Problem**  
`KeychainService.swift` redirected secrets to `UserDefaults` when `LOCAL_BUILD` was enabled. Because this shared layer backs API key and license storage, the local-build workflow wrote secrets to plaintext on disk.

**Resolution**  
`KeychainService` now remains Keychain-only for local builds. When local entitlements cannot support syncable/shared items, the service disables syncable storage instead of switching backends.

**Files Updated**
- `VoiceInk/Services/KeychainService.swift`

### P2. Cloud upload path bypassed the hardened networking layer

**Problem**  
Several cloud transcription providers used `URLSession.shared` and loaded full recordings into memory with `Data(contentsOf:)`, even though the codebase already had an ephemeral session abstraction and async file loading utilities. This created both privacy and memory-scaling issues for longer recordings.

**Resolution**  
- Added a shared streamed multipart upload helper to `CloudTranscriptionBase`.
- Switched providers to `SecureURLSession.makeEphemeral()`.
- Used `upload(for:fromFile:)` for raw uploads.
- Built multipart request bodies in a temporary file and uploaded that file instead of duplicating the recording in RAM.
- Removed the now-redundant multipart builder utility.

**Files Updated**
- `VoiceInk/Services/CloudTranscription/CloudTranscriptionBase.swift`
- `VoiceInk/Services/CloudTranscription/DeepgramTranscriptionService.swift`
- `VoiceInk/Services/CloudTranscription/ElevenLabsTranscriptionService.swift`
- `VoiceInk/Services/CloudTranscription/SonioxTranscriptionService.swift`
- `VoiceInk/Services/CloudTranscription/OpenAICloudTranscriptionService.swift`
- `VoiceInk/Services/CloudTranscription/OpenAICompatibleTranscriptionService.swift`
- `VoiceInk/Services/CloudTranscription/GroqTranscriptionService.swift`
- `VoiceInk/Services/CloudTranscription/ZAITranscriptionService.swift`
- `VoiceInk/Services/CloudTranscription/MistralTranscriptionService.swift`
- Removed: `VoiceInk/Services/CloudTranscription/MultipartFormDataBuilder.swift`

### P3. Duplicate history view implementations were drifting

**Problem**  
`HistoryTranscriptionView` and `TranscriptionHistoryLegacyView` duplicated the real history screen instead of forwarding to it, which meant fixes could land in one history UI while silently missing the others.

**Resolution**  
The history surface now has one canonical implementation: `TranscriptionHistoryView`. The legacy entry points were reduced to thin compatibility wrappers/typealiases, preserving call sites without keeping forked view bodies.

**Files Updated**
- `VoiceInk/Views/History/HistoryTranscriptionView.swift`
- `VoiceInk/Views/TranscriptionHistoryLegacyView.swift`

---

## Documentation Updates

To prevent recurrence, `AGENTS.md` was updated with explicit guidance covering:

- Single-source-of-truth implementations for screens and services
- Sensitive-data logging rules and examples
- Keychain-only credential storage, including `LOCAL_BUILD`
- Streamed large-audio uploads through ephemeral sessions

This documentation now reflects the patterns reinforced by this review and remediation pass.

---

## Verification

### Build Validation

- Successful command:

```bash
xcodebuild -project VoiceInk.xcodeproj -scheme VoiceInk -configuration Debug -destination 'platform=macOS' CODE_SIGN_IDENTITY='' CODE_SIGNING_REQUIRED=NO build
```

### Patch Hygiene

- `git diff --check` completed successfully.

### Pattern Sweeps

Follow-up searches confirmed:

- No remaining `URLSession.shared` usage in reviewed cloud transcription providers
- No `Data(contentsOf:)` upload-body construction in reviewed cloud transcription providers
- The previous explicit sensitive log strings were removed from the reviewed AI enhancement, transcription, output-filter, and browser URL paths

### Notes

- The build still emits unrelated pre-existing warnings, including `SelectedTextKit` import warnings and several existing Swift 6 migration warnings. These were outside the scope of this review pass.
- A small unrelated compile repair was made in `VoiceInk/Views/TranscriptionCard.swift` to restore a missing toggle style so full validation could complete.

---

## Outcome

This review pass materially improved privacy, reduced credential-handling risk, lowered upload memory pressure for cloud transcription, and simplified the history UI maintenance surface. The resulting code is safer in production and more resistant to recurrence because the review expectations were also codified in `AGENTS.md`.
