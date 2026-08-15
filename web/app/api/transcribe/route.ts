import { env } from "cloudflare:workers";
import {
  enforceRateLimit,
  jsonNoStore,
  rejectCrossOrigin,
  validateDeclaredBodySize,
} from "../../../lib/server/requestSecurity";
import {
  INTERNAL_BODY_LENGTH_HEADER,
  isSupportedAudioMediaType,
  MAXIMUM_AUDIO_BYTES,
  normalizeAudioMediaType,
  parseTranscriptionResponse,
} from "../../../shared/transcriptionContract";

export const runtime = "edge";

export async function POST(request: Request) {
  const originError = rejectCrossOrigin(request);
  if (originError) return originError;

  const size = validateDeclaredBodySize(request, MAXIMUM_AUDIO_BYTES);
  if (!size.ok) return size.response;
  const mediaType = normalizeAudioMediaType(request.headers.get("content-type") ?? "");
  if (!isSupportedAudioMediaType(mediaType)) {
    return jsonNoStore({ error: "A supported audio Content-Type is required." }, { status: 415 });
  }

  const rateError = await enforceRateLimit(request, "TRANSCRIPTION_RATE_LIMITER");
  if (rateError) return rateError;

  const apiKey = process.env.PARAKEET_API_KEY;
  const bindings = env as unknown as { ASR?: Fetcher };
  if (!bindings.ASR || !apiKey || !request.body) {
    return jsonNoStore({ error: "Transcription is unavailable." }, { status: 503 });
  }

  let response: Response;
  try {
    response = await bindings.ASR.fetch(new Request("https://asr.internal/v1/transcriptions", {
      method: "POST",
      headers: {
        authorization: `Bearer ${apiKey}`,
        "content-type": mediaType,
        [INTERNAL_BODY_LENGTH_HEADER]: String(size.bytes),
      },
      body: request.body,
      signal: request.signal,
    }));
  } catch {
    return jsonNoStore({ error: "Transcription inference failed." }, { status: 502 });
  }

  if (!response.ok) {
    const status = response.status === 400 || response.status === 413 || response.status === 415 || response.status === 429
      ? response.status
      : 502;
    return jsonNoStore({ error: "Transcription inference failed." }, { status });
  }

  if (!response.headers.get("content-type")?.toLowerCase().startsWith("application/json")) {
    return jsonNoStore({ error: "Transcription inference failed." }, { status: 502 });
  }

  try {
    const result = parseTranscriptionResponse(await response.json());
    if (!result) return jsonNoStore({ error: "Transcription inference failed." }, { status: 502 });
    return jsonNoStore(result);
  } catch {
    return jsonNoStore({ error: "Transcription inference failed." }, { status: 502 });
  }
}
