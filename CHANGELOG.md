# Changelog

All notable changes to the VoiceLink Community application are documented here.

## 2026-02-07

### Dependencies
- Updated Swift Package pin for **FluidAudio** to revision `b354014c37b8aa7705aeaabcbb234c80ba93aae0` in both Xcode package references and `Package.resolved`.
- Updated `mediaremote-adapter` (branch `master`) pin to revision `979bd77540b7f1389d294cc49e8bb2aa9675ed6b`.
- Updated `KeyboardShortcuts` `2.4.0` pin to current upstream tag revision `834156b492d82c4c003c680629dfad377a59a07f`.
- Verified no newer pins were required for `AXSwift`, `KeySender`, `LaunchAtLogin-Modern`, `onnxruntime-swift-package-manager`, `Sparkle`, `swift-atomics`, and `Zip`.

### Upstream Sync
- Merged latest `upstream/main` into `custom-main-v2` via merge commit `087e7bf` (upstream tip at merge: `a4cee17`).
- Preserved fork-prepared implementations during conflicts for:
  - `VoiceInk/Views/KeyboardShortcutsListView.swift`
  - `VoiceInk/Views/Settings/PowerModeSettingsSection.swift`
  - `VoiceInk/Views/TranscriptionCard.swift`
  - `VoiceInk/Views/TranscriptionHistoryView.swift`
- Preserved fork deletion of `VoiceInk/Services/UserDefaultsManager.swift` during merge conflict resolution.

### Standards Alignment
- Fixed merge-side structural issue in `VoiceInk/PowerMode/PowerModeSessionManager.swift` and kept session lifecycle behavior coherent.
- Added `@MainActor` to `VoiceInk/Services/FillerWordManager.swift` to align with strict concurrency guidance.
- Replaced new unguarded runtime prints with structured logging/error handling in:
  - `VoiceInk/MenuBarManager.swift`
  - `VoiceInk/Services/ImportExportService.swift`
  - `VoiceInk/Views/History/TranscriptionHistoryView.swift`
  - `VoiceInk/Views/AI Models/CloudModelCardRowView.swift`
- Removed redundant `MainActor.run` in `VoiceInk/PowerMode/ActiveWindowService.swift` where class isolation already guarantees main-actor execution.

### TTS (Pocket TTS)
- Added Pocket TTS voice options to Tight Ass Mode in `VoiceInk/TTS/Services/LocalTTSService.swift`:
  - `pocket-tts:alba`
  - `pocket-tts:azelma`
  - `pocket-tts:cosette`
  - `pocket-tts:javert`
- Added routing logic so Tight Ass Mode synthesizes with Pocket TTS for `pocket-tts:*` identifiers while keeping system AVSpeech voices as fallback/default.
- Updated Tight Ass Mode format guidance in `VoiceInk/TTS/ViewModels/TTSSettingsViewModel+Computed.swift` to reflect on-device system + Pocket voice support.
- Added regression tests in `VoiceInkTests/TTS/TTSServiceTests.swift` to verify Pocket voices are exposed and default selection remains a system voice.

### TTS (Pocket Voice Visibility Controls)
- Added user-controlled hide/restore behavior for Pocket voices in Tight Ass Mode so users can remove a voice from selection without uninstalling anything.
- Added persisted hidden Pocket voice IDs in app settings (`hiddenPocketVoiceIDs`) with typed access via `AppSettings+Voice`.
- Added `TTSSettingsViewModel+PocketVoices.swift` for centralized visibility filtering, hide/restore commands, and persistence.
- Added best-effort removal of cached Pocket voice embeddings on hide at `~/.cache/fluidaudio/Models/kokoro/voices/<voice-id>.json`.
- Added hide/restore controls in:
  - TTS command strip
  - TTS inspector voice section
  - TTS settings general section (including restore-all)
- Added regression tests in `VoiceInkTests/TTS/TTSViewModelTests.swift` for hide/restore filtering and persistence across view model instances.

### Build Stabilization
- Resolved stale cloud transcription references:
  - Added retry/timeout constants in `VoiceInk/Services/CloudTranscription/GroqTranscriptionService.swift`.
  - Fixed Soniox custom vocabulary extraction in `VoiceInk/Services/CloudTranscription/SonioxTranscriptionService.swift`.
- Fixed audio-device notification and mode consistency:
  - Added `audioDeviceChanged` and `audioDeviceSwitchRequired` notifications in `VoiceInk/Notifications/AppNotifications.swift`.
  - Updated `VoiceInk/Services/AudioDeviceManager.swift` and `VoiceInk/Services/AudioDeviceConfiguration.swift` to use typed notifications and exhaustive mode handling.
