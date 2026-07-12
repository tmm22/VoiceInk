# Deployment guide

This guide describes the live production architecture as of July 12, 2026.

## Deployed services

| Component | Cloud service | Deployment |
| --- | --- | --- |
| Web UI and API | Cloudflare Workers | `voiceink-web` |
| Speech recognition | Cloudflare Workers + Workers AI | `voiceink-asr` |
| Transcript database | Convex Cloud | `bold-swan-844` |
| ASR model | Cloudflare Workers AI | `@cf/openai/whisper-large-v3-turbo` |

The public entry point is <https://voiceink-web.paul-2eb.workers.dev>. The ASR Worker is reached from the web Worker through the `ASR` service binding. Do not replace this with a fetch to its public `workers.dev` hostname: same-account Worker subrequests can fail at Cloudflare routing, and the service binding is private and does not add another request charge.

When a user stops recording, the browser automatically uploads the in-memory audio to `/api/transcribe`. A successful result is written to Convex and the history list is refreshed. Audio bytes are not stored by the application.

## Prerequisites

- Node.js 22 LTS
- npm
- A Cloudflare account with Workers AI enabled
- Wrangler authenticated with `npx wrangler login`
- A Convex account authenticated through the Convex CLI

Run all web commands from the `web/` directory unless another directory is shown.

## 1. Deploy Convex

For a first deployment:

```bash
npx convex dev --once --configure=new
npx convex deploy
```

The production deployment used by this project is:

```text
NEXT_PUBLIC_CONVEX_URL=https://bold-swan-844.convex.cloud
```

`npx convex deploy` validates and uploads `convex/schema.ts`, the indexes, and functions. It also regenerates `convex/_generated/`; commit generated bindings when they change.

After changing Convex functions:

```bash
npx convex deploy --typecheck enable --message "Describe the change"
```

## 2. Deploy the Workers AI service

```bash
cd cloudflare-asr
npm ci
npm run typecheck
npx wrangler deploy
cd ..
```

The Worker receives multipart audio and invokes `@cf/openai/whisper-large-v3-turbo` through its `AI` binding. Its public hostname exists for health checks, but the production application reaches it through a service binding.

## 3. Create the shared internal secret

The ASR Worker checks `ASR_API_KEY`. The web Worker sends the same value from its legacy `PARAKEET_API_KEY` secret.

Generate and install both values in one shell session so the secret is never committed:

```bash
ASR_KEY=$(openssl rand -hex 32)

printf '%s\n' "$ASR_KEY" | \
  (cd cloudflare-asr && npx wrangler secret put ASR_API_KEY)

printf '%s\n' "$ASR_KEY" | \
  npx wrangler secret put PARAKEET_API_KEY \
    --config wrangler.production.jsonc \
    --name voiceink-web

unset ASR_KEY
```

Wrangler expects the terminating newline. Omitting it can result in a secret value that does not authenticate correctly.

## 4. Build and deploy the web Worker

The public Convex and site URLs are embedded in the client build, so set them explicitly during a production build:

```bash
NEXT_PUBLIC_CONVEX_URL=https://bold-swan-844.convex.cloud \
NEXT_PUBLIC_SITE_URL=https://voiceink-web.paul-2eb.workers.dev \
npm run build

npx wrangler deploy \
  --config wrangler.production.jsonc \
  --keep-vars
```

`wrangler.production.jsonc` deploys:

- `dist/server/index.js` as the Worker
- `dist/client` as static assets
- the `ASR` binding to `voiceink-asr`
- public runtime configuration values

`--keep-vars` preserves dashboard-managed values and the existing secret during ordinary redeployments.

For a brand-new `voiceink-web` Worker, deploy it once before running `wrangler secret put`, then deploy again after the secret is installed.

## 5. Verify production

Check the site:

```bash
curl --fail --head https://voiceink-web.paul-2eb.workers.dev
```

Run a real transcription:

```bash
curl --fail \
  -F "audio=@sample.wav" \
  -F "model=whisper-large-v3-turbo" \
  https://voiceink-web.paul-2eb.workers.dev/api/transcribe
```

Expected response shape:

```json
{
  "text": "The completed transcript.",
  "model": "whisper-large-v3-turbo"
}
```

Then confirm a record appears in the `transcriptions` table in the Convex dashboard.

## Configuration reference

| Name | Location | Secret | Purpose |
| --- | --- | --- | --- |
| `NEXT_PUBLIC_CONVEX_URL` | Build and web Worker | No | Convex production client URL |
| `NEXT_PUBLIC_SITE_URL` | Build and web Worker | No | Canonical production URL |
| `PARAKEET_API_URL` | Web Worker | No | Legacy fallback URL for ASR |
| `PARAKEET_API_KEY` | Web Worker | Yes | Credential sent to ASR Worker |
| `ASR_API_KEY` | ASR Worker | Yes | Credential checked by ASR Worker |
| `AI` | ASR Worker binding | Binding | Workers AI access |
| `ASR` | Web Worker binding | Binding | Private Worker-to-Worker transport |

The `PARAKEET_*` names remain for compatibility with the prototype’s first inference adapter. Renaming them should be done as a dedicated migration so both Workers and deployment instructions change together.

## Logs and diagnostics

```bash
npx wrangler tail voiceink-web --format pretty
cd cloudflare-asr
npx wrangler tail voiceink-asr --format pretty
```

Common failures:

- `401` from ASR: the two Worker secrets do not match; rotate them together.
- `404` from an upstream Worker fetch: verify the `ASR` service binding is present and do not use the public hostname for Worker-to-Worker traffic.
- `502` from `/api/transcribe`: inspect `upstreamStatus` and tail both Workers.
- Demo transcript returned: `PARAKEET_API_URL` was unavailable in the web runtime.
- Transcript succeeds but is not saved: verify the production Convex URL and inspect Convex function logs.

## Rollback

List Cloudflare versions:

```bash
npx wrangler versions list --name voiceink-web
npx wrangler versions list --name voiceink-asr
```

Use the Cloudflare dashboard or Wrangler rollback command to restore a known-good Worker version. For Convex, check out the known-good source revision and run `npx convex deploy`; schema changes should be reviewed for backward compatibility before rollback.

Always repeat the production transcription smoke test after a rollback.
