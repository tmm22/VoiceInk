// Turnstile siteverify for the costly transcription route. Pure Web-API module
// (no cloudflare:workers import) so the verification logic stays unit-testable.

export type TurnstileVerification =
  | { ok: true }
  | { ok: false; status: number; error: string };

type SiteverifyResponse = {
  success?: boolean;
  action?: string;
  hostname?: string;
  "error-codes"?: string[];
};

const SITEVERIFY_URL = "https://challenges.cloudflare.com/turnstile/v0/siteverify";
const MAXIMUM_TOKEN_LENGTH = 2_048;
const ATTEMPT_TIMEOUT_MS = 5_000;

// The always-pass test secret reports hostname "example.com"; a widget whose
// domains are restricted to the production hostname can never legitimately
// produce that value, so allowing it keeps dev/CI on the identical code path.
const TEST_KEY_HOSTNAME = "example.com";

const FAILED = { ok: false, status: 403, error: "Verification failed. Please try again." } as const;
const UNAVAILABLE = { ok: false, status: 503, error: "Verification is unavailable." } as const;

// The caller's IP is deliberately never forwarded to siteverify: `remoteip` is
// optional in the Turnstile API and omitting it keeps client addresses from
// leaving this Worker.
export async function verifyTurnstileToken(options: {
  token: string | null;
  secret: string;
  expectedHostname: string;
  expectedAction: string;
  fetcher?: typeof fetch;
}): Promise<TurnstileVerification> {
  const { token, secret, expectedHostname, expectedAction } = options;
  const fetcher = options.fetcher ?? fetch;
  if (!token || token.length > MAXIMUM_TOKEN_LENGTH) return FAILED;

  // The idempotency key makes a retry after a transient siteverify failure safe
  // even though tokens are single-use.
  const idempotencyKey = crypto.randomUUID();
  let result: SiteverifyResponse | null = null;
  for (let attempt = 0; attempt < 2 && !result; attempt += 1) {
    try {
      const response = await fetcher(SITEVERIFY_URL, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          secret,
          response: token,
          idempotency_key: idempotencyKey,
        }),
        signal: AbortSignal.timeout(ATTEMPT_TIMEOUT_MS),
      });
      if (!response.ok) continue;
      const parsed = await response.json() as SiteverifyResponse;
      if (parsed.success === false && (parsed["error-codes"] ?? []).includes("internal-error")) continue;
      result = parsed;
    } catch {
      // Transient failure; one retry with the same idempotency key.
    }
  }
  if (!result) return UNAVAILABLE;

  if (result.success !== true) {
    const codes = result["error-codes"] ?? [];
    const configurationError = codes.some((code) =>
      code === "invalid-input-secret" || code === "missing-input-secret" || code === "bad-request");
    return configurationError ? UNAVAILABLE : FAILED;
  }
  // Require the hostname the widget is domain-locked to; absence or mismatch is
  // a rejection, never a skipped check. The test secret reports example.com.
  if (result.hostname !== expectedHostname && result.hostname !== TEST_KEY_HOSTNAME) return FAILED;
  // The widget always stamps the action, so a matching value is required; an
  // absent action means the token did not come from our transcription flow.
  if (result.action !== expectedAction) return FAILED;
  return { ok: true };
}