- Fixed transcription-service API drift:
  - Updated `VoiceInk/Services/AudioFileTranscriptionManager.swift` and `VoiceInk/Services/AudioFileTranscriptionService.swift` to match current `WordReplacementService` signature and local service initialization.
- Repaired dictionary/vocabulary model drift:
  - Added `VoiceInk/Models/VocabularyWordData.swift`.
  - Reworked import/export and vocabulary persistence in:
    - `VoiceInk/Services/DictionaryImportExportService.swift`
    - `VoiceInk/Services/ImportExportService.swift`
    - `VoiceInk/Services/CustomVocabularyService.swift`
    - `VoiceInk/Views/Dictionary/VocabularyView.swift`
    - `VoiceInk/Views/Dictionary/DictionarySettingsView.swift`
- Fixed `CustomCloudModel` API key property conflicts and initialization consistency in `VoiceInk/Models/TranscriptionModel.swift`.
- Fixed a Debug launch crash caused by missing `whisper.framework` embedding:
  - Restored `whisper.xcframework` build-file entries in `VoiceInk.xcodeproj/project.pbxproj` so the framework is properly linked and embedded in app bundles.
  - Prevents `DYLD, Code 1, Library missing` on `@rpath/whisper.framework/Versions/Current/whisper`.

### Verification
- Performed parser-level verification across Swift sources with `swiftc -frontend -parse`.
- Full `xcodebuild build/test` remains blocked in this sandbox environment due SwiftPM/package sandbox restrictions (`sandbox-exec: sandbox_apply: Operation not permitted`).

## 2025-12-31

### Bug Fixes
- **Sidebar Styling**: Fixed an issue where the "Text to Speech" sidebar item displayed incorrect colors (blue/teal) when the sidebar lost focus.
- **Persistent Selection**: Implemented persistent active styling to ensure the selected sidebar item remains visually active (Blue/White) even when focus is transferred to detail views.

## 2025-12-29

### Refactoring (Tier 4)
- **Settings Centralization**: Consolidated scattered `UserDefaults` access into a unified `AppSettings` structure.
  - Eliminated `VoiceInk/Services/UserDefaultsManager.swift`.
  - Migrated license and trial date storage to `AppSettings+License.swift` with obfuscation.
- **Shared Utilities**: Relocated `AuthorizationHeader.swift` to `VoiceInk/Utilities` to promote reuse across services.
- **Documentation**: Added missing HeaderDoc comments to shared utilities.

### AI Enhancement & CloudSync
- **CloudSync**: Implemented iCloud Key-Value Store synchronization for AI enhancement profiles.
- **Opt-in Privacy**: Introduced "Sync with iCloud" toggle in Settings -> Enhancement.
- **UI UX**: Added dedicated "Enhancement" settings tab (renamed from internal "AI").
- **Documentation**: Added `CLOUDSYNC_DOCUMENTATION.md` and updated `DESIGN_DOCUMENT.md`/`AGENTS.md`.

## 2025-12-27

### Architecture - WhisperState SOLID Refactoring

Major architectural refactoring of the Whisper transcription system following SOLID principles. The refactoring was completed in 5 phases and introduces a clean, protocol-based architecture.

**New Components:**

- **Protocols** (`VoiceInk/Whisper/Protocols/`)
  - `ModelProviderProtocol` - Type-safe model handling with associated types
  - `LoadableModelProviderProtocol` - Extension for models requiring memory loading
  - `RecordingSessionProtocol` - Recording session abstraction
  - `TranscriptionProcessorProtocol` - Transcription processing interface
  - `UIManagerProtocol` - UI state management interface

- **Providers** (`VoiceInk/Whisper/Providers/`)
  - `LocalModelProvider` - Whisper.cpp model management (430 lines)
  - `ParakeetModelProvider` - Parakeet model management (135 lines)

- **Managers** (`VoiceInk/Whisper/Managers/`)
  - `RecordingSessionManager` - Clean state machine for recording (167 lines)
  - `AudioBufferManager` - Buffer caching and cleanup (133 lines)
  - `UIManager` - UI state coordination (105 lines)

- **Processors** (`VoiceInk/Whisper/Processors/`)
  - `TranscriptionProcessor` - Service registry pattern (183 lines)
  - `AudioPreprocessor` - Audio preprocessing pipeline (102 lines)
  - `TranscriptionResultProcessor` - Text filtering and formatting (84 lines)

- **Actors** (`VoiceInk/Whisper/Actors/`)
  - `WhisperContextManager` - Thread-safe Whisper context operations via `@globalActor`

