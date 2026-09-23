# Web Performance and Architecture Plan

Status: proposal, not yet implemented. Written 2026-09-23 from an architecture survey of the
web companion (`web/`, `web/cloudflare-asr/`, `web/convex/`), re-verified against trunk
commit `39b43faa`. Each workstream is meant to become one PR. File and line references are
to that commit; re-check them before starting a workstream.

## Scope and intent

The question this answers: if the web app were rebuilt from scratch for performance, what
would be kept and what would be thrown away? The keep list is short and deliberate. The
workstreams below are the throw-away or rebuild items, ordered by user-visible payoff over
effort.

### Keep as-is

- **Raw-body upload from the browser.** `lib/transcriptionRequest.ts` posts the audio Blob as
  the request body with its real content type. No multipart, no base64, no JSON wrapping.
- **Edge route piping to the ASR worker.** `app/api/transcribe/route.ts` validates, then pipes
  `request.body` through the `ASR` service binding without materialising it.
- **The ASR worker as a private billing boundary.** Workers AI binding plus the `SpendLedger`
  Durable Object, reachable only over a service binding. Keep this trust split.
- **One shared transcription contract.** `shared/transcriptionContract.ts` is imported by the
  browser, the edge route and the ASR worker. Routing constants live once.
- **Envelope encryption design.** Per-record HKDF subkeys with owner context bound into the
  derivation, key held only in the web worker. The per-page cost is tuned in W5, the design
  stays.
- **Small dependency footprint.** Five runtime packages, no icon library, no utility belt.

---

## W1. Start inference before the upload finishes (ASR worker)

**Problem.** `cloudflare-asr/src/index.ts:124` (`bufferAudio`) reads the whole request body into
chunks, copies them into one `Uint8Array` (up to 24 MB), then re-wraps that array as a new
stream for each `env.AI.run` call. Peak memory is about twice the audio size and inference
cannot begin until the last byte arrives. The README still describes this hop as streamed.

**Proposed change.**
1. Keep the magic-byte signature check, but perform it on the first chunk only, then hand the
   remainder of the original stream to the model. Use a `TransformStream` or `tee()` rather
   than a full copy.
2. Where two models may need the same bytes (see W2), `tee()` the stream once instead of
   buffering and re-wrapping.
3. Keep the declared-length and maximum-size guards as a counting transform so oversize uploads
   are still rejected mid-stream.
4. Update `README.md` architecture section to match reality.

**Acceptance.** A 20 MB upload shows first model-call start before upload completion in worker
logs. Memory high-water mark in `wrangler tail` drops from roughly 2x to roughly 1x audio size.
Existing `tests/transcription-contract.test.mjs` still passes; add a test for the counting
transform rejecting oversize and under-declared bodies.

**Risk.** Workers AI may internally buffer anyway for some models, which caps the latency win.
Measure before and after with a fixed 60 s sample. Medium effort.

## W2. Route language once, not twice

**Problem.** `cloudflare-asr/src/index.ts` (language routing block, around lines 300 to 400)
runs nova-3 to completion with language detection, then if the detected language is not
English, runs whisper-large-v3-turbo over the same full buffer. Non-English requests pay both
models and wait for both serially. `docs/COSTS.md` puts the combined cost at roughly 11x the
English per-minute price.

**Proposed change.** Two options, pick after a measurement spike:
- **A. Detect on a prefix.** Run nova-3 language detection on the first 8 to 10 seconds only,
  then dispatch the full audio once to the chosen model. Saves cost and latency for non-English,
  adds one short call for everyone.
- **B. Client hint.** Let the browser send a language hint from `navigator.language` or a user
  setting; skip detection when the hint is confident, fall back to A otherwise.

**Acceptance.** Non-English request runs exactly one full-length model call. English request
latency does not regress by more than the prefix-detection call. Add a routing unit test for
the nova-3 to whisper fallback decision and for `extractDeepgramTranscription` (currently
untested).

**Risk.** Prefix detection is less accurate on mixed-language or slow-start audio. Keep the
full-audio fallback when prefix confidence is low. Medium effort, depends on W1 for `tee()`.

## W3. Parse the response once

**Problem.** `parseTranscriptionResponse` from `shared/transcriptionContract.ts` runs in the ASR
worker, again in `app/api/transcribe/route.ts`, and again in the browser
(`lib/transcriptionRequest.ts`). On a long recording that is three full parses of a payload
that can reach 200k characters plus a segments array.

