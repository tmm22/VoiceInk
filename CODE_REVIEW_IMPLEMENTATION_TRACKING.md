# Code Review Implementation Tracking

Date: 2026-01-04

This file tracks the concrete changes applied to implement the latest code review recommendations and to prevent loss of context.

## Must Fix

- Remove `@MainActor` from `deinit` in `AudioPlayerService`.
  - File: `VoiceInk/TTS/Services/AudioPlayerService.swift`
  - Change: `@MainActor deinit` -> `deinit` (direct cleanup only)
  - Status: Completed

## Should Fix

- Replace `DispatchQueue.main` with `Task { @MainActor ... }` in runtime UI logic in `VoiceInk.swift`.
  - File: `VoiceInk/VoiceInk.swift`
  - Changes:
    - Replaced `DispatchQueue.main.async { ... }` in storage warning alert with `Task { @MainActor ... }`.
    - Replaced `DispatchQueue.main.asyncAfter` when posting `openFileForTranscription` with `Task.sleep` under `@MainActor`.
    - Replaced `DispatchQueue.main.async` in `WindowAccessor.makeNSView` with `Task { @MainActor ... }`.
  - Status: Completed

- Clarify MainActor isolation in `PromptDetectionService` and remove redundant `MainActor.run`.
  - File: `VoiceInk/Services/PromptDetectionService.swift`
  - Changes:
    - Annotated `applyDetectionResult` and `restoreOriginalSettings` with `@MainActor` and removed `await MainActor.run`.
  - Status: Completed

## Nice to Have / Follow-ups

- Continue migrating remaining `DispatchQueue.main.async/asyncAfter` calls in runtime code to `Task { @MainActor ... }` where appropriate. Tests may continue using `DispatchQueue`.
  - Completed in this pass:
    - `VoiceInk/Services/LastTranscriptionService.swift` (paste timing)
    - `VoiceInk/Services/DictionaryImportExportService.swift` (panels and alerts)
    - `VoiceInk/CursorPaster.swift` (paste timing and clipboard restore)
    - `VoiceInk/Services/AnnouncementsService.swift` (delayed initial fetch and UI dispatch)
    - `VoiceInk/Utilities/AppSettings.swift` (notifyChange crossing threads)
    - `VoiceInk/TTS/Views/TextEditorView.swift` (auto-focus timing)
    - `VoiceInk/Services/ImportExportService.swift` (panels/alerts)
    - `VoiceInk/Services/TranscriptionExportService.swift` (notification dispatch)
    - `VoiceInk/Services/AudioDeviceManager.swift` (global listener → @MainActor Task)
    - `VoiceInk/Views/AudioPlayerView.swift` (UI message timeouts)
    - `VoiceInk/Services/DictionaryImportExportService.swift` (alert dispatch fix)
  - Remaining to consider (non-exhaustive): `Views/*` where UI timing is used.
  - Status: Partially Completed

## Verification

- Compiles under Swift concurrency rules without `@MainActor deinit` violations.
- FastConformer and SenseVoice tensor shapes already use explicit `NSNumber` elements; no changes needed.
- Runtime `DispatchQueue.main.async/asyncAfter` calls migrated where practical in this pass. Remaining usages primarily exist in SwiftUI view timing and tests; acceptable but marked for future cleanup.

## Notes

- This tracking file is temporary and can be removed after merge once the PR description captures these changes.
