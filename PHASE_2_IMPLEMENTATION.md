# Phase 2 Implementation Checklist

Scope: Medium/low review issues plus structural refactors (large file splits) and optional hardening tasks.

## Status
- [ ] Not started
- [x] In progress
- [ ] Ready for review
- [ ] Complete

## Review Phase 3/4: Medium + Low Issues
### MEDIUM-001: Silent `try?` without logging
- [x] `VoiceInk/Services/AIEnhancement/AIService.swift`
- [x] `VoiceInk/Services/TranscriptionAutoCleanupService.swift`
- [x] `VoiceInk/Services/QuickRulesService.swift`
- [x] `VoiceInk/Whisper/WhisperState.swift`
- [x] `VoiceInk/Whisper/WhisperState+Parakeet.swift`
- [x] `VoiceInk/TTS/ViewModels/TTSViewModel+BatchProcessing.swift`
- [x] `VoiceInk/TTS/Services/TranscriptionRecorder.swift`
- [x] `VoiceInk/ViewModels/TranscriptionHistoryViewModel.swift`
- [x] `VoiceInk/PowerMode/PowerModeConfig.swift`
- [x] `VoiceInk/CustomSoundManager.swift`

### MEDIUM-002: URL matching logic bug
- [x] `VoiceInk/PowerMode/PowerModeConfig.swift` precise domain matching

### MEDIUM-003: Timer callback calls `@MainActor` method
- [x] `VoiceInk/Notifications/NotificationManager.swift` use Task { @MainActor }

### MEDIUM-004: Dead code / unreachable guard
- [x] `VoiceInk/TTS/ViewModels/TTSViewModel+SpeechGeneration.swift` remove unreachable guard

### MEDIUM-005: Unsafe pointer access
- [x] `VoiceInk/Whisper/LibWhisper.swift` avoid pointer escaping `withUnsafeBufferPointer`

### MEDIUM-006: Force unwraps in production
- [x] `VoiceInk/Whisper/LibWhisper.swift` safe prompt handling
- [x] `VoiceInk/Services/AIEnhancement/FocusedElementService.swift` avoid force casts
- [x] `VoiceInk/TTS/ViewModels/TTSTranscriptionViewModel.swift` remove force unwrap (moved)

### MEDIUM-007: Model not unloaded when switching
- [x] `VoiceInk/Whisper/WhisperState+LocalModelManager.swift` allow model switching

### MEDIUM-008: handleModelDownloadError swallows errors
- [x] `VoiceInk/Whisper/WhisperState+LocalModelManager.swift` log/show failures

### LOW-001: Deprecated API usage
- [x] `VoiceInk/Whisper/WhisperPrompt.swift` remove `synchronize()`
- [x] `VoiceInk/PowerMode/PowerModePopover.swift` update `onChange` signature

### LOW-002: Code style issues
- [x] `VoiceInk/Models/PredefinedPrompts.swift` remove force unwraps
- [x] Large file refactors (tracked under Structural Refactors)
- [x] Duplicate `AuthorizationHeader` pattern removal (verify coverage)
- [x] PowerMode views hardcoded strings localized
- [x] `VoiceInk/PowerMode/EmojiPickerView.swift` remove empty conditional blocks

### LOW-003: DispatchQueue.main.asyncAfter in SwiftUI
- [x] `VoiceInk/PowerMode/EmojiPickerView.swift` migrate to Task-based delay

### LOW-004: Missing documentation
- [x] `VoiceInk/TTS/ViewModels/TTSTranscriptionViewModel.swift` document `transcribeAudioFile`
- [x] Add doc comments to complex methods identified during refactors

## 2025-12-21 Comprehensive Audit Cleanup
- [x] Remove build logs and screenshots
- [x] Remove obsolete documentation files

