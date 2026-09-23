import {
  INTERNAL_BODY_LENGTH_HEADER,
  INTERNAL_CLIENT_KEY_HEADER,
  MAXIMUM_AUDIO_BYTES,
} from "../../shared/transcriptionContract.ts";

// Request/response plumbing shared by every ASR Worker endpoint.

export function requestClientKey(request: Request) {
  return request.headers.get(INTERNAL_CLIENT_KEY_HEADER) ?? "unknown";
}

// The worker-observed Cloudflare colo, so reserve-latency telemetry can be
// correlated with where the request landed relative to the ledger DO.
export function requestColo(request: Request) {
  const colo = (request.cf as { colo?: unknown } | undefined)?.colo;
  return typeof colo === "string" ? colo.slice(0, 8) : null;
}

// Length telemetry is rounded up to a coarse bucket so logs never carry an
// exact transcript size.
export function characterBucket(length: number) {
  return length === 0 ? 0 : Math.ceil(length / 250) * 250;
}

export function json(body: unknown, init: ResponseInit = {}) {
  const headers = new Headers(init.headers);
  headers.set("cache-control", "no-store");
  headers.set("pragma", "no-cache");
  headers.set("x-content-type-options", "nosniff");
  return Response.json(body, { ...init, headers });
}

export function internalBodyLength(request: Request) {
  const value = request.headers.get(INTERNAL_BODY_LENGTH_HEADER);
  if (!value || !/^[1-9]\d*$/.test(value)) return null;
  const bytes = Number(value);
  return Number.isSafeInteger(bytes) && bytes <= MAXIMUM_AUDIO_BYTES ? bytes : null;
}

export async function hasValidAuthorization(request: Request, secret: string) {
  const authorization = request.headers.get("authorization") ?? "";
  const expected = `Bearer ${secret}`;
  const encoder = new TextEncoder();
  if (!authorization || authorization.length > 512 || expected.length > 512) return false;
  try {
    const algorithm = { name: "HMAC", hash: "SHA-256" };
    const challenge = encoder.encode("voiceink-internal-auth-v1");
    const [actualKey, expectedKey] = await Promise.all([
      crypto.subtle.importKey("raw", encoder.encode(authorization), algorithm, false, ["sign"]),
      crypto.subtle.importKey("raw", encoder.encode(expected), algorithm, false, ["verify"]),
    ]);
    const actualMac = await crypto.subtle.sign("HMAC", actualKey, challenge);
    return crypto.subtle.verify("HMAC", expectedKey, actualMac, challenge);
  } catch {
    return false;
  }
}

export function logInferenceFailure(event: string, error: unknown) {
  const diagnostic = error && typeof error === "object"
    ? error as { name?: unknown; code?: unknown }
    : null;
  console.error(event, {
    errorName: typeof diagnostic?.name === "string" ? diagnostic.name.slice(0, 80) : typeof error,
    errorCode: typeof diagnostic?.code === "string" || typeof diagnostic?.code === "number"
      ? String(diagnostic.code).slice(0, 80)
      : null,
  });
}
