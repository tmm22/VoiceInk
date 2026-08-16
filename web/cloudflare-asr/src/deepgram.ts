import {
  boundedDurationSeconds,
  isValidLanguageTag,
} from "../../shared/transcriptionContract.ts";

export type DeepgramTranscription = {
  text: string;
  detectedLanguages: string[];
  durationSeconds?: number;
};

// The generated Workers AI output type for @cf/deepgram/nova-3 documents only a
// subset of Deepgram's response: metadata.duration, alternatives[].languages,
// and alternatives[].paragraphs arrive at runtime but are absent from the
// schema, so the raw value is parsed defensively here instead of trusting the
// generated types. Detection observed live on Workers AI reports the spoken
// languages as alternatives[0].languages (an array, code-switching aware);
// channels[0].detected_language is kept as a fallback for Deepgram's
// single-language response shape.
export function extractDeepgramTranscription(value: unknown): DeepgramTranscription | null {
  if (!value || typeof value !== "object") return null;
  const results = (value as { results?: unknown }).results;
  if (!results || typeof results !== "object") return null;
  const channels = (results as { channels?: unknown }).channels;
  if (!Array.isArray(channels) || !channels[0] || typeof channels[0] !== "object") return null;
  const channel = channels[0] as { alternatives?: unknown; detected_language?: unknown };
  if (!Array.isArray(channel.alternatives) || !channel.alternatives[0]
    || typeof channel.alternatives[0] !== "object") return null;
  const alternative = channel.alternatives[0] as {
    transcript?: unknown; paragraphs?: unknown; words?: unknown; languages?: unknown;
  };

  // The paragraphs feature places its newline-broken text on a sibling field;
  // the top-level transcript stays one unbroken string.
  const paragraphs = alternative.paragraphs && typeof alternative.paragraphs === "object"
    ? (alternative.paragraphs as { transcript?: unknown }).transcript
    : undefined;
  const flat = typeof alternative.transcript === "string" ? alternative.transcript.trim() : "";
  const text = typeof paragraphs === "string" && paragraphs.trim() ? paragraphs.trim() : flat;
  if (!text) return null;

  const rawLanguages = Array.isArray(alternative.languages)
    ? alternative.languages
    : [channel.detected_language];
  const detectedLanguages: string[] = [];
  for (const tag of rawLanguages.slice(0, 16)) {
    if (!isValidLanguageTag(tag)) continue;
    const normalized = tag.toLowerCase();
    if (!detectedLanguages.includes(normalized)) detectedLanguages.push(normalized);
  }

  const metadata = (value as { metadata?: unknown }).metadata;
  let durationSeconds = metadata && typeof metadata === "object"
    ? boundedDurationSeconds((metadata as { duration?: unknown }).duration)
    : undefined;
  if (durationSeconds === undefined && Array.isArray(alternative.words) && alternative.words.length) {
    const last = alternative.words[alternative.words.length - 1];
    if (last && typeof last === "object") {
      durationSeconds = boundedDurationSeconds((last as { end?: unknown }).end);
    }
  }

  return {
    text,
    detectedLanguages,
    ...(durationSeconds !== undefined ? { durationSeconds } : {}),
  };
}
