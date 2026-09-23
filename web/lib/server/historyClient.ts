import { ConvexHttpClient } from "convex/browser";
import { enforceRateLimit, jsonNoStore, rejectCrossOrigin } from "./requestSecurity";
import { loadHistoryKey } from "./historyCrypto";

// Shared entry for every /api/history method: origin and rate-limit checks,
// then a Convex client carrying the caller's bearer token (if any) and the
// imported history key. Any missing piece fails closed.

export function requestFailure() {
  const requestId = crypto.randomUUID();
  return jsonNoStore(
    { error: "History is temporarily unavailable.", requestId },
    { status: 503, headers: { "x-request-id": requestId } },
  );
}

export type SecuredClient =
  | { error: Response; client?: never; serviceSecret?: never; historyKey?: never; hasToken?: never }
  | { error?: never; client: ConvexHttpClient; serviceSecret: string; historyKey: CryptoKey; hasToken: boolean };

// History is stored encrypted at rest: transcripts and summaries are sealed in
// this Worker with HISTORY_ENCRYPTION_KEY before they reach Convex and opened
// only on the way back out. A missing key fails closed, like a missing service
// secret.
export async function securedClient(request: Request): Promise<SecuredClient> {
  const originError = rejectCrossOrigin(request);
  if (originError) return { error: originError };
  const rateError = await enforceRateLimit(request, "HISTORY_RATE_LIMITER");
  if (rateError) return { error: rateError };

  const convexUrl = process.env.NEXT_PUBLIC_CONVEX_URL;
  const serviceSecret = process.env.CONVEX_WEB_API_SECRET;
  const keyPromise = loadHistoryKey(process.env.HISTORY_ENCRYPTION_KEY);
  if (!convexUrl || !serviceSecret || !keyPromise) {
    return { error: jsonNoStore({ error: "History is unavailable." }, { status: 503 }) };
  }
  const client = new ConvexHttpClient(convexUrl);
  const authorization = request.headers.get("authorization");
  const hasToken = authorization?.startsWith("Bearer ") ?? false;
  if (hasToken) client.setAuth(authorization!.slice(7));
  return { client, serviceSecret, historyKey: await keyPromise, hasToken };
}