**Proposed change.** Validate at the trust boundary only: the ASR worker validates what the
model returned, the edge route passes the bytes through with a content-length check, the
browser trusts its own origin and does a cheap shape check (`typeof text === "string"`). Keep
the full validator available for the anonymous path if that path ever accepts third-party
input.

**Acceptance.** One `parseTranscriptionResponse` call per transcription in production traces.
Contract tests still pass. Small effort.

## W4. Remove dead scaffolding

**Problem.** Leftovers from the site-creator template and earlier experiments:
- `app/chatgpt-auth.ts` (86 lines, zero importers).
- `drizzle/meta/_journal.json` with an empty entries array (Drizzle is not used; `db/` and
  `examples/` are already gone).
- `vite.config.ts:9` reads `d1` and `r2` from `.openai/hosting.json` and conditionally wires
  bindings that are always null.
- `parakeet-service/` (FastAPI plus torch container, documented as unused) and the misnamed
  `PARAKEET_API_KEY` secret that actually authenticates the ASR worker
  (`app/api/transcribe/route.ts:50`, `docs/DEPLOYMENT.md`).
- Two worker entry points with different capabilities: dev uses `worker/index.ts` with
  `IMAGES`/`ASSETS` bindings, production uses `dist/server/index.js` without them.
- `compatibility_date` differs between the two workers (`2026-05-15` vs `2026-07-12`).

**Proposed change.** Delete the first three. Rename the secret to `ASR_API_KEY` on both sides
with a one-release fallback read of the old name, then remove the fallback. Remove
`parakeet-service/` or move it to an `archive/` folder outside the build. Align
`compatibility_date`. Decide whether dev needs the image bindings; if not, make dev use the
production entry so behaviour matches.

**Acceptance.** `npm run check` passes. `wrangler deploy --dry-run` for both workers shows the
same `compatibility_date`. No references to `PARAKEET` remain except the fallback note in
`docs/DEPLOYMENT.md`. Small effort, but the secret rename touches production config, so do it
in its own PR with a rollback note.

## W5. Cheaper history pages

**Problem.** `app/api/history/route.ts` (GET path around lines 116 to 151) does three Convex
round-trips per page (viewer context, list, retention), then up to 50 HKDF derivations and
AES-GCM decrypts per 25-row page because each record has its own salt. `resolveContext` is
re-queried on every POST and PATCH. Base64 in `lib/server/historyCrypto.ts:37-42` is a
hand-rolled per-character loop over up to 267 KB per record. The anonymous `list` in
`convex/transcriptions.ts:80-89` ignores pagination and takes 30 rows.

**Proposed change.**
1. Collapse viewer context plus retention into the `list` query response, or cache viewer
   context per request in the route handler. Target one Convex round-trip per page.
2. Decrypt only the fields the list view renders (title or first 200 characters); decrypt the
   full text on detail open. If the list needs full text, batch the HKDF derivations with
   `Promise.all` rather than sequential awaits.
3. Replace the base64 loop with `Uint8Array.fromBase64` where the runtime supports it, or a
   chunked `btoa`/`atob` fallback.
4. Give the anonymous path the same pagination contract as the signed-in path.

**Acceptance.** History page TTFB measured in `tests/production-smoke.mjs` drops; record the
before and after number in the PR. `tests/history-crypto.test.mjs` still passes; add a test for
the base64 replacement against the old implementation on random inputs.

**Risk.** Changing which fields the list decrypts changes what the client receives; update
`history-view.tsx` in the same PR. Medium effort.

## W6. Lighter anonymous bundle

**Problem.** Built client chunks total about 458 KB of JavaScript, of which the Clerk provider
chunk is about 153 KB. `app/providers.tsx` gates Clerk at runtime but imports it statically,
so anonymous visitors download it. `app/page.tsx:19-22` eagerly imports the TTS workspace,
history view and AI enhancement panel although only one tab is visible at a time.

**Proposed change.** Dynamic-import the Clerk provider only when a sign-in affordance is used
or a session cookie is present. Lazy-load the three non-default tabs with `React.lazy` and a
suspense fallback. Verify with `vinext build` output sizes.

**Acceptance.** Anonymous first-load JavaScript under 250 KB. Sign-in and tab switching still
work in `tests/rendered-html.test.mjs` and a manual pass. Small to medium effort.

