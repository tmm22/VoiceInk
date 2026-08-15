import { env } from "cloudflare:workers";
import { jsonNoStore } from "./requestValidation";
export {
  jsonNoStore,
  readBoundedJson,
  readBoundedText,
  rejectCrossOrigin,
  rejectOversizedRequest,
  validateDeclaredBodySize,
  validateJsonContentType,
  validateMultipartContentType,
} from "./requestValidation";

type RateLimiter = { limit(options: { key: string }): Promise<{ success: boolean }> };

export async function enforceRateLimit(request: Request, binding:
  | "TRANSCRIPTION_RATE_LIMITER"
  | "SUMMARY_RATE_LIMITER"
  | "ENHANCEMENT_RATE_LIMITER"
  | "IMPORT_RATE_LIMITER"
  | "HISTORY_RATE_LIMITER") {
  const limiter = (env as unknown as Record<string, RateLimiter | undefined>)[binding];
  if (!limiter) {
    return jsonNoStore({ error: "Request protection is unavailable." }, { status: 503 });
  }
  const key = request.headers.get("cf-connecting-ip") ?? "unknown";
  try {
    const { success } = await limiter.limit({ key });
    return success ? null : jsonNoStore(
      { error: "Too many requests. Please wait and try again." },
      { status: 429, headers: { "retry-after": "60" } },
    );
  } catch {
    return jsonNoStore({ error: "Request protection is unavailable." }, { status: 503 });
  }
}
