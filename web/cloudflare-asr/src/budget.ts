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

// Text generation (@cf/google/gemma-4-26b-a4b-it): $0.10 per M input tokens
// and $0.30 per M output tokens, i.e. 0.1 and 0.3 micro-dollars per token.
export const TEXT_INPUT_MICROS_PER_TOKEN = 0.1;
export const TEXT_OUTPUT_MICROS_PER_TOKEN = 0.3;
// Headroom for the system prompt and chat template around the user text.
const TEXT_PROMPT_OVERHEAD_TOKENS = 1_000;

// Worst-case reservation from the UTF-8 byte length of the exact serialized
// prompt: a BPE token always covers at least one byte, so bytes bound tokens
// even for dense scripts and JSON-escaped control characters. English runs
// about four bytes per token, so real usage settles far below this.
export function estimateTextGenerationMicros(inputBytes: number, maxOutputTokens: number) {
  const inputTokens = Math.max(0, Math.ceil(inputBytes)) + TEXT_PROMPT_OVERHEAD_TOKENS;
  return Math.ceil(inputTokens * TEXT_INPUT_MICROS_PER_TOKEN + Math.max(0, maxOutputTokens) * TEXT_OUTPUT_MICROS_PER_TOKEN);
}

// Settles to the provider-reported usage; without usage the reservation stands.
export function actualTextGenerationMicros(usage: unknown, reservedMicros: number) {
  if (!usage || typeof usage !== "object") return reservedMicros;
  const { prompt_tokens: input, completion_tokens: output } = usage as { prompt_tokens?: unknown; completion_tokens?: unknown };
  if (typeof input !== "number" || typeof output !== "number" || !Number.isFinite(input) || !Number.isFinite(output)
    || input < 0 || output < 0) return reservedMicros;
  return Math.min(reservedMicros, Math.ceil(input * TEXT_INPUT_MICROS_PER_TOKEN + output * TEXT_OUTPUT_MICROS_PER_TOKEN));
}

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

// Defaults to the combined nova-3 + whisper worst case; a request routed
// straight to whisper by a confident language hint can only run whisper.
export function estimateTranscriptionMicros(
  declaredBytes: number,
  microsPerMinute: number = WORST_CASE_TRANSCRIPTION_MICROS_PER_MINUTE,
) {
  return Math.ceil((worstCaseAudioSeconds(declaredBytes) / 60) * microsPerMinute);
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
