# VoiceInk Web Agent Guide

These instructions apply to everything under `web/`. They supplement the repository-root `AGENTS.md`; when rules conflict, use this file for the web application and the root guide for shared repository policy.

## Product and production architecture

VoiceInk Web is the browser version of VoiceInk. Its production stack is:

- Next.js/React built for Cloudflare Workers with Vinext
- Cloudflare Worker `voiceink-web` for the UI and public API
- Private Cloudflare service binding `ASR` to Worker `voiceink-asr`
- Cloudflare Workers AI for transcription and summarization
- Convex for transcription, summary, retention, and account history
- Clerk production authentication for cross-device account ownership
- Browser `speechSynthesis` for device-local text-to-speech

The canonical and only production origin is `https://v.paul.im`. The `workers.dev` route is deliberately disabled. Do not re-enable a second production origin without updating Clerk, the CSP, origin checks, tests, and deployment documentation together.

Current production models:

- Transcription (English, default): `@cf/deepgram/nova-3`, invoked with language detection and smart formatting
- Transcription (non-English fallback): `@cf/openai/whisper-large-v3-turbo`, used when nova-3 detects a non-English language or nova-3 fails
- Summarization: `@cf/meta/llama-3.2-3b-instruct`

Transcription buffers the bounded audio once and may run it through both models; spend-ledger admission must always reserve the combined worst case for both.

`parakeet-service/` is an experimental self-hosted reference and is not the production transcription path. The `PARAKEET_*` Worker variable names remain only for compatibility with the original adapter.

## Core product invariants

- Recording Stop automatically uploads the in-memory audio, transcribes it, and saves the completed result to history.
- Uploaded audio uses the same real transcription pipeline as microphone recordings.
- Never return sample, demonstration, or fabricated transcript text when inference fails.
- Audio is processed in memory and is not stored by this application.
- Transcripts and summaries are separate fields on the same Convex record and share its retention policy.
- Keep the text-to-speech editor separate from the transcription editor. Moving text between them must be an explicit user action.
- Text-to-speech remains device-local through browser voices unless a future feature explicitly changes the privacy and cost model.
- The dedicated History workspace is the canonical long-form history UI; do not rebuild a second history implementation in the Studio view.
- Anonymous history expires after one hour.
- Signed-in history is owned by the verified Clerk identity and syncs across devices. Default retention is 90 days, with 7, 30, 90, 365 days, or keep-until-deleted options.
- Retention changes must apply to the complete account history through bounded/paginated work, not only the first query page.

## Authentication and data ownership

Clerk runs in production on the `paul.im` primary domain:

- Frontend API: `https://clerk.paul.im`
- Account Portal: `https://accounts.paul.im`
- Application origin: `https://v.paul.im`
- Convex issuer: `https://clerk.paul.im`

The Clerk Convex integration must remain enabled. Convex is the authorization boundary: derive account ownership exclusively from the verified Convex identity token. Never accept a browser-supplied user ID, email address, or account key as proof of ownership.

Anonymous writes must be brokered through the web Worker and authenticated to Convex with `CONVEX_WEB_API_SECRET`. Do not expose direct anonymous Convex mutations to the browser.

`NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY` is public configuration but is intentionally supplied at build/deployment time rather than committed. Do not introduce `CLERK_SECRET_KEY` unless server-side Clerk APIs genuinely require it.

## Security and abuse resistance

Every public API route must:

- Reject cross-origin browser requests
- Enforce declared and actual body-size limits before parsing the payload
- Use the appropriate Cloudflare rate-limit binding for costly or state-changing work
- Return bounded, non-sensitive error details
- Fail closed when an internal credential or required service is unavailable

Keep separate rate limits for transcription, summarization, enhancement, content imports, and history writes. The private ASR Worker must require `ASR_API_KEY` for inference. The web Worker sends the matching value through its server-only compatibility secret; rotate both sides together.

Every Workers AI call in the ASR Worker must be admitted by the `SPEND_LEDGER` durable object before inference runs (reserve worst-case, settle to actual, release on failure). A failed or unreachable ledger call is a denial, never an allow. Do not remove or bypass the daily spend ceiling or the per-client daily audio quota; changing the defaults is a deliberate `wrangler.jsonc` edit that must update docs and tests together.

`/api/transcribe` must verify a single-use Turnstile token before streaming audio upstream whenever `TURNSTILE_SECRET_KEY` is configured, and production must keep it configured. Local development uses Cloudflare's official test keys rather than a code bypass. Anonymous browser sessions get the 10-minute audio tier; signed-in users keep the full recording and upload limits.

