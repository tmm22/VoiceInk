FROM python:3.12-slim
WORKDIR /app
ENV HF_HOME=/models \
    TRANSFORMERS_CACHE=/models \
    PARAKEET_MODEL=nvidia/parakeet-tdt-0.6b-v3
RUN apt-get update && apt-get install -y --no-install-recommends ffmpeg && rm -rf /var/lib/apt/lists/*
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py .
# Download model weights while building so cold starts do not depend on Hugging Face.
RUN python -c "from transformers import pipeline; pipeline('automatic-speech-recognition', model='nvidia/parakeet-tdt-0.6b-v3', device=-1)"
EXPOSE 8080
CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8080"]
