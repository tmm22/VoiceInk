import { env } from "cloudflare:workers";
import { enforceRateLimit, rejectCrossOrigin, rejectOversizedRequest } from "../../../lib/server/requestSecurity";

export const runtime = "edge";

const allowedModes = new Set(["clean", "concise", "professional", "notes"]);

export async function POST(request: Request) {
  const originError = rejectCrossOrigin(request);
  if (originError) return originError;
  const oversized = rejectOversizedRequest(request, 16_000);
  if (oversized) return oversized;
  const rateError = await enforceRateLimit(request, "AI_RATE_LIMITER");
  if (rateError) return rateError;

  let body: { text?: string; mode?: string };
  try {
    body = await request.json() as { text?: string; mode?: string };
  } catch {
    return Response.json({ error: "Valid JSON is required" }, { status: 400 });
  }

  const text = body.text?.trim();
  const mode = body.mode?.trim();
  if (!text) return Response.json({ error: "Text is required" }, { status: 400 });
  if (text.length > 12_000) return Response.json({ error: "Text is too long to enhance" }, { status: 413 });
  if (!mode || !allowedModes.has(mode)) return Response.json({ error: "Choose a supported enhancement style" }, { status: 400 });

  const apiKey = process.env.PARAKEET_API_KEY;
  const bindings = env as unknown as { ASR?: Fetcher };
  if (!bindings.ASR || !apiKey) return Response.json({ error: "Text enhancement is unavailable" }, { status: 503 });

  const response = await bindings.ASR.fetch(new Request("https://asr.internal/v1/enhancements", {
    method: "POST",
    headers: {
      authorization: `Bearer ${apiKey}`,
      "content-type": "application/json",
    },
    body: JSON.stringify({ text, mode }),
  }));
  if (!response.ok) {
    const status = response.status >= 400 && response.status < 500 ? response.status : 502;
    return Response.json({ error: "Text enhancement failed" }, { status });
  }
  return new Response(response.body, {
    status: 200,
    headers: { "content-type": "application/json" },
  });
}
