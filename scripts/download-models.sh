#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODELS_DIR="$ROOT_DIR/VoiceInk/Resources/Models"

mkdir -p "$MODELS_DIR"

function fetch() {
  local url="$1"
  local output="$2"

  if [[ -f "$output" ]]; then
    echo "✔ $output already present; skipping"
    return
  fi

  echo "⬇︎ Downloading $(basename "$output")"
  curl -L --fail "$url" -o "$output"
}

# Whisper base English model (good balance of speed/accuracy)
fetch "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin" \
      "$MODELS_DIR/ggml-base.en.bin"

# Whisper large-v3 turbo quantized (optional but handy)
fetch "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q5_0.bin" \
      "$MODELS_DIR/ggml-large-v3-turbo-q5_0.bin"

echo "All default models downloaded to $MODELS_DIR"
