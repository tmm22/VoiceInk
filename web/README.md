# VoiceInk Web

VoiceInk Web is a browser-based transcription prototype deployed entirely through Cloudflare, with transcript persistence in Convex.

It also includes a separate device-local text-to-speech workspace adapted from the proven browser speech controller in [`tmm22/untitled-folder-2`](https://github.com/tmm22/untitled-folder-2). Users can paste or type independent narration text, or explicitly copy in a completed transcript, then read it aloud with voices installed in the current browser or operating system.

Users can switch between the original editorial theme and a native macOS-inspired appearance from the header. The original design remains the default, and the preference is stored only in the current browser.

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

Audio is forwarded in memory and is not stored by this application. The returned transcript is saved to Convex after a successful transcription. Anonymous history expires after one hour and a scheduled Convex cleanup removes it. When Clerk is configured, signed-in history is owned by the authenticated Clerk identity and persists across browsers and devices.

Recording is intentionally one-step: pressing Stop immediately uploads the captured audio, runs transcription, stores the completed transcript in Convex, and refreshes the on-page history. If transcription fails, the in-memory recording remains available for retry.

## Repository layout

- `app/` — browser recorder, automatic transcription workflow, history interface, and transcription proxy
- `lib/browserSpeech.ts` — reused system-voice discovery and playback controller
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

Clerk is optional during development. Without `NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY`, the app runs anonymously and applies the one-hour retention policy. See the deployment guide before enabling accounts.

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

- Clerk account support requires a Clerk application and production environment configuration before it becomes visible
- No per-user quotas or public-endpoint rate limiting
- Anonymous history is associated with a browser-generated client ID and retained for no more than one hour
- Account history persists until an account-data deletion flow or retention policy is added
- Batch transcription only; no live partial transcript stream
- System/device voices only for the initial TTS integration; cloud TTS adapters are not yet connected
- Audio uploads are limited to 24 MB by the ASR Worker
- `PARAKEET_API_URL` and `PARAKEET_API_KEY` are legacy configuration names; production inference uses Whisper Large V3 Turbo

These limitations should be addressed before opening the application to untrusted public traffic.
