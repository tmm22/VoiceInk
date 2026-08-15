# Codebase Alignment Cleanup Plan

Date: 2026-03-14
Status: In Progress

## Goal

Remove remaining redundant or dead code, keep the codebase aligned with the historical review guidance, and maintain the current file-splitting standards without introducing churn where the source tree is already compliant.

## Current Baseline

- Production Swift files are under the 500-line target.
- Oversized files are currently concentrated in tests:
  - `VoiceInkTests/TTS/TTSServiceTests.swift`
  - `VoiceInkTests/TTS/TTSViewModelTests.swift`
  - `VoiceInkTests/Services/CloudTranscriptionServiceTests.swift`
  - `VoiceInkTests/Transcription/WhisperStateTests.swift`
- History UI duplication is reduced to one canonical implementation plus compatibility wrappers.
- Shared `AuthorizationService` exists and is now the canonical auth-header path for TTS and OpenAI-backed TTS utility services.

## Completed In This Pass

- Migrated remaining TTS/OpenAI utility services to `AuthorizationService`.
- Removed duplicated `authorizationHeader()` helpers from:
  - `OpenAITTSService`
  - `GoogleTTSService`
  - `OpenAITranscriptionService`
  - `OpenAISummarizationService`
  - `OpenAITranslationService`
  - `TranscriptCleanupService`
  - `TranscriptInsightsService`
- Removed unused managed-credential state in those services.
- Shared one `AuthorizationService` instance through `TTSViewModel` wiring.
- Marked `MiniWindowManager` as `@MainActor`.
- Replaced several production `print(...)` leftovers with `AppLogger`.
- Removed preview `try!` usage in:
  - `KeyboardShortcutCheatSheet`
  - `KeyboardShortcutsListView`
- Verified the project still builds.

## Remaining Work

### Phase 1: Main-Actor Cleanup

- Replace remaining redundant `MainActor.run` usage inside `@MainActor` types where direct state mutation is valid.
- Replace runtime `DispatchQueue.main.async/asyncAfter` calls in core application paths with `Task { @MainActor ... }` or `Task.sleep` where appropriate.
- Prioritize:
  - `WhisperState.swift`
  - `WhisperState+UI.swift`
  - `Recorder.swift`
  - `CursorPaster.swift`

### Phase 2: Dead-Code and Compatibility Audit

- Confirm deprecated wrappers are still required.
- Keep only wrappers that preserve active call sites.
- Audit legacy migration helpers and remove any that are no longer referenced in runtime or migration paths.

### Phase 3: Test File Splitting

- Split oversized test files by concern, not arbitrarily by line count.
- Suggested breakdown:
  - service behavior
  - error handling
  - concurrency and cancellation
  - regression coverage

### Phase 4: Enforcement

- Add a lightweight audit script or CI check for:
  - production `print(...)`
  - preview `try!`
  - `ObservableObject` without `@MainActor`
  - Swift files over 500 lines
  - targeted review-pattern regressions

## Verification Standard

- `git diff --check`
- targeted `rg` sweeps for banned patterns
- `xcodebuild -project VoiceInk.xcodeproj -scheme VoiceInk -configuration Debug -destination 'platform=macOS' CODE_SIGN_IDENTITY='' CODE_SIGNING_REQUIRED=NO build`

## Notes

- Existing test-only `DispatchQueue.main.asyncAfter` usage is acceptable for now and should not block runtime cleanup.
- Current build still emits the pre-existing unsigned-entitlements warning when built without code signing.
