# Deployment guide

This guide describes the live production architecture as of July 12, 2026.

## Deployed services

| Component | Cloud service | Deployment |
| --- | --- | --- |
| Web UI and API | Cloudflare Workers | `voiceink-web` |
| Speech recognition and summaries | Cloudflare Workers + Workers AI | `voiceink-asr` |
| Transcript database | Convex Cloud | Supplied at deployment time |
| Optional authentication | Clerk | User accounts and cross-device ownership |
| ASR model | Cloudflare Workers AI | `@cf/openai/whisper-large-v3-turbo` |
| Summary model | Cloudflare Workers AI | `@cf/meta/llama-3.2-3b-instruct` |

The public entry point is the URL returned by the `voiceink-web` deployment. The ASR Worker is reached from the web Worker through the `ASR` service binding. Do not replace this with a fetch to its public `workers.dev` hostname: same-account Worker subrequests can fail at Cloudflare routing, and the service binding is private and does not add another request charge.

When a user stops recording, the browser automatically uploads the in-memory audio to `/api/transcribe`. A successful result is written to Convex and the history list is refreshed. Audio bytes are not stored by the application.

Text-to-speech runs through the browser's `speechSynthesis` API and requires no Cloudflare binding, provider secret, or deployment step. The controller is adapted from `tmm22/untitled-folder-2`; available voices differ by browser and operating system.

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
NEXT_PUBLIC_CONVEX_URL=https://<your-convex-deployment>.convex.cloud
```

`npx convex deploy` validates and uploads `convex/schema.ts`, the indexes, and functions. It also regenerates `convex/_generated/`; commit generated bindings when they change.

The deployed Convex cron runs every five minutes. It deletes anonymous transcripts after one hour and account transcripts after the user's selected retention period. Account retention defaults to 90 days and can be changed to 7, 30, 90, or 365 days, or disabled. Changing the selection reapplies the policy to the user's existing history.

After changing Convex functions:

```bash
npx convex deploy --typecheck enable --message "Describe the change"
```

## 2. Enable Clerk accounts

Create a Clerk application and activate its Convex integration. Configure the Convex JWT issuer in both Convex development and production; do not paste credentials into tracked files:

```bash
npx convex env set CLERK_JWT_ISSUER_DOMAIN 'https://<your-clerk-issuer>'
npx convex env set --prod CLERK_JWT_ISSUER_DOMAIN 'https://<your-clerk-issuer>'
npx convex deploy --typecheck enable --message "Enable Clerk authentication"
```

Set `NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY` in the Cloudflare build environment, then include it when producing the deployed client bundle. The publishable key is intentionally not committed:

```bash
NEXT_PUBLIC_CONVEX_URL=https://<your-convex-deployment>.convex.cloud \
NEXT_PUBLIC_SITE_URL=https://<your-web-worker>.<your-subdomain>.workers.dev \
NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY=pk_<your-publishable-key> \
npm run build
```

This client-only integration does not require `CLERK_SECRET_KEY`. Add a secret key only if future server-side Clerk APIs require it, and store it with Wrangler or the Cloudflare dashboard—not in source control. Account history is keyed exclusively from Convex's verified identity token, never from a browser-supplied user ID.

The current `workers.dev` prototype is built with a Clerk development publishable key. Clerk production instances require DNS records for their frontend API domain; because the assigned `workers.dev` zone is not controlled by this project, production Clerk keys should be activated only after attaching a custom domain whose DNS records you can edit. Until then, the account flow works in Clerk development mode and is subject to Clerk's development limits.

## 3. Deploy the Workers AI service

```bash
cd cloudflare-asr
npm ci
npm run typecheck
npx wrangler deploy
cd ..
```

The Worker receives multipart audio and invokes `@cf/openai/whisper-large-v3-turbo` through its `AI` binding. Its public hostname exists for health checks, but the production application reaches it through a service binding.

The same private Worker handles `/v1/summaries` with Llama 3.2 3B. The public web Worker exposes `/api/summarize`, forwards transcript text through the private service binding, and returns the generated summary without storing it.

## 4. Create the shared internal secret

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

## 5. Build and deploy the web Worker

The public Convex and site URLs are embedded in the client build, so set them explicitly during a production build:

```bash
NEXT_PUBLIC_CONVEX_URL=https://<your-convex-deployment>.convex.cloud \
NEXT_PUBLIC_SITE_URL=https://<your-web-worker>.<your-subdomain>.workers.dev \
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

## 6. Verify production

Check the site:

```bash
curl --fail --head "https://<your-web-worker>.<your-subdomain>.workers.dev"
```

Run a real transcription:

```bash
curl --fail \
  -F "audio=@sample.wav" \
  -F "model=whisper-large-v3-turbo" \
  "https://<your-web-worker>.<your-subdomain>.workers.dev/api/transcribe"
```

Expected response shape:

```json
{
  "text": "The completed transcript.",
  "model": "whisper-large-v3-turbo"
}
```

Then confirm a record appears in the `transcriptions` table in the Convex dashboard.

Run a summary smoke test:

```bash
curl --fail \
  -H 'content-type: application/json' \
  --data '{"text":"A transcript containing decisions and action items."}' \
  "https://<your-web-worker>.<your-subdomain>.workers.dev/api/summarize"
```

The same endpoint accepts audio selected through the browser's **Upload audio file** control. Uploads share the ASR Worker's 24 MB maximum. Verify TXT, SRT, and VTT downloads from the transcript toolbar and confirm that history deletion removes only records owned by the current account or anonymous browser identity.

Verify article importing:

```bash
curl --fail \
  -H 'content-type: application/json' \
  --data '{"url":"https://example.com/"}' \
  "https://<your-web-worker>.<your-subdomain>.workers.dev/api/import"
```

## Configuration reference

| Name | Location | Secret | Purpose |
| --- | --- | --- | --- |
| `NEXT_PUBLIC_CONVEX_URL` | Build and web Worker | No | Convex production client URL |
| `NEXT_PUBLIC_SITE_URL` | Build and web Worker | No | Canonical production URL |
| `NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY` | Build and web Worker | No | Enables Clerk sign-in in the browser |
| `CLERK_JWT_ISSUER_DOMAIN` | Convex environment | No | Validates Clerk-issued Convex JWTs |
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
- Sign-in is not visible: the client bundle was built without `NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY`.
- Clerk signs in but history fails: verify the Clerk Convex integration and `CLERK_JWT_ISSUER_DOMAIN`, then redeploy Convex with `auth.config.ts` enabled.

## Rollback

List Cloudflare versions:

```bash
npx wrangler versions list --name voiceink-web
npx wrangler versions list --name voiceink-asr
```

Use the Cloudflare dashboard or Wrangler rollback command to restore a known-good Worker version. For Convex, check out the known-good source revision and run `npx convex deploy`; schema changes should be reviewed for backward compatibility before rollback.

Always repeat the production transcription smoke test after a rollback.
