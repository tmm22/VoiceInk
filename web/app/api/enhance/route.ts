import { env } from "cloudflare:workers";
import { enforceRateLimit, jsonNoStore, readBoundedJson, rejectCrossOrigin } from "../../../lib/server/requestSecurity";

export const runtime = "edge";

const allowedModes = new Set(["clean", "concise", "professional", "notes"]);

export async function POST(request: Request) {
  const originError = rejectCrossOrigin(request);
  if (originError) return originError;
  const rateError = await enforceRateLimit(request, "ENHANCEMENT_RATE_LIMITER");
  if (rateError) return rateError;

  const parsed = await readBoundedJson<{ text?: unknown; mode?: unknown }>(request, 16_000);
  if (!parsed.ok) return parsed.response;
  const body = parsed.value;

  const text = typeof body.text === "string" ? body.text.trim() : "";
  const mode = typeof body.mode === "string" ? body.mode.trim() : "";
  if (!text) return jsonNoStore({ error: "Text is required" }, { status: 400 });
  if (text.length > 12_000) return jsonNoStore({ error: "Text is too long to enhance" }, { status: 413 });
  if (!allowedModes.has(mode)) return jsonNoStore({ error: "Choose a supported enhancement style" }, { status: 400 });

  const apiKey = process.env.PARAKEET_API_KEY;
  const bindings = env as unknown as { ASR?: Fetcher };
  if (!bindings.ASR || !apiKey) return jsonNoStore({ error: "Text enhancement is unavailable" }, { status: 503 });

  let response: Response;
  try {
    response = await bindings.ASR.fetch(new Request("https://asr.internal/v1/enhancements", {
      method: "POST",
      headers: {
        authorization: `Bearer ${apiKey}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({ text, mode }),
      signal: request.signal,
    }));
  } catch {
    return jsonNoStore({ error: "Text enhancement failed" }, { status: 502 });
  }
  if (!response.ok) {
    const status = response.status >= 400 && response.status < 500 ? response.status : 502;
    return jsonNoStore({ error: "Text enhancement failed" }, { status });
  }
  try {
    const result = await response.json() as { enhanced?: unknown; mode?: unknown; model?: unknown };
    if (typeof result.enhanced !== "string" || !result.enhanced.trim() || result.enhanced.length > 30_000
      || result.mode !== mode || result.model !== "llama-3.2-3b-instruct") throw new Error("invalid response");
    return jsonNoStore({ enhanced: result.enhanced.trim(), mode, model: result.model });
  } catch {
    return jsonNoStore({ error: "Text enhancement failed" }, { status: 502 });
  }
}
