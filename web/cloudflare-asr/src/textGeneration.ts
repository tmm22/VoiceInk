import { TEXT_GENERATION_MODEL_ID, TEXT_GENERATION_MODEL_NAME } from "../../shared/textGenerationContract.ts";
import { actualTextGenerationMicros, estimateTextGenerationMicros } from "./budget.ts";
import { admissionDenial, reserveSpendLogged, type AsrEnv } from "./admission.ts";
import { enhancementSystemPrompt, isEnhancementMode, SUMMARY_SYSTEM_PROMPT } from "./enhancement.ts";
import { json, requestClientKey } from "./http.ts";
import { commitSpend, releaseSpend } from "./ledgerClient.ts";

// Accepts the OpenAI-style chat shape Gemma returns (choices[0].message.content)
// and the older { response } / { text } shapes.
export function generatedText(result: unknown) {
  if (!result || typeof result !== "object") return "";
  const output = result as { response?: unknown; text?: unknown; choices?: unknown };
  const choice = Array.isArray(output.choices) ? output.choices[0] as { message?: { content?: unknown } } | undefined : undefined;
  const value = typeof choice?.message?.content === "string"
    ? choice.message.content
    : typeof output.response === "string" ? output.response : output.text;
  return typeof value === "string" ? value.trim() : "";
}

function fallbackSummary(transcript: string) {
  const sentences = (transcript.match(/[^.!?\n]+[.!?]?/g) ?? [transcript])
    .map((sentence) => sentence.trim())
    .filter(Boolean);
  return sentences.slice(0, 4).join(" ");
}

const utf8 = new TextEncoder();

type TextRun = { ok: true; text: string } | { ok: false; response: Response };

// One admitted text-generation call: reserve the worst case for this input,
// run the model with reasoning off (so every token is answer text and the
// cost is bounded by max_completion_tokens), then settle to reported usage.
async function runTextModel(
  request: Request,
  env: AsrEnv,
  executionContext: ExecutionContext,
  call: { system: string; text: string; maxOutputTokens: number; failure: string },
): Promise<TextRun> {
  const userContent = JSON.stringify({ source_text: call.text });
  const reservedMicros = estimateTextGenerationMicros(utf8.encode(call.system + userContent).byteLength, call.maxOutputTokens);
  const admission = await reserveSpendLogged(env, request, {
    estimateMicros: reservedMicros,
    secondsEstimate: 0,
    clientKey: requestClientKey(request),
  });
  if (!admission.ok) return { ok: false, response: admissionDenial(admission) };

  let result: unknown;
  try {
    result = await env.AI.run(TEXT_GENERATION_MODEL_ID, {
      messages: [
        { role: "system", content: call.system },
        { role: "user", content: userContent },
      ],
      max_completion_tokens: call.maxOutputTokens,
      temperature: 0.2,
      chat_template_kwargs: { enable_thinking: false },
    }, { signal: request.signal });
  } catch {
    executionContext.waitUntil(releaseSpend(env, admission.id));
    return { ok: false, response: json({ error: call.failure }, { status: 502 }) };
  }
  const usage = result && typeof result === "object" ? (result as { usage?: unknown }).usage : undefined;
  executionContext.waitUntil(commitSpend(env, admission.id, actualTextGenerationMicros(usage, reservedMicros), 0));
  return { ok: true, text: generatedText(result) };
}

export async function handleEnhancement(request: Request, env: AsrEnv, executionContext: ExecutionContext): Promise<Response> {
  if (Number(request.headers.get("content-length") ?? 0) > 16_000) return json({ error: "Request body is too large" }, { status: 413 });
  let body: { text?: string; mode?: unknown };
  try { body = await request.json() as { text?: string; mode?: unknown }; }
  catch { return json({ error: "Valid JSON is required" }, { status: 400 }); }
  const text = body.text?.trim();
  if (!text) return json({ error: "Text is required" }, { status: 400 });
  if (text.length > 12_000) return json({ error: "Text is too long to enhance" }, { status: 413 });
  if (!isEnhancementMode(body.mode)) return json({ error: "Unsupported enhancement style" }, { status: 400 });

  const run = await runTextModel(request, env, executionContext, {
    system: enhancementSystemPrompt(body.mode),
    text,
    maxOutputTokens: 3_000,
    failure: "Enhancement generation failed",
  });
  if (!run.ok) return run.response;
  const enhanced = run.text;
  if (!enhanced || enhanced.length > 30_000) return json({ error: "Enhancement generation failed" }, { status: 502 });
  return json({ enhanced, mode: body.mode, model: TEXT_GENERATION_MODEL_NAME });
}

export async function handleSummary(request: Request, env: AsrEnv, executionContext: ExecutionContext): Promise<Response> {
  if (Number(request.headers.get("content-length") ?? 0) > 70_000) return json({ error: "Request body is too large" }, { status: 413 });
  let body: { text?: string };
  try { body = await request.json() as { text?: string }; }
  catch { return json({ error: "Valid JSON is required" }, { status: 400 }); }
  const text = body.text?.trim();
  if (!text) return json({ error: "Transcript text is required" }, { status: 400 });
  if (text.length > 60_000) return json({ error: "Transcript is too long to summarize" }, { status: 413 });

  const run = await runTextModel(request, env, executionContext, {
    system: SUMMARY_SYSTEM_PROMPT,
    text,
    maxOutputTokens: 500,
    failure: "Summary generation failed",
  });
  if (!run.ok) return run.response;
  const generated = run.text;
  const rejectedTranscript = /(?:no|not)\s+(?:transcript|text)|provide\s+(?:the\s+|a\s+)?transcript/i.test(generated);
  return json({
    summary: !generated || generated.length > 20_000 || rejectedTranscript ? fallbackSummary(text) : generated,
    model: TEXT_GENERATION_MODEL_NAME,
  });
}
