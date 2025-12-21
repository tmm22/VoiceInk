# Changelog

All notable changes to the VoiceLink Community application are documented here.

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
