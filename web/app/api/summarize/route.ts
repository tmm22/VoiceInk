import { env } from "cloudflare:workers";
import { enforceRateLimit, jsonNoStore, readBoundedJson, rejectCrossOrigin } from "../../../lib/server/requestSecurity";
import { INTERNAL_CLIENT_KEY_HEADER } from "../../../shared/transcriptionContract";
import { pseudonymousClientKey } from "../../../lib/server/clientKey";

export const runtime = "edge";

export async function POST(request: Request) {
  const originError = rejectCrossOrigin(request);
  if (originError) return originError;
  const rateError = await enforceRateLimit(request, "SUMMARY_RATE_LIMITER");
  if (rateError) return rateError;
  const parsed = await readBoundedJson<{ text?: unknown }>(request, 70_000);
  if (!parsed.ok) return parsed.response;
  const text = typeof parsed.value.text === "string" ? parsed.value.text.trim() : "";
  if (!text) return jsonNoStore({ error: "Transcript text is required" }, { status: 400 });
  if (text.length > 60_000) return jsonNoStore({ error: "Transcript is too long to summarize" }, { status: 413 });
  const apiKey = process.env.PARAKEET_API_KEY;
  const pseudonymSecret = process.env.HISTORY_ENCRYPTION_KEY;
  const bindings = env as unknown as { ASR?: Fetcher };
  if (!bindings.ASR || !apiKey || !pseudonymSecret) return jsonNoStore({ error: "Summarization is unavailable" }, { status: 503 });

  let response: Response;
  try {
    response = await bindings.ASR.fetch(new Request("https://asr.internal/v1/summaries", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        authorization: `Bearer ${apiKey}`,
        [INTERNAL_CLIENT_KEY_HEADER]: await pseudonymousClientKey(pseudonymSecret, request.headers.get("cf-connecting-ip"), Date.now()),
      },
      body: JSON.stringify({ text }),
      signal: request.signal,
    }));
  } catch {
    return jsonNoStore({ error: "Summary generation failed" }, { status: 502 });
  }
  if (!response.ok) {
    return jsonNoStore({ error: "Summary generation failed" }, { status: response.status === 429 ? 429 : 502 });
  }
  try {
    const result = await response.json() as { summary?: unknown; model?: unknown };
    if (typeof result.summary !== "string" || !result.summary.trim() || result.summary.length > 20_000
      || result.model !== "llama-3.2-3b-instruct") throw new Error("invalid response");
    return jsonNoStore({ summary: result.summary.trim(), model: result.model });
  } catch {
    return jsonNoStore({ error: "Summary generation failed" }, { status: 502 });
  }
}
