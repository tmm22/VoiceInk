# Changelog

All notable changes to the VoiceLink Community application are documented here.

## 2026-03-13

### Release Preparation
- Bumped the community build metadata to version `1.62` (`v1.62-community` release target) for the next GitHub release on `tmm22/VoiceInk`.

### Maintenance
- Replaced remaining menu bar navigation `print()` diagnostics with `AppLogger.ui` logging in `VoiceInk/MenuBarManager.swift` so the app stays aligned with the existing structured logging conventions.
- Removed an unused `WindowDelegate` helper from `VoiceInk/MenuBarManager.swift`.
- Removed unused `hotkeyManager`, `audioDeviceManager`, and `isHovered` state from `VoiceInk/Views/MenuBarView.swift` to keep the menu bar view surface in sync with its actual dependencies.

## 2026-03-10

### Release Preparation
- Bumped the community build metadata to version `1.61` (`v1.61-community` release target) for the next GitHub release on `tmm22/VoiceInk`.
- Added GitHub-facing documentation for running unsigned releases, including Gatekeeper override steps and the explanation that Apple Developer Program membership currently costs 99 USD per year.
- Added a reusable release-body template at `.github/RELEASE_TEMPLATE.md` and a maintainer guide at `docs/development/RELEASING.md` so future GitHub releases consistently include unsigned-build instructions.

### Community Infrastructure
- Redirected in-app announcement fetches to the `tmm22/VoiceInk` repository instead of upstream, so community builds no longer depend on `beingpax.github.io` for announcement content.

## 2026-03-07

### Security & Privacy
- Removed production payload logging of AI system prompts, transcript text, enhanced text, filtered transcript text, and active browser URLs. Reviewed paths now log metadata only (provider/model identifiers, browser names, and character counts).
- Eliminated the `LOCAL_BUILD` plaintext secret fallback in `KeychainService`; local builds now remain Keychain-only and disable syncable items instead of redirecting secrets to `UserDefaults`.

### Performance & Networking
- Added a shared streamed multipart upload path in `VoiceInk/Services/CloudTranscription/CloudTranscriptionBase.swift` that writes request bodies to a temporary file and uploads them through `SecureURLSession.makeEphemeral()`.
- Moved Deepgram to direct `upload(for:fromFile:)` uploads for recorded audio instead of loading files fully into memory.
- Migrated ElevenLabs and Soniox multipart uploads to the streamed body-file path, and applied the same hardening/refactor to OpenAI, OpenAI-compatible, Groq, ZAI, and Mistral cloud transcription providers.
- Removed the redundant `MultipartFormDataBuilder.swift` after consolidating multipart upload handling in the shared base class.
- Reworked Gemini cloud transcription to use the Gemini Files API instead of embedding full recordings as inline Base64 JSON payloads. Audio is now uploaded via resumable file upload, referenced by `file_uri` during `generateContent`, and deleted remotely after completion as best-effort cleanup.
- Reduced TTS workspace memory retention by teaching the active workspace state to track file-backed audio separately from in-memory `Data`, allowing history playback and same-format export to reuse disk-backed audio without reloading the full file into RAM.
- Added explicit audio-player unloading in the TTS workspace so clearing or replacing generated audio releases the underlying `AVAudioPlayer` instance and its buffers instead of only resetting playback state.
- Reduced Parakeet transcription peak memory and conversion overhead by switching local audio reads to `.mappedIfSafe` and replacing the previous per-sample slicing path with a reserved-capacity PCM conversion loop.

### Reduction & Maintenance
- Collapsed duplicate history screens into compatibility shims so `TranscriptionHistoryView` is once again the single real implementation, while legacy entry points forward to it.
- Restored the missing `CircularCheckboxStyle` used by `TranscriptionCard`, which allowed the full app target to compile cleanly during verification.

### Documentation
- Expanded `AGENTS.md` with explicit guardrails for single-source-of-truth UI implementations, sensitive-data logging, Keychain-only local builds, and streamed large-audio uploads.
- Added `docs/reviews/CODE_REVIEW_2026-03-07.md` to capture the review findings, resolutions, and validation results for this pass.

### Verification
- Completed a successful `xcodebuild` Debug build for scheme `VoiceInk` on macOS after the remediation pass.
- Completed `git diff --check` successfully after the fixes.
- Ran follow-up code sweeps to confirm the reviewed cloud transcription paths no longer use `URLSession.shared`, `Data(contentsOf:)` for upload bodies, or the previous explicit sensitive log strings.
- Completed parser-level validation with `xcrun swiftc -parse` for the Gemini transcription refactor and the TTS/Parakeet resource-usage changes made in this follow-up pass.

