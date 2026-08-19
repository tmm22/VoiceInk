import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const root = new URL("../", import.meta.url);
const source = (path) => readFile(new URL(path, root), "utf8");

test("stop is staged: stopping, verifying, transcribing with elapsed seconds, saving", async () => {
  const [page, request] = await Promise.all([
    source("app/page.tsx"),
    source("lib/transcriptionRequest.ts"),
  ]);
  // The stop click gets synchronous feedback before any async work runs.
  const stopBody = page.slice(page.indexOf("function stopRecording"), page.indexOf("async function transcribe"));
  const stopStatus = stopBody.indexOf('setStatus("stopping")');
  const stopCall = stopBody.indexOf("recorder.current.stop()");
  assert.ok(stopStatus !== -1 && stopCall !== -1 && stopStatus < stopCall, "'stopping' must be set before the recorder stops");
  // The pipeline reports real stages: token verification, then upload+inference.
  assert.match(request, /onStage\?\.\("verifying"\);/);
  assert.match(request, /onStage\?\.\("transcribing"\);/);
  assert.match(page, /setStatus\("saving"\);/);
  // Transcribing shows real elapsed seconds via the ticker pattern — never a
  // fabricated progress percentage.
  assert.match(page, /startTranscribeTicker/);
  assert.match(page, /Transcribing… \$\{transcribeElapsed\}s/);
  assert.doesNotMatch(page, /%\`|progressPercent|fakeProgress/);
});

test("the Convex token overlaps inference and the saved row is prepended locally", async () => {
  const page = await source("app/page.tsx");
  const body = page.slice(page.indexOf("async function transcribe"), page.indexOf("async function uploadAudio"));
  const tokenStart = body.indexOf("const convexToken = account.getConvexToken()");
  const transcriptionCall = body.indexOf("await requestTranscription(");
  assert.ok(tokenStart !== -1 && transcriptionCall !== -1 && tokenStart < transcriptionCall, "the token fetch must start before the transcription await");
  // The early fetch is a cache warm-up only. The save path must fetch its own
  // fresh token AFTER inference: Clerk session JWTs live about a minute, so a
  // token resolved at transcription start would be expired server-side after
  // a long transcription and Convex would silently file the row as anonymous.
  const saveTokenFetch = body.indexOf("const token = await account.getConvexToken()", transcriptionCall);
  assert.ok(saveTokenFetch !== -1, "the save path must await a fresh account.getConvexToken() after inference");
  assert.doesNotMatch(body, /await convexToken\b/, "the warmed-up token promise must never be consumed at save time");
  // After the save returns, the constructed row lands in state directly
  // instead of a full history refetch, and duplicates are guarded.
  assert.match(body, /status: "complete", createdAt: Date\.now\(\)/);
  assert.match(body, /\[savedItem, \.\.\.items\]/);
  assert.match(body, /items\.some\(\(item\) => item\._id === savedId\)/);
  assert.doesNotMatch(body, /await refreshHistory\(\)/);
  // A summary generated while the save is in flight serializes on its promise.
  assert.match(body, /pendingSave\.current = savePromise/);
});

test("summaries are revealed as soon as generated; persistence is non-blocking", async () => {
  const hook = await source("app/use-transcript-summary.ts");
  const generate = hook.slice(hook.indexOf("async function summarizeText"), hook.indexOf("async function persistSummary"));
  const revealed = generate.indexOf("setSummary(generatedSummary)");
  const persisted = generate.indexOf("void persistSummary(");
  assert.ok(revealed !== -1 && persisted !== -1 && revealed < persisted, "the summary must be shown before persistence starts");
  assert.doesNotMatch(generate, /await persistSummary/, "persistence must not block the loading state");
  // A failed background save surfaces a notice instead of silently dropping.
  assert.match(hook, /setSummaryNotice\("The summary is shown here but could not be saved to history\."\);/);
  // The PATCH attaches to the in-flight transcript save when no id exists yet.
  assert.match(hook, /transcriptionId \?\? \(pendingSavedId \? await pendingSavedId : null\)/);
});

test("loading placeholders are shimmer-only with reserved height, never readable text", async () => {
  const [page, enhancement, css] = await Promise.all([
    source("app/page.tsx"),
    source("app/ai-enhancement.tsx"),
    source("app/globals.css"),
  ]);
  // Summary and rewrite loading states render bare shimmer bars.
  assert.match(page, /className="result-placeholder" role="status" aria-label="Summarizing"><span \/><span \/><span \/><\/div>/);
  assert.match(enhancement, /className="result-placeholder" role="status" aria-label="Rewriting transcript"><span \/><span \/><span \/><\/div>/);
  // No placeholder copy that could be mistaken for generated content.
  assert.doesNotMatch(page, /summary-loading/);
  // The containers reserve the same min-height as the result textareas so
  // nothing shifts when real content lands.
  assert.match(css, /\.result-placeholder \{[^}]*min-height:125px/);
  assert.match(css, /\.enhancement-result \.result-placeholder \{ min-height:150px; \}/);
  assert.match(css, /\.result-placeholder span[^}]*animation:history-skeleton-shimmer/);
  // Copy feedback is the consistent 1.5s "Copied" swap in both places.
  assert.match(page, /\{summaryCopied \? "Copied" : "Copy"\}/);
  assert.match(enhancement, /\{copied \? "Copied" : "Copy"\}/);
});
