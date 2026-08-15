export const TRANSCRIPTION_MODEL_ID = "@cf/openai/whisper-large-v3-turbo" as const;
export const TRANSCRIPTION_MODEL_NAME = "whisper-large-v3-turbo" as const;

export const MAXIMUM_TRANSCRIPTION_REQUEST_BYTES = 25 * 1024 * 1024;
export const MAXIMUM_AUDIO_BYTES = 24 * 1024 * 1024;
export const MAXIMUM_TRANSCRIPT_CHARACTERS = 200_000;
export const MAXIMUM_TRANSCRIPTION_DURATION_SECONDS = 6 * 60 * 60;

export const INTERNAL_BODY_LENGTH_HEADER = "x-voiceink-body-length";
export const INTERNAL_CLIENT_KEY_HEADER = "x-voiceink-client-key";
export const TURNSTILE_TOKEN_HEADER = "x-voiceink-turnstile";

const supportedAudioTypes = new Set([
  "audio/aac",
  "audio/flac",
  "audio/mp4",
  "audio/mpeg",
  "audio/ogg",
  "audio/wav",
  "audio/webm",
  "audio/x-m4a",
  "audio/x-wav",
]);

export type TranscriptionResponse = {
  text: string;
  model: typeof TRANSCRIPTION_MODEL_NAME;
  durationSeconds?: number;
  segments?: TranscriptionSegment[];
};

export type TranscriptionSegment = { start: number; end: number; text: string };

export function normalizeAudioMediaType(value: string) {
  return value.split(";", 1)[0]?.trim().toLowerCase() ?? "";
}

export function isSupportedAudioMediaType(value: string) {
  return supportedAudioTypes.has(normalizeAudioMediaType(value));
}

export function hasMatchingAudioSignature(mediaType: string, bytes: Uint8Array) {
  const type = normalizeAudioMediaType(mediaType);
  const startsWith = (...signature: number[]) => signature.every((byte, index) => bytes[index] === byte);
  const asciiAt = (offset: number, value: string) =>
    [...value].every((character, index) => bytes[offset + index] === character.charCodeAt(0));

  switch (type) {
  case "audio/wav":
  case "audio/x-wav":
    return asciiAt(0, "RIFF") && asciiAt(8, "WAVE");
  case "audio/webm":
    return startsWith(0x1a, 0x45, 0xdf, 0xa3);
  case "audio/ogg":
    return asciiAt(0, "OggS");
  case "audio/flac":
    return asciiAt(0, "fLaC");
  case "audio/mp4":
  case "audio/x-m4a":
    return asciiAt(4, "ftyp");
  case "audio/mpeg":
    return asciiAt(0, "ID3") || (bytes[0] === 0xff && (bytes[1] ?? 0) >= 0xe0);
  case "audio/aac":
    return bytes[0] === 0xff && ((bytes[1] ?? 0) & 0xf6) === 0xf0;
  default:
    return false;
  }
}

export function parseTranscriptionResponse(value: unknown): TranscriptionResponse | null {
  if (!value || typeof value !== "object") return null;
  const candidate = value as Record<string, unknown>;
  if (candidate.model !== TRANSCRIPTION_MODEL_NAME || typeof candidate.text !== "string") return null;
  const text = candidate.text.trim();
  if (!text || text.length > MAXIMUM_TRANSCRIPT_CHARACTERS) return null;

  const duration = candidate.durationSeconds;
  if (duration !== undefined && (
    typeof duration !== "number"
    || !Number.isFinite(duration)
    || duration < 0
    || duration > MAXIMUM_TRANSCRIPTION_DURATION_SECONDS
  )) return null;

  let segments: TranscriptionSegment[] | undefined;
  if (candidate.segments !== undefined) {
    if (!Array.isArray(candidate.segments) || candidate.segments.length > 5_000) return null;
    let previousStart = 0;
    let characters = 0;
    segments = [];
    for (const value of candidate.segments) {
      if (!value || typeof value !== "object") return null;
      const segment = value as Record<string, unknown>;
      const segmentText = typeof segment.text === "string" ? segment.text.trim() : "";
      if (typeof segment.start !== "number" || !Number.isFinite(segment.start)
        || typeof segment.end !== "number" || !Number.isFinite(segment.end)
        || segment.start < previousStart || segment.start < 0 || segment.end <= segment.start
        || segment.end > MAXIMUM_TRANSCRIPTION_DURATION_SECONDS || !segmentText) return null;
      characters += segmentText.length;
      if (characters > MAXIMUM_TRANSCRIPT_CHARACTERS) return null;
      previousStart = segment.start;
      segments.push({ start: segment.start, end: segment.end, text: segmentText });
    }
  }

  return {
    text,
    model: TRANSCRIPTION_MODEL_NAME,
    ...(typeof duration === "number" ? { durationSeconds: duration } : {}),
    ...(segments?.length ? { segments } : {}),
  };
}