## 2026-03-06

### Upstream Sync
- Merged latest `upstream/main` into branch history via merge commit `586f2f6` (upstream tip at merge: `b775ebe`).
- Adopted upstream additions that were low-risk or additive for the community fork, including:
  - Streaming/cloud transcription support files and session plumbing
  - Cursor pasting/log export/screen capture updates
  - Audio/transcription cleanup support and related settings flows
- Preserved community-fork behavior and conventions in conflict-heavy areas, including settings/navigation, menu bar flow, hotkey behavior, Power Mode integration, AI model management views, and local/cloud transcription wiring.

### Build Recovery
- Repaired the Xcode project after merge resolution so `VoiceInk.xcodeproj/project.pbxproj` remains parseable while keeping community-specific package choices and adding upstream-required `LLMkit` and `CloudKit` references.
- Removed partially merged upstream engine/manager files that conflicted with the fork's established `WhisperState` architecture and restored the local UI/controller wiring they would have displaced.
- Synced `Package.resolved` with the successful build state, including the `mediaremote-adapter` pin required by the repaired project graph.

### Documentation
- Updated `docs/implementation/UPSTREAM_INTEGRATION_PROGRESS.md` with the March 6, 2026 sync session and conflict-resolution strategy.
- Refreshed README recent-changes notes to reflect the current upstream sync status.

### Structural Refactors
- Split the remaining oversized Swift files into focused companion files so the key application areas now stay under the 500-line review target.
- Refactored the remaining large UI surfaces into smaller sections/components, including:
  - `VoiceInk/Views/PromptEditorView.swift`
  - `VoiceInk/Views/Dictionary/WordReplacementView.swift`
  - `VoiceInk/Views/AI Models/APIKeyManagementView.swift`
  - `VoiceInk/Views/AudioPlayerView.swift`
  - `VoiceInk/TTS/Views/TTSInspectorView.swift`
- Refactored the remaining large service/core files into feature-focused companions, including:
  - `VoiceInk/CoreAudioRecorder.swift`
  - `VoiceInk/Services/AudioDeviceManager.swift`
  - `VoiceInk/TTS/Services/ElevenLabsTTSService.swift`
- Added a follow-up audit/fix pass after the split to preserve moved call sites and restore small regressions in audio-device access and branded dictionary examples.

### AI Enhancement
- Updated the OpenAI enhancement default/model list to `gpt-5.4` and `gpt-5.4-pro`, and routed GPT-5 enhancement requests through the OpenAI Responses API.
- Normalized GPT-5 reasoning effort handling and added output token caps so enhancement requests stay within model-supported parameters more consistently.
- Improved OpenAI rate-limit handling by surfacing provider `429` messages, respecting `Retry-After`, and retrying once from `gpt-5.4-pro` to `gpt-5.4` when the pro tier is throttled.
- Updated OpenAI API key verification to use the correct GPT-5 endpoint/model path with a reduced token budget, and switched OpenAI audio transcription to `gpt-4o-transcribe`.
- Added `GPT-4o Transcribe (OpenAI)` to the cloud transcription model catalog and wired it into the selectable Model Management list.

### Verification
- Completed a successful `xcodebuild` Debug build for scheme `VoiceInk` in an isolated worktree after merge reconciliation.
- Completed a follow-up successful `xcodebuild` Debug build after the GPT-5.4 and rate-limit handling changes, then reran `reset_permissions.sh` for clean manual testing.
- Completed a post-refactor audit showing `0` Swift files over 500 lines in `VoiceInk/`, with `git diff --check`, parser-level validation across all touched files, and narrow `swiftc -typecheck` verification for the recorder and audio-device splits.

## 2026-02-19

### Gemini 3.1 Preview
- Added support for `gemini-3.1-pro-preview` in AI Enhancement model selection (`VoiceInk/Services/AIEnhancement/AIProvider.swift`).
- Updated Gemini AI Enhancement default model to `gemini-3.1-pro-preview`.
- Added `gemini-3.1-pro-preview` to Gemini reasoning-capable models (`VoiceInk/Services/AIEnhancement/ReasoningConfig.swift`).
- Added `gemini-3.1-pro-preview` to cloud transcription Gemini model catalog (`VoiceInk/Models/PredefinedModels+CloudModels.swift`).

