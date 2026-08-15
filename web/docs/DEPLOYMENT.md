# Deployment guide

This guide describes the live production architecture as of August 15, 2026.

## Deployed services

| Component | Cloud service | Deployment |
| --- | --- | --- |
| Web UI and API | Cloudflare Workers | `voiceink-web` |
| Speech recognition, summaries, and text enhancement | Cloudflare Workers + Workers AI | `voiceink-asr` |
| Transcript database | Convex Cloud | Supplied at deployment time |
| Authentication | Clerk production | User accounts and cross-device ownership |
| ASR model | Cloudflare Workers AI | `@cf/openai/whisper-large-v3-turbo` |
| Summary and enhancement model | Cloudflare Workers AI | `@cf/meta/llama-3.2-3b-instruct` |

The public entry point is the URL returned by the `voiceink-web` deployment. The ASR Worker is reached from the web Worker through the `ASR` service binding. Do not replace this with a fetch to its public `workers.dev` hostname: same-account Worker subrequests can fail at Cloudflare routing, and the service binding is private and does not add another request charge.

When a user stops recording, the browser automatically uploads the in-memory audio to `/api/transcribe`. A successful result is written to Convex and the dedicated History workspace is refreshed. Audio bytes are not stored by the application. Any subsequently generated AI summary is attached to the matching transcription record.

Text-to-speech runs through the browser's `speechSynthesis` API and requires no Cloudflare binding, provider secret, or deployment step. The controller is adapted from `tmm22/untitled-folder-2`; available voices differ by browser and operating system.

## Prerequisites

- Node.js 22 LTS
- npm
- A Cloudflare account with Workers AI enabled
- Wrangler authenticated with `npx wrangler login`
- A Convex account authenticated through the Convex CLI

Run all web commands from the `web/` directory unless another directory is shown.

When upgrading an existing deployment, complete the steps below back-to-back in the order shown. The Convex functions, ASR Worker, and web Worker share strict request contracts (required pagination and operation-ID arguments, raw streamed audio bodies), so a mixed old/new state breaks history or transcription until all three are on the same release. Browser tabs still running the previous bundle must be reloaded before they can save history again.

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

Retention changes are applied in paginated background mutations, so the policy covers the complete account history rather than only the first page of records.

After changing Convex functions:

```bash
npx convex deploy --typecheck enable --message "Describe the change"
```

## 2. Enable Clerk accounts

The live application uses Clerk's production environment on the `paul.im` primary domain. Its Frontend API is `clerk.paul.im`, the Account Portal is `accounts.paul.im`, and the Clerk Convex integration is enabled. Configure the Convex JWT issuer in both Convex development and production; do not paste credentials into tracked files:

```bash
npx convex env set CLERK_JWT_ISSUER_DOMAIN 'https://clerk.paul.im'
npx convex env set --prod CLERK_JWT_ISSUER_DOMAIN 'https://clerk.paul.im'
npx convex deploy --typecheck enable --message "Enable Clerk authentication"
```

Set `NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY` in the Cloudflare build environment, then include it when producing the deployed client bundle. The publishable key is intentionally not committed:

```bash
NEXT_PUBLIC_CONVEX_URL=https://<your-convex-deployment>.convex.cloud \
NEXT_PUBLIC_SITE_URL=https://v.paul.im \
NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY=pk_<your-publishable-key> \
npm run build
```

This client-only integration does not require `CLERK_SECRET_KEY`. Add a secret key only if future server-side Clerk APIs require it, and store it with Wrangler or the Cloudflare dashboard—not in source control. Account history is keyed exclusively from Convex's verified identity token, never from a browser-supplied user ID.

Google sign-in uses a dedicated public OAuth web client in the `VoiceInk Web` Google Cloud project. The only authorized production origin is `https://v.paul.im`, and Clerk's registered redirect URI is:

```text
https://clerk.paul.im/v1/oauth_callback
```

The Google Client ID and Client Secret are stored only in Clerk's production Google connection. Do not copy either credential into this repository, Cloudflare, Convex, or local environment files. The Google OAuth audience must remain External and published; Testing mode restricts sign-in to named test users. The Clerk provider forces both sign-in and sign-up callbacks back to `https://v.paul.im` so the root `paul.im` site never becomes an authentication landing page.

### Production abuse protection

The web Worker defines independent Cloudflare rate-limit bindings for transcription (4/minute), summarization (6/minute), enhancement (6/minute), webpage imports (10/minute), and history (30/minute). API routes also reject cross-origin browser requests and enforce both declared and actual byte limits before inference or persistence. Anonymous history writes pass through `/api/history` and require a shared `CONVEX_WEB_API_SECRET` configured in both the web Worker and the production Convex deployment. Never expose or commit this value.

The ASR Worker requires `ASR_API_KEY` for every inference request and fails closed if the secret is missing. It has no public `workers.dev` or preview URL; health metadata is reachable only through a service binding.

Generate the anonymous-history broker secret once and install the identical value in Convex production and the web Worker without committing or printing it:

```bash
HISTORY_KEY=$(openssl rand -hex 32)
npx convex env set --prod CONVEX_WEB_API_SECRET "$HISTORY_KEY"
printf '%s\n' "$HISTORY_KEY" | npx wrangler secret put CONVEX_WEB_API_SECRET \
  --config wrangler.production.jsonc --name voiceink-web
unset HISTORY_KEY
```

