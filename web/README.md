# VoiceInk Web

VoiceInk Web is a browser-based transcription prototype deployed entirely through Cloudflare, with transcript persistence in Convex.

## Production

- Web app: the `voiceink-web` Worker in the target Cloudflare account
- Transcription: Cloudflare Workers AI using `@cf/openai/whisper-large-v3-turbo`
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
  └─ Convex transcript mutation
       │ private Cloudflare service binding
       ▼
voiceink-asr Cloudflare Worker
       │ Workers AI binding
       ▼
Whisper Large V3 Turbo
```

Audio is forwarded in memory and is not stored by this application. The returned transcript is saved to Convex after a successful transcription.

Recording is intentionally one-step: pressing Stop immediately uploads the captured audio, runs transcription, stores the completed transcript in Convex, and refreshes the on-page history. If transcription fails, the in-memory recording remains available for retry.

## Repository layout

- `app/` — browser recorder, automatic transcription workflow, history interface, and transcription proxy
- `cloudflare-asr/` — secured Workers AI transcription Worker
- `convex/` — schema, queries, mutations, and generated bindings
- `wrangler.production.jsonc` — production web Worker and service binding
- `parakeet-service/` — experimental self-hosted Parakeet reference; not used in production

## Local development

Use Node.js 22 LTS or another version satisfying `package.json`.

```bash
npm install
npx convex dev
npm run dev
```

The web interface returns a clearly marked demo transcript when no inference endpoint is configured. To use the deployed ASR Worker locally, provide its URL and the matching Worker secret in `.env.local`.

## Validation

```bash
npx tsc --noEmit
npm run build
```

For a production smoke test with a local audio file:

```bash
curl --fail \
  -F "audio=@sample.wav" \
  -F "model=whisper-large-v3-turbo" \
  "https://<your-web-worker>.<your-subdomain>.workers.dev/api/transcribe"
```

## Deployment and costs

- [Deployment guide](docs/DEPLOYMENT.md)
- [Operating costs](docs/COSTS.md)

## Current prototype limitations

- No user authentication or account ownership checks
- No per-user quotas or public-endpoint rate limiting
- History is stored against a browser-generated client ID
- Batch transcription only; no live partial transcript stream
- Audio uploads are limited to 24 MB by the ASR Worker
- `PARAKEET_API_URL` and `PARAKEET_API_KEY` are legacy configuration names; production inference uses Whisper Large V3 Turbo

These limitations should be addressed before opening the application to untrusted public traffic.