## 2026-02-14

### Upstream Sync
- Merged latest `upstream/main` into `custom-main-v2` via merge commit `5c75ed2` (upstream tip at merge: `36427eb`).
- Brought upstream streaming transcription architecture and providers into the fork, including:
  - `VoiceInk/Services/StreamingTranscription/StreamingTranscriptionService.swift`
  - `VoiceInk/Services/StreamingTranscription/DeepgramStreamingProvider.swift`
  - `VoiceInk/Services/StreamingTranscription/ElevenLabsStreamingProvider.swift`
  - `VoiceInk/Services/StreamingTranscription/MistralStreamingProvider.swift`
  - `VoiceInk/Services/StreamingTranscription/ParakeetStreamingProvider.swift`
  - `VoiceInk/Services/StreamingTranscription/SonioxStreamingProvider.swift`
- Incorporated upstream recorder/metrics/settings updates and local-build support additions (`LocalBuild.xcconfig`, `VoiceInk/VoiceInk.local.entitlements`, `Makefile` `local` target).

### TTS Stability (Pocket Voices)
- Normalized Pocket TTS voice IDs in `VoiceInk/TTS/Services/LocalTTSService.swift` so legacy user-facing IDs map correctly to engine voice IDs.
- Added fallback behavior to a recommended Pocket voice when a selected voice is unavailable at runtime.
- Expanded embedding-cache cleanup so hide/remove paths clear both legacy and normalized Pocket voice cache entries.

### Community Edition Follow-up Fixes
- Removed remaining Voice Link branding references and promotional savings copy from the Community Edition UI.
- Removed Discord references from dashboard/community call-to-actions and replaced them with the maintained discussion route.
- Fixed a Community Edition relaunch regression that incorrectly showed a trial-expired state after reopening a recent debug build.
- Confirmed Community Edition behavior remains license-free (no license key requirement) after follow-up dashboard/settings changes.
- Restored the category-based Settings layout (General, Audio, AI, etc.) while keeping upstream functionality introduced in the sync.

### Verification
- Completed merge-conflict resolution with a clean index and no conflict markers.
- Ran whitespace/conflict hygiene checks on merge content (`git diff --check`).

## 2026-02-08

### Stability
- Added a runtime CloudKit guard in `VoiceInk/VoiceInk.swift` for the dictionary store so CloudKit sync is enabled only when entitlement and iCloud account state are available.
- Added `VOICEINK_DISABLE_DICTIONARY_CLOUDKIT=1` environment override to force local-only dictionary persistence for troubleshooting.
- Prevented launch-time aborts observed on `com.apple.coredata.cloudkit.queue` when CloudKit prerequisites are not met.

### Debug Validation
- Performed a fresh clean Debug build and launch verification from local derived data artifacts.
- Confirmed Pocket TTS voices are available in Tight Ass Mode after resetting local visibility defaults.

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

### Build Recovery & Debug Validation
- Resolved additional compile-time drift to restore a clean Debug build flow for TTS voice testing:
  - Restored compatibility APIs and call sites in Power Mode (`ActiveWindowService`, `PowerModeShortcutManager`, `PowerModeView`, `PowerModeConfigView`).
  - Fixed recorder/history/hotkey integration issues in `Recorder`, `HistoryWindowController`, and `HotkeyManager`.
  - Reconciled UI and helper API mismatches in `InfoTip`, `PermissionsView`, `EnhancementSettingsView`, `EnhancementShortcutsView`, `DashboardPromotionsSection`, and `APIKeyManagementView`.
  - Fixed dictionary/context/model download regressions in `WordReplacementView`, `AIContextBuilder`, and `OnboardingModelDownloadView`.
- Completed a fresh clean Debug build with `xcodebuild ... clean build` (macOS destination, local derived data), producing `VoiceLink Community.app` successfully with warnings only.

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
- **Documentation**: Added `docs/implementation/CLOUDSYNC_DOCUMENTATION.md` and updated `docs/development/DESIGN_DOCUMENT.md`/`AGENTS.md`.

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

- Created `docs/reviews/WHISPERSTATE_REFACTORING_VERIFICATION_REPORT.md` with comprehensive verification results
- Updated `docs/reviews/PHASE_REVIEW_FINAL_REPORT_2025-12-26.md` with phase completion status

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
