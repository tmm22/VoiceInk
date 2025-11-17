# Local Transcription Upgrades

## Overview

- Added dedicated FastConformer provider backed by ONNX Runtime, delivering ~4.3% WER CTC decoding with sub‑250 ms latency on Apple Silicon.
- Expanded Whisper local model metadata so `.gguf` exports (e.g., Distil‑Whisper Large v3 and Whisper Large v3 Turbo q5_0) download, index, and import without manual renaming.
- Reworked the download pipeline to stream multi‑gigabyte payloads straight to disk, keeping memory usage flat and enabling simultaneous progress reporting for model, Core ML encoder, and tokenizer assets.

## FastConformer Provider

### Requirements

- macOS user account must allow Metal access; FastConformer cards expose a **Metal** badge to make this explicit.
- Assets live at `~/Library/Application Support/com.tmm22.VoiceLinkCommunity/FastConformer/<model-name>/` and consist of `model.onnx` and `tokens.txt`.

### Download & Management Flow

1. Open **AI Models → Local** and switch the filter pill to **FastConformer**.
2. Use the dedicated card to start the download; progress reflects two sequential transfers (ONNX weights then tokenizer).
3. When the progress ring completes, the Manage menu offers:
   - **Set Default**: swaps `currentTranscriptionModel` to FastConformer and invalidates any cached ORT session.
   - **Show in Finder**: jumps directly to the per‑model folder described above.
   - **Delete Files**: removes both assets and clears the persisted “downloaded” flag from `UserDefaults`.
4. Switching back to Parakeet/Whisper automatically calls `fastConformerTranscriptionService.cleanup()` so resources are released.

### Testing Checklist

- ✅ Download end‑to‑end on Release build without code signing.
- ✅ Confirm transcription works by selecting **FastConformer CTC (1.1B)**, recording a short clip, and verifying greedy decoding output.
- ✅ Delete & re‑download to ensure directory cleanup + notification flow operate as expected.

## GGUF Whisper Enhancements

### New Predefined Models

| Model | Size | Notes |
| --- | --- | --- |
| `distil-whisper-large-v3` | 1.5 GB | Distilled Large v3 with `distil-large-v3_f16.gguf` payload, ~45 % faster with near‑Large accuracy. |
| `whisper-large-v3-turbo-gguf` | 2.1 GB | Turbo export quantized to `q5_0`, tuned for Apple Silicon VRAM budgets. |

Both entries use explicit Hugging Face `?download=1` links plus filename overrides so the downloader stores the canonical `.gguf` names.

### Download Pipeline Improvements

- `downloadFileWithProgress` now streams to a `*.download` temp file before atomically moving into `WhisperModels/`, eliminating multi‑gigabyte `Data` allocations.
- Model discovery now recognizes both `.bin` and `.gguf` extensions, re‑mapping filenames back to the canonical model IDs to keep UI labels consistent.
- Core ML warmups remain limited to `.bin` builds to avoid wasting time on quantized exports that cannot be converted.

### Importing Custom Models

- The **Import Model** action (Model Management → ••• → Import) accepts `.bin` **and** `.gguf` payloads.
- Files are copied—not moved—into the managed directory. Name collisions result in a user‑facing warning instead of overwriting.

### Verification Checklist

- ✅ Download each new predefined GGUF model and confirm it appears under **Local Models** with the correct badges/highlights.
- ✅ Import a third‑party `.gguf` file via Finder; ensure it shows up under “Imported Local Model” with full action menu.
- ✅ Delete a GGUF model and confirm both the primary file and any paired CoreML encoder directory are removed.

## Reference Commands

- Release validation: `xcodebuild -project VoiceInk.xcodeproj -scheme VoiceInk -configuration Release -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build`
- Default validator (Debug): `xcodebuild -project VoiceInk.xcodeproj -scheme VoiceInk -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build`
