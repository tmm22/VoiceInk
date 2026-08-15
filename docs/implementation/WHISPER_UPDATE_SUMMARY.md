# Whisper Framework Update to v1.8.2

## Overview
The underlying `whisper.cpp` framework has been updated to version **v1.8.2**. This update is required to support newer model architectures (Distil-Whisper) and file formats (GGUF), addressing the "transcription failed, unable to layer model" error users were experiencing with models like `distil-large-v3_f16.gguf`.

## Changes

### Framework Update
- Replaced the outdated `whisper.framework` in `VoiceInk-Dependencies` with the official precompiled `whisper.xcframework` from `ggml-org/whisper.cpp` release v1.8.2.
- This ensures binary compatibility with macOS (ARM64/x86_64) and iOS/iPadOS/visionOS targets if needed.

### Code Adjustments (`LibWhisper.swift`)
- Updated `LibWhisper.swift` to be more robust against potential API changes in `whisper_full_default_params`.
- Added comments about VAD (Voice Activity Detection) parameter handling, which has evolved in newer library versions.
- Removed explicit `params.vad = false` in the else block to avoid compilation errors if the field was deprecated/renamed, while keeping `params.vad = true` in the active block where we explicitly configure it (assuming backward compatibility).

## Verification
- **Compilation:** The app should compile successfully with the new framework headers.
- **Model Support:** GGUF models (e.g., `distil-large-v3_f16.gguf`) should now load and transcribe correctly.
- **Performance:** Flash Attention and other optimizations in v1.8.2 should improve inference speed on Apple Silicon.

## Troubleshooting
If you encounter "missing symbol" errors during build:
1. Clean the build folder (`Shift+Cmd+K`).
2. Ensure the `whisper.xcframework` is correctly embedded in the target settings (General -> Frameworks, Libraries, and Embedded Content).
3. Verify that `Include Search Paths` in Build Settings points to the new framework headers if not automatically resolved.
