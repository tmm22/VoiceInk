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

## Build and drift examples

- `index.js` is valid; `index 2.js` fails the duplicate-artifact check.
- The public web Worker may use the private `ASR` service binding; an external ASR URL fallback fails the configuration contract.
- `voiceink-asr` must keep `workers_dev: false` and `preview_urls: false`.
- A model, size, rate-limit, origin, privacy, or topology change must update `README.md`, `docs/DEPLOYMENT.md`, `docs/COSTS.md`, `AGENTS.md`, tests, and deployment config together.
- Dependency audits fail on any new high/critical advisory. The only temporary exception is exact, transitive `vinext`/`image-size` exposure recorded in `scripts/check-audit.mjs`, with an expiry date.

## Operations outside source control

Binding-level counters protect an edge location but are not durable accounting. Production operators must also configure Workers AI and billing alerts, a tested inference kill switch, WAF rules, and server-validated Turnstile for sustained anonymous abuse. Do not log user content while investigating an alert; use bounded request IDs, status, model, duration, and byte counts.
