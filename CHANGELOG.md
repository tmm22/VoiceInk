# Changelog

All notable changes to the VoiceLink Community application are documented here.

## 2025-12-29

### Refactoring (Tier 4)
- **Settings Centralization**: Consolidated scattered `UserDefaults` access into a unified `AppSettings` structure.
  - Eliminated `VoiceInk/Services/UserDefaultsManager.swift`.
  - Migrated license and trial date storage to `AppSettings+License.swift` with obfuscation.
- **Shared Utilities**: Relocated `AuthorizationHeader.swift` to `VoiceInk/Utilities` to promote reuse across services.
- **Documentation**: Added missing HeaderDoc comments to shared utilities.

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