## Structural Refactors (from LOW-002: large file sizes)
### TTSViewModel Split
- [x] Extract `TTSTranscriptionViewModel`
- [x] Extract `TTSPlaybackViewModel`
- [x] Extract `TTSHistoryViewModel`
- [x] Extract `TTSSpeechGenerationViewModel`
- [x] Extract `TTSVoicePreviewViewModel` (preview domain)
- [x] Move preview state + logic into the preview view model
- [x] Wire preview environment object into the TTS workspace + inspector
- [x] Identify remaining domain boundaries (settings, import/export)
- [x] Create new view model types (settings, import/export)
- [x] Move published state + logic into new view models (settings, import/export)
- [x] Define shared data flow (dependencies, callbacks, bindings)
- [x] Update TTS workspace views to use new view models (playback + history + generation)
- [x] Update tests (or add new ones) for split responsibilities
- [x] Verify persistence behaviors (settings, history cache, snippets, rules)
- [x] Verify playback/generation still coordinated correctly
- [x] Remove dead code from TTSViewModel

### TTSWorkspaceView Split
- [x] Extract layout shell into `TTSWorkspaceLayoutView`
- [x] Move `TTSAboutSheetView` into dedicated file
- [x] Identify remaining subview boundaries (composer, playback, inspector, panels)
- [x] Extract additional subviews into dedicated files
- [x] Update previews and view wiring

## WhisperState Refactor (Optional, Non-review)
- [x] Extract recording/transcription flow into `WhisperState+Recording.swift`
- [ ] Identify responsibilities to extract (recording, transcription, model management, UI state)
- [ ] Create new helper services/view models/actors as needed
- [ ] Move state + logic into new types with clear boundaries
- [ ] Update WhisperState to orchestrate dependencies
- [ ] Update call sites and injected dependencies
- [ ] Verify lifecycle cleanup (tasks, timers, observers) in new types
- [ ] Update tests or add missing coverage

## Centralize App Settings (Non-review)
- [x] Audit current settings reads/writes (non-TTS)
- [x] Design AppSettings (or equivalent) abstraction
- [x] Migrate to centralized settings access
- [x] Update change notifications
- [x] Remove redundant UserDefaults usage where possible (non-TTS)
- [x] Migrate remaining TTS UserDefaults usage (managed provisioning + legacy keychain migration)

## Standardize Service Naming (Non-review)
- [x] Identify ambiguous/inconsistent service names
- [x] Rename services (e.g., ElevenLabsService -> ElevenLabsTTSService)
- [x] Update references and documentation
- [x] Verify public API compatibility

## Split Large Views (>500 lines) (Non-review)
- [x] PowerModeConfigView+Sections.swift (extract sections)
- [x] AudioInputSettingsView.swift (extract subviews)
- [x] OnboardingPermissionsView.swift (extract permission sections)
- [x] Update previews and view wiring

## File Size Compliance (Non-review)
- [x] Split `TTSSpeechGenerationViewModel` into focused extension files

## Entitlements and Security (Non-review)
- [x] Enable App Sandbox in `VoiceInk.entitlements`
- [x] Review/remove `network.server` entitlement if unused
- [ ] Verify runtime behavior in sandboxed mode

## Build & Dependency Hygiene (Non-review)
- [x] Resolve AXSwift identity conflict by vendoring `SelectedTextKit` locally and updating its AXSwift URL
- [x] Remove stale `Package.resolved` files inside the vendored `SelectedTextKit` to avoid old URL pins

## Quality Gates
- [x] Build succeeds (unsigned build: `CODE_SIGNING_ALLOWED=NO`)
- [x] Targeted tests updated or added
- [ ] No new warnings
- [ ] Docs updated (if public API changed)

## Notes / Decisions
- [x] AppSettings migration now covers non-TTS + TTS managed provisioning and legacy key migrations
- [x] Deferred: WhisperState deep refactor tasks + sandbox runtime verification + test/warning gates pending after structural splits
- [x] Targeted test run (KeychainManagerTests, AIServiceTests, TTSServiceTests, TTSViewModelTests) passed via `xcodebuild` with derived data under `build/DerivedData`
- [ ] Full test sweep with integration/stress suites timed out due to long-running model downloads (FluidAudio/Parakeet); rerun locally after pre-downloading models