## W7. Split the page component and the ASR fetch handler

**Problem.** `app/page.tsx` is 486 lines with 19 `useState` and 12 `useRef` hooks driving
recording, upload, transcription, summary, history, retention, theme and tabs.
`cloudflare-asr/src/index.ts` is 449 lines with three unrelated endpoints and inline system
prompts in one `fetch`. `loadMoreHistory` dedupes with an O(n·m) nested scan (`page.tsx:98`).

**Proposed change.** Extract `useRecordingSession`, `useTranscriptionUpload` and
`useHistoryFeed` hooks and move the prompts in the ASR worker into `enhancement.ts` next to the
existing ones; give each endpoint its own module with a small router. Replace the dedupe scan
with a `Set` of ids.

**Acceptance.** No file over 250 lines in `app/` or `cloudflare-asr/src/`. Behaviour unchanged;
the existing test suite is the regression gate. Medium effort, no user-visible change, so
schedule after W1 to W6.

## W8. Close the Convex validation gap

**Problem.** Convex functions cannot import `shared/transcriptionContract.ts`, so
`convex/transcriptions.ts:109-111` re-inlines the model allowlist and the BCP-47 regex. They
will drift.

**Proposed change.** Generate a `convex/_generated/contractConstants.ts` from the shared module
in a prebuild script (the repo already has `scripts/` conventions and `docs:check`-style
contract tests). Add a test asserting the generated file matches the source of truth.

**Acceptance.** Adding a model to the shared contract updates Convex without a hand edit.
Small effort.

## W9. Ledger client hygiene

**Problem.** `cloudflare-asr/src/ledgerClient.ts:23` races each Durable Object call against a
`setTimeout` rejection but never clears the timer on the winning path, leaking a timer per
call. Reserve and commit both round-trip a single global `idFromName("global")` object, which
serialises every paid request.

**Proposed change.** Clear the timer in a `finally`. Measure ledger latency under load; if it
shows up, shard the ledger by day or by client bucket while keeping a daily aggregate.

**Acceptance.** No dangling timers in a unit test using fake timers. Sharding only if the
measurement justifies it. Small effort for the timer, larger for sharding.

## W10. Test the routing decision

**Problem.** The nova-3 to whisper routing, `extractDeepgramTranscription`, and the `app/api/*`
route handlers have no direct tests. Several existing tests are regex assertions over source
text rather than behaviour (`tests/config-contracts.test.mjs:96`).

**Proposed change.** Add handler-level tests with mocked `env.AI.run` for: English detected,
non-English detected, detection missing, nova-3 failure. Add route tests for
`app/api/transcribe` using a fake `ASR` binding. Do this before or alongside W1 and W2 so the
refactors have a safety net.

**Acceptance.** Each routing branch has a named test. Small to medium effort.

---

## Suggested order

| Order | Workstream | Why here |
|---|---|---|
| 1 | W10 tests | Safety net for everything below |
| 2 | W4 dead code | Cheap, reduces noise for later diffs |
| 3 | W1 streaming | Largest latency win |
| 4 | W2 routing | Largest cost win, builds on W1 |
| 5 | W3 single parse | Small, pairs naturally with W1/W2 |
| 6 | W6 bundle | Visible first-load improvement |
| 7 | W5 history | Visible on the history tab |
| 8 | W9 ledger | Correctness fix, measurement gate for more |
| 9 | W8 Convex constants | Prevents drift |
| 10 | W7 splits | Maintainability, no behaviour change |

## Open questions for the owner

1. Is the anonymous path meant to stay? W3, W5 and W6 have simpler shapes if it is removed.
2. Is Deepgram nova-3 first still the intended default for English, or should whisper be
   the single model with nova-3 as an opt-in? W2 changes shape depending on the answer.
3. Is the Parakeet container worth archiving for reference, or can it be deleted outright?
4. What first-load JavaScript budget do you want to hold the line at? W6 assumes 250 KB.

## Verification conventions

Run the full gate from `web/`: `npm run check` (typecheck, lint, doc contracts, file sizes,
tests, ASR typecheck, secret scan, audit). Use Node 22.13 and npm 10 (`npx -y node@22.13.0`).
Production smoke: `npm run test:production` after deploy. Deployment order and secrets are in
`docs/DEPLOYMENT.md`.
