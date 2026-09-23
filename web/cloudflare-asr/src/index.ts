import { ENGLISH_TRANSCRIPTION_MODEL_ID, MULTILINGUAL_TRANSCRIPTION_MODEL_ID } from "../../shared/transcriptionContract.ts";
import type { AsrEnv } from "./admission.ts";
import { hasValidAuthorization, json } from "./http.ts";
import { SpendLedger } from "./spendLedger.ts";
import { handleEnhancement, handleSummary } from "./textGeneration.ts";
import { handleTranscription } from "./transcription.ts";

export { SpendLedger };
export { enhancementInstructions, isEnhancementMode } from "./enhancement.ts";

const routes: Record<string, (request: Request, env: AsrEnv, executionContext: ExecutionContext) => Promise<Response>> = {
  "/v1/enhancements": handleEnhancement,
  "/v1/summaries": handleSummary,
  "/v1/transcriptions": handleTranscription,
};

export default {
  async fetch(request: Request, env: AsrEnv, executionContext: ExecutionContext): Promise<Response> {
    if (request.method === "GET") {
      return json({
        status: "ok",
        models: {
          english: ENGLISH_TRANSCRIPTION_MODEL_ID,
          multilingual: MULTILINGUAL_TRANSCRIPTION_MODEL_ID,
        },
      });
    }

    if (request.method !== "POST") {
      return json({ error: "Method not allowed" }, { status: 405, headers: { allow: "GET, POST" } });
    }

    if (!env.ASR_API_KEY || !await hasValidAuthorization(request, env.ASR_API_KEY)) {
      return json({ error: "Unauthorized" }, { status: 401 });
    }

    const { pathname } = new URL(request.url);
    const handle = Object.hasOwn(routes, pathname) ? routes[pathname] : undefined;
    return handle ? handle(request, env, executionContext) : json({ error: "Not found" }, { status: 404 });
  },
} satisfies ExportedHandler<AsrEnv>;
