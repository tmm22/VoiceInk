import { TEXT_GENERATION_FLAT_MICROS } from "./budget.ts";
import { admissionDenial, reserveSpendLogged, type AsrEnv } from "./admission.ts";
import { enhancementSystemPrompt, isEnhancementMode, SUMMARY_SYSTEM_PROMPT } from "./enhancement.ts";
import { json, requestClientKey } from "./http.ts";
import { commitSpend, releaseSpend } from "./ledgerClient.ts";

function generatedText(result: unknown) {
  if (!result || typeof result !== "object") return "";
  const output = result as { response?: unknown; text?: unknown };
  const value = typeof output.response === "string" ? output.response : output.text;
  return typeof value === "string" ? value.trim() : "";
}

function fallbackSummary(transcript: string) {
  const sentences = (transcript.match(/[^.!?\n]+[.!?]?/g) ?? [transcript])
    .map((sentence) => sentence.trim())
    .filter(Boolean);
  return sentences.slice(0, 4).join(" ");
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

  const admission = await reserveSpendLogged(env, request, {
    estimateMicros: TEXT_GENERATION_FLAT_MICROS,
    secondsEstimate: 0,
    clientKey: requestClientKey(request),
  });
  if (!admission.ok) return admissionDenial(admission);

  let result: unknown;
  try {
    result = await env.AI.run("@cf/meta/llama-3.2-3b-instruct", {
      messages: [
        {
          role: "system",
          content: enhancementSystemPrompt(body.mode),
        },
        { role: "user", content: JSON.stringify({ source_text: text }) },
      ],
      max_tokens: 3_000,
      temperature: 0.2,
    }, { signal: request.signal });
  } catch {
    executionContext.waitUntil(releaseSpend(env, admission.id));
    return json({ error: "Enhancement generation failed" }, { status: 502 });
  }
  executionContext.waitUntil(commitSpend(env, admission.id, TEXT_GENERATION_FLAT_MICROS, 0));
  const enhanced = generatedText(result);
  if (!enhanced || enhanced.length > 30_000) return json({ error: "Enhancement generation failed" }, { status: 502 });
  return json({ enhanced, mode: body.mode, model: "llama-3.2-3b-instruct" });
}

export async function handleSummary(request: Request, env: AsrEnv, executionContext: ExecutionContext): Promise<Response> {
  if (Number(request.headers.get("content-length") ?? 0) > 70_000) return json({ error: "Request body is too large" }, { status: 413 });
  let body: { text?: string };
  try { body = await request.json() as { text?: string }; }
  catch { return json({ error: "Valid JSON is required" }, { status: 400 }); }
  const text = body.text?.trim();
  if (!text) return json({ error: "Transcript text is required" }, { status: 400 });
  if (text.length > 60_000) return json({ error: "Transcript is too long to summarize" }, { status: 413 });

  const admission = await reserveSpendLogged(env, request, {
    estimateMicros: TEXT_GENERATION_FLAT_MICROS,
    secondsEstimate: 0,
    clientKey: requestClientKey(request),
  });
  if (!admission.ok) return admissionDenial(admission);

  let result: unknown;
  try {
    result = await env.AI.run("@cf/meta/llama-3.2-3b-instruct", {
      messages: [
        {
          role: "system",
          content: SUMMARY_SYSTEM_PROMPT,
        },
        { role: "user", content: JSON.stringify({ source_text: text }) },
      ],
      max_tokens: 500,
      temperature: 0.2,
    }, { signal: request.signal });
  } catch {
    executionContext.waitUntil(releaseSpend(env, admission.id));
    return json({ error: "Summary generation failed" }, { status: 502 });
  }
  executionContext.waitUntil(commitSpend(env, admission.id, TEXT_GENERATION_FLAT_MICROS, 0));
  const generated = generatedText(result);
  const rejectedTranscript = /(?:no|not)\s+(?:transcript|text)|provide\s+(?:the\s+|a\s+)?transcript/i.test(generated);
  return json({
    summary: !generated || generated.length > 20_000 || rejectedTranscript ? fallbackSummary(text) : generated,
    model: "llama-3.2-3b-instruct",
  });
}