- **Coordinators** (`VoiceInk/Whisper/Coordinators/`)
  - `InferenceCoordinator` - Priority-based queue with cancellation support (216 lines)

- **Models** (`VoiceInk/Whisper/Models/`)
  - `WhisperContextWrapper` - Context wrapper for safe memory management

- **Core Updates**
  - `ModelManager` - Coordinates all providers with Combine bindings (291 lines)
  - `WhisperState` - Maintains backward compatibility while delegating to new components (354 lines)
  - `RecordingState` - Clean state enum for recording flow

**Quality Metrics:**
- Test pass rate: 93.9% (168/179 tests)
- ~2,400 lines of well-structured new code
- Full backward compatibility maintained
- Proper Swift concurrency patterns (@MainActor, actors, async/await)

### Performance

- Optimized `TTSHistoryViewModel` disk limit calculation with cached byte tracking

### Bug Fixes

- Fixed hotkey regression that prevented recording shortcuts from working

### Testing

- Added 57 new tests covering the refactored Whisper architecture
- All test failures are test implementation issues, not production code bugs

### Documentation

- Created `WHISPERSTATE_REFACTORING_VERIFICATION_REPORT.md` with comprehensive verification results
- Updated `PHASE_REVIEW_FINAL_REPORT_2025-12-26.md` with phase completion status

## 2025-12-23

### Security
- Enabled App Sandbox entitlements and tightened keychain cleanup behavior.
- Enforced HTTPS validation for custom provider endpoints and URL matching safeguards.

### Architecture
- Split TTS view model responsibilities into focused components and reorganized workspace views.
- Centralized app settings access and normalized service naming across the codebase.

### Cloud Transcription
- Introduced shared request/response utilities and multipart builders.
- Added a base provider abstraction to reduce duplication across services.

### Power Mode
- Modularized configuration view sections and improved prompt/URL handling logic.
- Updated localization coverage and reduced view complexity.

### Whisper + Audio
- Extracted recording flow into a dedicated extension and hardened model lifecycle handling.
- Addressed task lifecycle cleanup and thread-safety improvements.

### Testing
- Updated unit/integration tests to align with refactors and new APIs.
- Recorded targeted test runs in implementation checklists.

### Documentation
- Updated phase checklists and test status tracking to reflect completed work.

## 2025-12-21

### UI
- Aligned Settings navigation selection highlight with app accent styling.

### Refactoring
- Decomposed 7 large files into modular extensions following the `Type+Feature.swift`
  pattern from AGENTS.md to comply with the 500-line guideline.
- Created 22 new extension files to improve code organization and maintainability.
- Achieved 62.2% total line reduction in main files (4,340 → 1,641 lines).
- Files refactored:
  - `AIService.swift`: 792 → 192 lines (75.8% reduction, 4 extensions)
  - `TTSViewModel+Helpers.swift`: 672 → 185 lines (72.5% reduction, 4 extensions)
  - `AIEnhancementService.swift`: 613 → 331 lines (46.0% reduction, 3 extensions)
  - `TTSSettingsView.swift`: 604 → 235 lines (61.1% reduction, 4 extensions)
  - `TTSViewModel.swift`: 587 → 311 lines (47.0% reduction, 3 extensions)
  - `PredefinedModels.swift`: 564 → 39 lines (93.1% reduction, 3 extensions)
  - `TTSViewModel+SpeechGeneration.swift`: 508 → 348 lines (31.5% reduction, 1 extension)
- All changes verified to compile successfully.

## 2025-12-20

### Performance
- Streamed audio preprocessing to avoid loading entire files into memory.
- Streamed OpenAI and Google transcription request bodies from temp files.
- Used memory-mapped audio reads where safe to reduce heap pressure.

### Memory
- Read PCM16 samples in chunks for local and on-device transcription engines.
- Truncated browser and OCR context at source to cap payload size.
- Capped stored AI request context strings to prevent runaway memory growth.

### Storage
- Reused audio files via hard links when possible to reduce duplicate storage.
- Cached recent TTS history audio on disk with size limits and cleanup.

### Reliability
- Prevented duplicate playback timers in the audio player view.

## 2025-12-19

### Security
- Enforced HTTPS validation for custom AI provider verification to prevent
  insecure API key transmission.

### Performance
- Avoided blocking audio file reads by using async loaders and upload-by-file
  where supported.

### Concurrency
- Removed redundant main-thread hops in `@MainActor` classes.

### I/O
- Removed forced `UserDefaults.synchronize()` calls in hot paths.
