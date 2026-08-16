# Web hardening contracts

These guardrails are executable product policy. Run `npm run check` before deployment and the non-mutating `npm run test:production -- --base-url https://v.paul.im` afterward.

## Request examples

Allowed JSON request:

```http
POST /api/enhance
Origin: https://v.paul.im
Content-Type: application/json
Content-Length: 37

{"text":"meeting notes","mode":"clean"}
```

Rejected examples include a missing, negative, malformed, mismatched, or oversized `Content-Length`; a non-JSON content type; `Sec-Fetch-Site: cross-site`; an unsupported audio MIME or container signature; and any request made while its route-specific rate-limit binding is unavailable.

Allowed cache policy:

```text
/assets/<content-hash>.*  public, max-age=31536000, immutable
/ and HTML               no-store
/api/**                  private, no-store, max-age=0, must-revalidate
```

Forbidden user-content caching includes the Cache API, AI Gateway response caching, shared transcript hashes, KV/R2 transcript copies, and CDN caching of audio, transcripts, summaries, imports, or enhancement output. Idempotency is actor-scoped through operation IDs on the canonical Convex record; it is not a cross-user result cache.

## Abuse and spend ceilings

- Every Workers AI call in `voiceink-asr` must be admitted by the `SPEND_LEDGER` durable object before inference runs; a failed, timed-out, or missing ledger call is a denial, never an allow.
- Transcription admissions price the declared bytes at the worst-case low bitrate before any model runs, combined across both transcription models (nova-3 plus the whisper fallback, since non-English audio runs both), then settle to the provider-reported duration and the models that actually ran, clamped so a request can never commit more than it reserved. Buffering and inference share a four-minute deadline, below the six-minute reservation expiry, so a live request always settles before its reservation can be reclaimed and a stalled or trickled upload cannot pin the worker or hold budget indefinitely.
- The default ceilings are `DAILY_SPEND_LIMIT_MICROS = 10000000` (10.00 USD per UTC day across all inference; it must exceed the ≈ 4.79 USD worst-case reservation for one 24 MB upload) and `DAILY_CLIENT_AUDIO_SECONDS = 7200` (two hours of transcribed audio per client IP per UTC day; a single request's admission estimate is clamped to this quota so worst-case byte pricing cannot deny legitimate large uploads outright). Raising them is a deliberate `wrangler.jsonc` change, not a dashboard toggle.
- `/api/transcribe` must verify a single-use Turnstile token (`x-voiceink-turnstile`) whenever `TURNSTILE_SECRET_KEY` is configured, before any audio is streamed upstream. Production must configure it; the official always-pass test keys cover local development on the identical code path.
- Anonymous visitors are capped at 10 minutes of audio per recording or upload in the browser; signed-in users keep 30-minute recordings and 2-hour uploads. The per-IP daily ledger cap backs the client-side tiers server-side.
- Do not log Turnstile tokens, siteverify responses beyond error codes, ledger amounts alongside user identifiers, or any transcript content in these paths.

## Build and drift examples

- `index.js` is valid; `index 2.js` fails the duplicate-artifact check.
- The public web Worker may use the private `ASR` service binding; an external ASR URL fallback fails the configuration contract.
- `voiceink-asr` must keep `workers_dev: false` and `preview_urls: false`.
- A model, size, rate-limit, origin, privacy, or topology change must update `README.md`, `docs/DEPLOYMENT.md`, `docs/COSTS.md`, `AGENTS.md`, tests, and deployment config together.
- Dependency audits fail on any new high/critical advisory. The only temporary exception is exact, transitive `vinext`/`image-size` exposure recorded in `scripts/check-audit.mjs`, with an expiry date.

## Operations outside source control

Binding-level counters protect an edge location but are not durable accounting; the `SPEND_LEDGER` durable object is the global daily cap, and Turnstile is the anonymous-abuse gate. Production operators must additionally maintain the zone-level checklist below. Do not log user content while investigating an alert; use bounded request IDs, status, model, duration, and byte counts.

Cloudflare dashboard checklist for the `v.paul.im` zone (free plan realities noted):

1. Keep the DNS record proxied (orange cloud) with SSL/TLS Full (strict); zone protections only apply to proxied traffic, and nothing below protects a `workers.dev` route (both Workers keep `workers_dev: false`).
2. Use the single free rate limiting rule on the costly path: expression `(http.request.uri.path eq "/api/transcribe")`, counted per IP, more than 5 requests per 10 seconds, action Block for 10 seconds. Free-plan rules cannot match the HTTP method, use regex, or serve challenges; the in-Worker limits remain authoritative.
3. Add a WAF custom rule blocking `/api/*` requests whose Host header is not `v.paul.im` (defense in depth for the single-origin invariant). Keep challenge actions off `/api/*` paths: a Managed Challenge served to a background `fetch()` is an opaque failure the app cannot solve.
4. Bot Fight Mode is optional and has no bypass mechanism on any plan. If enabled, review Security → Events within 24 hours; `tests/production-smoke.mjs` runs on Node and will look like a bot, so expect challenge noise or disable Bot Fight Mode if legitimate traffic is affected. Confirm the injected `/cdn-cgi/challenge-platform/` script is compatible with the CSP before enabling.
5. Create at least one Billing → Billable Usage budget alert (dollar threshold, e-mails the account address). Alerts are informational, fire once per billing period, and never pause usage — the spend ledger is the enforcement layer.
6. "I'm Under Attack" mode is break-glass only: it challenges every visitor and breaks the app's API fetches while enabled.
7. AI Gateway was evaluated (2026-08) and deliberately not adopted for transcription: gateway behavior with streamed audio bodies is undocumented and its spend limits are token-priced, so per-minute Whisper spend may not meter. Revisit only with a staging test, `collectLog: false`, and payload logging disabled — gateway logs store full request payloads by default, which would violate the no-transcript-logging invariant.