Rotate by repeating those commands, redeploying the web Worker, and running the non-mutating production smoke. Verify only that the variable names exist; never print their values.

Production responses include CSP, HSTS, clickjacking protection, MIME-sniffing protection, a restrictive permissions policy, and a strict referrer policy.

The canonical and only production site runs at `v.paul.im`. Clerk uses its production publishable key compiled into the client bundle. The `workers.dev` route is disabled so authentication is not exposed through a second, non-canonical origin.

## 3. Deploy the Workers AI service

```bash
cd cloudflare-asr
npm ci
npm run typecheck
npx wrangler deploy
cd ..
```

The web Worker streams a validated raw audio body to the private Worker, which verifies its bounded length, media type, and container signature before invoking `@cf/openai/whisper-large-v3-turbo` through its `AI` binding. It is private-only and the production application reaches it through the `ASR` service binding.

The same private Worker handles `/v1/summaries` and `/v1/enhancements` with Llama 3.2 3B. The public web Worker exposes `/api/summarize` and `/api/enhance`, then forwards text through the private service binding. After a successful summary response, the browser stores the summary on the matching transcription through an ownership-checked Convex mutation, so both share the same retention window. Enhancement results remain browser-local unless the user explicitly replaces the transcript.

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
NEXT_PUBLIC_SITE_URL=https://v.paul.im \
NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY=pk_<your-publishable-key> \
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

Before every deployment, run:

```bash
npm run check
```

After deployment, run `npm run test:production -- --base-url https://v.paul.im`. This smoke suite checks production health and security contracts without invoking paid transcription, summarization, or enhancement. The repository's `web-regression.yml` workflow repeats local checks on every relevant push/PR and runs production smoke checks daily and on manual dispatch.

Run a real transcription:

```bash
curl --fail \
  -H "content-type: audio/wav" \
  --data-binary @sample.wav \
  "https://v.paul.im/api/transcribe"
```

The route accepts raw audio bodies only; multipart uploads are rejected. Expected response shape (`durationSeconds` and `segments` are included when the provider returns timing data):

```json
{
  "text": "The completed transcript.",
  "model": "whisper-large-v3-turbo",
  "durationSeconds": 4.2,
  "segments": [{ "start": 0, "end": 4.2, "text": "The completed transcript." }]
}
```

Then confirm a record appears in the `transcriptions` table in the Convex dashboard.

Run a summary smoke test:

```bash
curl --fail \
  -H 'content-type: application/json' \
  --data '{"text":"A transcript containing decisions and action items."}' \
  "https://v.paul.im/api/summarize"
```

Run a minimal text-enhancement smoke test after changing the inference path:

```bash
curl --fail \
  -H 'content-type: application/json' \
  --data '{"text":"this is a short test transcript","mode":"clean"}' \
  "https://v.paul.im/api/enhance"
```

Expected fields are `enhanced`, `mode`, and `model`. Do not print real transcripts in deployment logs.

The same endpoint accepts audio selected through the browser's **Upload audio file** control. Uploads share the ASR Worker's 24 MB maximum. Verify TXT, SRT, and VTT downloads from the transcript toolbar and confirm that history deletion removes only records owned by the current account or anonymous browser identity.

Verify article importing:

```bash
curl --fail \
  -H 'content-type: application/json' \
  --data '{"url":"https://example.com/"}' \
  "https://v.paul.im/api/import"
```

## Configuration reference

| Name | Location | Secret | Purpose |
| --- | --- | --- | --- |
| `NEXT_PUBLIC_CONVEX_URL` | Build and web Worker | No | Convex production client URL |
| `NEXT_PUBLIC_SITE_URL` | Build and web Worker | No | Canonical production URL |
| `CONVEX_WEB_API_SECRET` | Web Worker and Convex | Yes | Authorizes brokered anonymous history creation |
| `NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY` | Build and web Worker | No | Enables Clerk sign-in in the browser |
| `CLERK_JWT_ISSUER_DOMAIN` | Convex environment | No | Validates Clerk-issued Convex JWTs |
| `PARAKEET_API_KEY` | Web Worker | Yes | Credential sent to ASR Worker |
| `ASR_API_KEY` | ASR Worker | Yes | Credential checked by ASR Worker |
| `AI` | ASR Worker binding | Binding | Workers AI access |
| `ASR` | Web Worker binding | Binding | Private Worker-to-Worker transport |

The `PARAKEET_API_KEY` name remains for compatibility with the prototype’s first inference adapter. There is no external URL fallback: production fails closed unless the private `ASR` binding and matching secret are both present.

## Logs and diagnostics

```bash
npx wrangler tail voiceink-web --format pretty
cd cloudflare-asr
npx wrangler tail voiceink-asr --format pretty
```

Common failures:

- `401` from ASR: the two Worker secrets do not match; rotate them together.
- `404` from an upstream Worker fetch: verify the `ASR` service binding is present and do not use the public hostname for Worker-to-Worker traffic.
- `502` from `/api/transcribe`: tail both Workers using the response request ID where present; provider bodies are intentionally not exposed.
- `503` from `/api/summarize` or `/api/enhance`: verify the `ASR` binding and shared secret are present on the web Worker.
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
