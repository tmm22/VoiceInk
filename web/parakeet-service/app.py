import os
import subprocess
import tempfile
from pathlib import Path

import torch
from fastapi import FastAPI, File, Form, Header, HTTPException, UploadFile
from transformers import pipeline

MODEL_ID = os.getenv("PARAKEET_MODEL", "nvidia/parakeet-tdt-0.6b-v3")
API_KEY = os.getenv("PARAKEET_API_KEY", "")

app = FastAPI(title="VoiceInk Parakeet Inference")
device = 0 if torch.cuda.is_available() else -1
transcriber = pipeline("automatic-speech-recognition", model=MODEL_ID, device=device)


@app.get("/health")
def health():
    return {"status": "ok", "model": MODEL_ID, "gpu": torch.cuda.is_available()}


@app.post("/v1/transcriptions")
async def transcribe(
    audio: UploadFile = File(...),
    model_name: str = Form("parakeet-tdt-0.6b-v3", alias="model"),
    authorization: str | None = Header(default=None),
):
    if API_KEY and authorization != f"Bearer {API_KEY}":
        raise HTTPException(status_code=401, detail="Unauthorized")

    suffix = Path(audio.filename or "recording.webm").suffix
    with tempfile.NamedTemporaryFile(suffix=suffix, delete=False) as target:
        target.write(await audio.read())
        path = target.name

    wav_path = f"{path}.wav"
    try:
        subprocess.run(
            ["ffmpeg", "-y", "-i", path, "-ac", "1", "-ar", "16000", wav_path],
            check=True,
            capture_output=True,
        )
        result = transcriber(wav_path)
        text = result["text"]
        return {"text": text, "model": model_name}
    finally:
        Path(path).unlink(missing_ok=True)
        Path(wav_path).unlink(missing_ok=True)
