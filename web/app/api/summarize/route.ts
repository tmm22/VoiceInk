import { env } from "cloudflare:workers";
import { enforceRateLimit, rejectCrossOrigin } from "../../../lib/server/requestSecurity";

export const runtime = "edge";

export async function POST(request: Request) {
  const originError = rejectCrossOrigin(request);
  if (originError) return originError;
  const rateError = await enforceRateLimit(request, "AI_RATE_LIMITER");
  if (rateError) return rateError;
  const apiKey = process.env.PARAKEET_API_KEY;
  const bindings = env as unknown as { ASR?: Fetcher };
  if (!bindings.ASR) return Response.json({ error: "Summarization is unavailable" }, { status: 503 });

  const body = await request.text();
  const response = await bindings.ASR.fetch(new Request("https://asr.internal/v1/summaries", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      ...(apiKey ? { authorization: `Bearer ${apiKey}` } : {}),
    },
    body,
  }));
  if (!response.ok) {
    return Response.json({ error: "Summary generation failed", upstreamStatus: response.status }, { status: response.status });
  }
  return new Response(response.body, {
    status: 200,
    headers: { "content-type": "application/json" },
  });
}