Keep webpage import protections intact: reject private, loopback, link-local, and metadata-service destinations; revalidate redirects; apply request timeouts; cap response size; and only accept supported content types.

Production security headers live in `proxy.ts`. When Clerk domains or other browser dependencies change, update the CSP narrowly and add a regression assertion. Preserve HSTS, clickjacking protection, MIME-sniffing protection, restrictive permissions, referrer policy, `object-src 'none'`, and `frame-ancestors 'none'`.

Do not log or return transcript text, summary text, authentication tokens, secrets, full imported content, or raw provider response bodies. Metadata such as status, byte count, model name, and a non-sensitive request identifier is sufficient.

## Secrets and environment configuration

Never commit `.env*`, `.dev.vars*`, Wrangler state, deployment keys, Clerk secret keys, shared Worker secrets, or Convex service secrets. The ignore rules are defense in depth; always run the secret scanner before committing.

Secret values belong in the relevant managed environment:

- `CONVEX_WEB_API_SECRET`: web Worker and Convex production environment
- `ASR_API_KEY`: private ASR Worker
- `PARAKEET_API_KEY`: web Worker compatibility credential matching `ASR_API_KEY`
- `CLERK_JWT_ISSUER_DOMAIN`: Convex environment; not secret
- Public client URLs and the Clerk publishable key: explicit production build environment

Do not print secret values while diagnosing deployments. Prefer commands that confirm whether a variable exists without echoing its content.

## Cloudflare and Convex deployment rules

The web Worker must reach `voiceink-asr` through the private `ASR` service binding. Do not replace the binding with a fetch to the ASR Worker's public hostname.

The production web build must explicitly include:

```bash
NEXT_PUBLIC_CONVEX_URL=https://<production-deployment>.convex.cloud \
NEXT_PUBLIC_SITE_URL=https://v.paul.im \
NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY=<production-publishable-key> \
npm run build
```

Deploy the built Worker with:

```bash
npx wrangler deploy --config wrangler.production.jsonc --keep-vars
```

`--keep-vars` is required during ordinary deployments so dashboard-managed configuration is not removed. If Convex functions, schema, indexes, auth configuration, or crons change, deploy Convex production explicitly and verify the target deployment before confirming the prompt.

Keep `README.md`, `docs/DEPLOYMENT.md`, and `docs/COSTS.md` synchronized whenever architecture, providers, model names, retention, domains, secrets, rate limits, or deployment steps change.

## Testing and regression checks

Run commands from `web/`.

Before committing a normal code change:

```bash
npm run check
```

This includes type checking, linting, a production build, Node regression tests, secret scanning, and the production dependency audit. Do not weaken a check merely to make a change pass; fix the behavior or document and narrowly isolate a genuine toolchain exception.

After a production deployment:

```bash
npm run test:production -- --base-url https://v.paul.im
```

The production smoke suite must avoid paid AI calls. For changes to transcription, summarization, authentication, or persistence, also perform the smallest appropriate real end-to-end check and confirm the expected record or identity behavior.

Add or update regression coverage whenever changing:

- Cloudflare bindings, domains, routes, rate limits, or security headers
- Model names or AI endpoint contracts
- Clerk/Convex authentication and ownership logic
- Anonymous or account retention behavior
- Upload, recording, summary, history, export, import, or TTS flows
- Error behavior that must never fall back to fabricated output

Prefer behavioral tests for parsing, validation, ownership, and retention logic. Use configuration-contract tests for deployment invariants that cannot be exercised locally.

## Implementation guidance

- Use TypeScript with explicit boundary types and schema validation for untrusted inputs.
- Keep server-only code out of client bundles and never reference secrets from client components.
- Apply size limits before allocating or decoding large request bodies.
- Use abort signals/timeouts for external fetches and check cancellation where meaningful.
- Keep UI state transitions explicit for recording, uploading, transcribing, saving, summarizing, and failure states.
- Preserve accessibility: controls require meaningful labels, keyboard support, visible focus, and non-color-only status cues.
- Avoid duplicate implementations. Extract shared helpers instead of copying route validation, identity, history, or transcript-export logic.
- Keep files focused. Split a production file before it becomes difficult to review or test.

## Definition of done

A web change is complete only when the requested behavior works, relevant tests pass, secrets remain untracked, production invariants are preserved, and affected documentation is current. A deployment task additionally requires successful Cloudflare/Convex deployment as applicable and a passing smoke check against `https://v.paul.im`.
