// Integer micro-dollar accounting for the daily spend ledger. Floats drift on
// thousands of small commits, so every amount in the ledger is micro-dollars.
export const ENGLISH_TRANSCRIPTION_MICROS_PER_MINUTE = 5_200; // $0.0052 per audio minute (@cf/deepgram/nova-3)
export const MULTILINGUAL_TRANSCRIPTION_MICROS_PER_MINUTE = 510; // $0.00051 per audio minute (@cf/openai/whisper-large-v3-turbo)

// Non-English audio is detected by nova-3 and then re-transcribed by whisper,
// so one request can run both models over the same audio. Admission must
// reserve for that combined worst case.
export const WORST_CASE_TRANSCRIPTION_MICROS_PER_MINUTE =
  ENGLISH_TRANSCRIPTION_MICROS_PER_MINUTE + MULTILINGUAL_TRANSCRIPTION_MICROS_PER_MINUTE;

// An attacker packs the most audio minutes per byte with low-bitrate audio, so
// admission pricing must assume the lowest plausible bitrate. Opus voice can
// reach ~6 kbps, so price below that (~4 kbps) to keep the reservation an upper
// bound on any real file's actual cost.
export const WORST_CASE_BYTES_PER_SECOND = 500;

export const TEXT_GENERATION_FLAT_MICROS = 2_000; // conservative flat cost per llama call

export const DEFAULT_DAILY_SPEND_LIMIT_MICROS = 10_000_000; // $10.00 per day
export const DEFAULT_DAILY_CLIENT_AUDIO_SECONDS = 7_200; // 2 hours of audio per client per day

// Inference is aborted before this so a live request always settles before its
// reservation can expire; the expiry only reclaims headroom from a crashed or
// abandoned request. Keep RESERVATION_EXPIRY_MS > INFERENCE_TIMEOUT_MS.
export const INFERENCE_TIMEOUT_MS = 4 * 60 * 1_000;
export const RESERVATION_EXPIRY_MS = 6 * 60 * 1_000;

export function worstCaseAudioSeconds(declaredBytes: number) {
  if (!Number.isSafeInteger(declaredBytes) || declaredBytes <= 0) return 0;
  return Math.ceil(declaredBytes / WORST_CASE_BYTES_PER_SECOND);
}

export function estimateTranscriptionMicros(declaredBytes: number) {
  return Math.ceil((worstCaseAudioSeconds(declaredBytes) / 60) * WORST_CASE_TRANSCRIPTION_MICROS_PER_MINUTE);
}

export function actualTranscriptionMicros(durationSeconds: number, microsPerMinute: number) {
  if (!Number.isFinite(durationSeconds) || durationSeconds <= 0) return 0;
  if (!Number.isFinite(microsPerMinute) || microsPerMinute <= 0) return 0;
  return Math.ceil((durationSeconds / 60) * microsPerMinute);
}

export function utcDay(epochMs: number) {
  return new Date(epochMs).toISOString().slice(0, 10);
}

export function parsePositiveIntegerSetting(value: unknown, fallback: number) {
  if (typeof value !== "string" || !/^[1-9]\d*$/.test(value)) return fallback;
  const parsed = Number(value);
  return Number.isSafeInteger(parsed) ? parsed : fallback;
}
