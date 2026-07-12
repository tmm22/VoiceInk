import { env } from "cloudflare:workers";

type RateLimiter = { limit(options: { key: string }): Promise<{ success: boolean }> };

export function rejectCrossOrigin(request: Request) {
  const origin = request.headers.get("origin");
  if (!origin || origin === new URL(request.url).origin) return null;
  return Response.json({ error: "Cross-origin requests are not allowed." }, { status: 403 });
}

export async function enforceRateLimit(request: Request, binding: "AI_RATE_LIMITER" | "IMPORT_RATE_LIMITER" | "HISTORY_RATE_LIMITER") {
  const limiter = (env as unknown as Record<string, RateLimiter | undefined>)[binding];
  if (!limiter) return null;
  const key = request.headers.get("cf-connecting-ip") ?? "unknown";
  const { success } = await limiter.limit({ key });
  return success ? null : Response.json({ error: "Too many requests. Please wait and try again." }, { status: 429 });
}
