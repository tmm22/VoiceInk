import { env } from "cloudflare:workers";
export { rejectCrossOrigin, rejectOversizedRequest } from "./requestValidation";

type RateLimiter = { limit(options: { key: string }): Promise<{ success: boolean }> };

export async function enforceRateLimit(request: Request, binding: "AI_RATE_LIMITER" | "IMPORT_RATE_LIMITER" | "HISTORY_RATE_LIMITER") {
  const limiter = (env as unknown as Record<string, RateLimiter | undefined>)[binding];
  if (!limiter) {
    if (new URL(request.url).hostname.endsWith(".chatgpt.site")) return null;
    return Response.json({ error: "Request protection is unavailable." }, { status: 503 });
  }
  const key = request.headers.get("cf-connecting-ip") ?? "unknown";
  const { success } = await limiter.limit({ key });
  return success ? null : Response.json({ error: "Too many requests. Please wait and try again." }, { status: 429 });
}
