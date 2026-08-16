# VoiceInk Web

VoiceInk Web is a production browser-based transcription service deployed through Cloudflare, with transcript persistence in Convex.

Completed transcripts can be enhanced on demand with four focused AI presets: clean up, concise, professional, and structured notes. Enhancement is additive and explicit—the original transcript remains unchanged until the user chooses to replace it. Text is sent only when the user requests enhancement and is processed through the same private Cloudflare Workers AI path used for summaries.

It also includes a separate device-local text-to-speech workspace adapted from the proven browser speech controller in [`tmm22/untitled-folder-2`](https://github.com/tmm22/untitled-folder-2). Users can paste or type independent narration text, or explicitly copy in a completed transcript, then read it aloud with voices installed in the current browser or operating system.

The text-to-speech workspace can also import a public article URL. The Cloudflare Worker fetches the page with redirect, size, timeout, and private-address safeguards, extracts readable article text, and loads it directly into the narration editor.

Users can switch between the original editorial theme and a native macOS-inspired appearance from the header. The original design remains the default, and the preference is stored only in the current browser.

## Production

- Web app: the `voiceink-web` Worker in the target Cloudflare account
- Transcription: Cloudflare Workers AI using `@cf/deepgram/nova-3` for English (with language detection and smart formatting) and `@cf/openai/whisper-large-v3-turbo` for detected non-English audio
- Database: the Convex deployment supplied through the build environment
- Region: Convex US East (N. Virginia)

The earlier `chatgpt.site` URL is only a private design preview. It is not the production Cloudflare deployment.

## Architecture

```text
Browser microphone
       │
       ▼
voiceink-web Cloudflare Worker
  ├─ Next.js/Vinext interface and static assets
  ├─ POST /api/transcribe
  ├─ POST /api/summarize and /api/enhance
  └─ Convex transcript mutation
       │ private Cloudflare service binding
       ▼
voiceink-asr Cloudflare Worker
       │ Workers AI binding
       ▼
Whisper Large V3 Turbo
```

Audio is streamed through both Workers without multipart materialization and is not stored by this application. The returned transcript and provider segment timings are saved to Convex after a successful transcription. Anonymous history expires after one hour and a scheduled Convex cleanup removes it. Signed-in history is owned by the authenticated Clerk identity and persists across browsers and devices. Account holders can choose automatic deletion after 7, 30, 90, or 365 days, or keep history until they delete it; the default is 90 days.

Recording is intentionally one-step: pressing Stop immediately uploads the captured audio, runs transcription, stores the completed transcript in Convex, and refreshes the on-page history. If transcription fails, the in-memory recording remains available for retry.

Existing audio can also be uploaded into the same transcription pipeline. Completed transcripts can be downloaded as plain text, SRT, or WebVTT; subtitle timings come from real provider segments, and editing a transcript clears those timings rather than exporting stale ones. A dedicated History workspace supports search across transcripts and summaries, loading an item back into the studio, sending it to narration, and ownership-checked deletion. History loads through cursor-based pagination (25 records per page with load-more) instead of a single flat fetch.

Transcript saves are idempotent: every transcription carries a client-generated operation ID, and Convex deduplicates retries through dedicated indexes so a retried save can never create a duplicate record. Retention-policy changes run as versioned migrations across the complete account history, and the scheduled cleanup holds off on records mid-migration so the two processes cannot race. All `/api/*` responses are served with `no-store`, while content-hashed static assets are cached immutably.

Completed transcripts can be summarized or enhanced on demand with Cloudflare Workers AI using `@cf/meta/llama-3.2-3b-instruct`. Summaries are editable, copyable, and can be sent to the narration workspace. Generated summaries are stored on their matching Convex transcription record and follow that record's retention policy. Enhancement results remain in the current browser session unless the user explicitly replaces the transcript and saves it through the existing history workflow.

Production API routes enforce same-origin browser requests, declared and actual byte limits, strict content types, and independent Cloudflare rate limits for transcription, summarization, enhancement, content imports, and history. Transcription additionally requires a server-verified Cloudflare Turnstile token when configured, and every Workers AI call is admitted through a durable spend ledger that enforces a global daily cost ceiling and per-client daily audio quota before inference runs. Anonymous history creation is brokered by the web Worker with a server-only secret; clients cannot write anonymous records directly to Convex. The private ASR Worker also fails closed when its shared secret is absent.

Transcript content is JSON-encoded as untrusted data and the model is instructed never to treat it as instructions. If the model incorrectly claims that no transcript was supplied, the Worker replaces that response with a deterministic extractive summary so users never see a false missing-transcript message.

## Repository layout

- `app/` — browser recorder, audio upload, automatic transcription workflow, AI enhancement, history interface, and protected API proxies
- `app/tts-workspace.tsx` — device-local text-to-speech workspace with article import
- `lib/recording.ts` — recorder MIME selection, tiered recording/upload duration caps, and safe audio-metadata reading
- `lib/turnstileClient.ts` and `lib/transcriptionRequest.ts` — invisible-first Turnstile widget driving and the token-carrying transcription request
- `lib/transcriptExport.ts` — TXT, SRT, and WebVTT transcript downloads adapted from the source project
- `lib/browserSpeech.ts` — reused system-voice discovery and playback controller
- `shared/transcriptionContract.ts` — single source of truth for model IDs, audio byte limits, and media-type validation shared by the browser, web Worker, and ASR Worker
- `cloudflare-asr/` — secured Workers AI transcription Worker
- `convex/` — schema, queries, mutations, and generated bindings
- `scripts/` — repository checks: clean build, secret scan, doc-contract drift, file-size cap, duplicate-artifact scan, and dependency-audit gate
- `public/_headers` — immutable caching for content-hashed assets, short-lived caching for named public files
- `wrangler.production.jsonc` — production web Worker and service binding
- `parakeet-service/` — experimental self-hosted Parakeet reference; not used in production

## Local development

Use Node.js 22 LTS or another version satisfying `package.json`.

```bash
npm install
npx convex dev
npm run dev
```

Clerk is optional during local development. Without `NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY`, the app runs anonymously and applies the one-hour retention policy. Production uses Clerk's production environment and publishable key on the `v.paul.im` domain; the key is supplied only while building and is not committed.

The web interface returns a service error when inference is unavailable and never substitutes demonstration text for a real transcript. Production ASR is available only through the web Worker's private service binding; local development should use Wrangler bindings rather than a public ASR URL.

## Validation

```bash
npm run check
npm run test:production -- --base-url https://v.paul.im
```

The production smoke suite is non-mutating and does not invoke paid AI. A real audio canary is a deliberate operator action and must use `https://v.paul.im/api/transcribe`.

## Deployment and costs

- [Deployment guide](docs/DEPLOYMENT.md)
- [Operating costs](docs/COSTS.md)
- [Security hardening contracts](docs/HARDENING.md)
- [Desktop-to-web feature feasibility](docs/DESKTOP_FEATURE_PARITY.md)

## Production limits

- Signed-in accounts are limited to 10 history writes per minute, 100 per day, 50 retained records, and 10 million stored transcript/summary characters
- Anonymous browsers can retain at most 30 active one-hour history records
- Signed-in recordings are capped at 30 minutes and uploads at 2 hours of audio; anonymous visitors get 10 minutes for either, enforced in the browser before upload
- A durable spend ledger in the ASR Worker caps all Workers AI inference at $10.00 per UTC day globally and 2 hours of transcribed audio per client IP per day; when the ledger cannot be reached, inference is denied
- Transcription requests require a server-verified Cloudflare Turnstile token whenever the Turnstile secret is configured (production configures it; local development uses Cloudflare's official test keys)
- Cloudflare applies separate inference, import, and history rate limits; missing production bindings fail closed

## Regression checks

Run `npm run check` before deploying. It performs TypeScript validation, linting, a clean production build, artifact and documentation drift checks, unit and contract tests, both Worker dependency audits, and a tracked-secret scan. Run `npm run test:production` for safe live checks of the custom domain, cache policy, security headers, cross-origin rejection, immutable assets, and anonymous history; it deliberately avoids paid inference.

GitHub Actions runs the complete local regression suite for every web-related push and pull request, including installing and typechecking the ASR Worker. A scheduled and manually dispatchable job runs the safe production smoke checks, and the upstream-sync workflow validates the merged tree with `npm run check` before pushing. Tests cover subtitle exports, readable article extraction, model/configuration consistency, removal of demo fallbacks, request-boundary behavior, recording behavior, Convex brokerage and quotas, retention race protection, cache and artifact contracts, documentation contracts, CSP/security headers, and deployment bindings.

## Current limitations

- Anonymous history is associated with a browser-generated client ID and retained for no more than one hour
- Account history uses the signed-in user's configurable Convex retention policy, defaulting to 90 days
- Batch transcription only; no live partial transcript stream
- System/device voices only for the initial TTS integration; cloud TTS adapters are not yet connected
- Audio uploads are limited to 24 MB at the browser, public Worker, and private ASR Worker boundaries
- AI enhancement input is limited to 12,000 characters and is processed only after an explicit request
- `PARAKEET_API_KEY` is a compatibility secret name; production inference uses Whisper Large V3 Turbo through the private `ASR` binding

Operational deployments should additionally configure billing/usage alerts, a tested inference kill switch, and WAF or Turnstile controls for sustained anonymous abuse; Cloudflare's binding-level counters are an edge pressure control rather than durable billing accounting.
