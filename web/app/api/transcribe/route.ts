import { env } from "cloudflare:workers";
import { enforceRateLimit, rejectCrossOrigin, rejectOversizedRequest } from "../../../lib/server/requestSecurity";

export const runtime = "edge";

export async function POST(request: Request) {
  const originError = rejectCrossOrigin(request);
  if (originError) return originError;
  const oversized = rejectOversizedRequest(request, 25 * 1024 * 1024);
  if (oversized) return oversized;
  const rateError = await enforceRateLimit(request, "AI_RATE_LIMITER");
  if (rateError) return rateError;
  const endpoint = process.env.PARAKEET_API_URL;
  const apiKey = process.env.PARAKEET_API_KEY;
  const bindings = env as unknown as { ASR?: Fetcher };

  if (!endpoint && !bindings.ASR) {
    return Response.json({ error: "Transcription is unavailable." }, { status: 503 });
  }
  let formData: FormData;
  try { formData = await request.formData(); }
  catch { return Response.json({ error: "A valid audio upload is required." }, { status: 400 }); }
  const target = endpoint
    ? `${endpoint.replace(/\/$/, "")}/v1/transcriptions`
    : "https://asr.internal/v1/transcriptions";
  const init: RequestInit = {
    method: "POST",
    headers: apiKey ? { Authorization: `Bearer ${apiKey}` } : undefined,
    body: formData,
  };
  const response = bindings.ASR
    ? await bindings.ASR.fetch(new Request(target, init))
    : await fetch(target, init);

  if (!response.ok) {
    return Response.json(
      { error: "Transcription inference failed", upstreamStatus: response.status },
      { status: response.status >= 400 && response.status < 500 ? response.status : 502 },
    );
  }

  return new Response(response.body, {
    status: 200,
    headers: { "content-type": response.headers.get("content-type") ?? "application/json" },
  });
}
