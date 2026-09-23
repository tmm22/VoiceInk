import { env } from "cloudflare:workers";
import {
  enforceRateLimit,
  jsonNoStore,
  rawJsonNoStore,
  readBoundedBytes,
  rejectCrossOrigin,
  validateDeclaredBodySize,
} from "../../../lib/server/requestSecurity";
import {
  INTERNAL_BODY_LENGTH_HEADER,
  INTERNAL_CLIENT_KEY_HEADER,
  isSupportedAudioMediaType,
  LANGUAGE_HINT_HEADER,
  MAXIMUM_AUDIO_BYTES,
  normalizeAudioMediaType,
  parseLanguageHint,
  TURNSTILE_TOKEN_HEADER,
} from "../../../shared/transcriptionContract";
import { verifyTurnstileToken } from "../../../lib/server/turnstile";
import { pseudonymousClientKey } from "../../../lib/server/clientKey";
import { asrApiKey } from "../../../lib/server/asrCredential";

export const runtime = "edge";

// Headroom over the ASR Worker's own bounds: 200,000 transcript characters
// (up to 4 UTF-8 bytes each, plus JSON escaping) and up to 5,000 segments.
const MAXIMUM_TRANSCRIPTION_RESPONSE_BYTES = 4 * 1024 * 1024;

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

  // Enforced whenever the secret is configured; production must configure it.
  const turnstileSecret = process.env.TURNSTILE_SECRET_KEY;
  if (turnstileSecret) {
    const verification = await verifyTurnstileToken({
      token: request.headers.get(TURNSTILE_TOKEN_HEADER),
      secret: turnstileSecret,
      expectedHostname: new URL(request.url).hostname,
      expectedAction: "transcribe",
    });
    if (!verification.ok) {
      return jsonNoStore({ error: verification.error }, { status: verification.status });
    }
  }

  const apiKey = asrApiKey();
  const pseudonymSecret = process.env.HISTORY_ENCRYPTION_KEY;
  const bindings = env as unknown as { ASR?: Fetcher };
  if (!bindings.ASR || !apiKey || !pseudonymSecret || !request.body) {
    return jsonNoStore({ error: "Transcription is unavailable." }, { status: 503 });
  }

  const languageHint = parseLanguageHint(request.headers.get(LANGUAGE_HINT_HEADER));
  let response: Response;
  try {
    response = await bindings.ASR.fetch(new Request("https://asr.internal/v1/transcriptions", {
      method: "POST",
      headers: {
        authorization: `Bearer ${apiKey}`,
        "content-type": mediaType,
        [INTERNAL_BODY_LENGTH_HEADER]: String(size.bytes),
        [INTERNAL_CLIENT_KEY_HEADER]: await pseudonymousClientKey(pseudonymSecret, request.headers.get("cf-connecting-ip"), Date.now()),
        ...(languageHint ? { [LANGUAGE_HINT_HEADER]: languageHint } : {}),
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

  // The private ASR Worker is the validation boundary: it runs every model
  // result through parseTranscriptionResponse before answering, so this hop
  // relays the bounded bytes instead of parsing and re-serializing them.
  const body = await readBoundedBytes(response, MAXIMUM_TRANSCRIPTION_RESPONSE_BYTES);
  if (!body?.byteLength) return jsonNoStore({ error: "Transcription inference failed." }, { status: 502 });
  return rawJsonNoStore(body);
}
