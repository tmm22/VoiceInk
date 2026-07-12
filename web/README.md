# VoiceInk Web

VoiceInk Web is a browser-based transcription prototype deployed entirely through Cloudflare, with transcript persistence in Convex.

It also includes a separate device-local text-to-speech workspace adapted from the proven browser speech controller in [`tmm22/untitled-folder-2`](https://github.com/tmm22/untitled-folder-2). Users can paste or type independent narration text, or explicitly copy in a completed transcript, then read it aloud with voices installed in the current browser or operating system.

The text-to-speech workspace can also import a public article URL. The Cloudflare Worker fetches the page with redirect, size, timeout, and private-address safeguards, extracts readable article text, and loads it directly into the narration editor.

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

Audio is forwarded in memory and is not stored by this application. The returned transcript is saved to Convex after a successful transcription. Anonymous history expires after one hour and a scheduled Convex cleanup removes it. Signed-in history is owned by the authenticated Clerk identity and persists across browsers and devices. Account holders can choose automatic deletion after 7, 30, 90, or 365 days, or keep history until they delete it; the default is 90 days.

Recording is intentionally one-step: pressing Stop immediately uploads the captured audio, runs transcription, stores the completed transcript in Convex, and refreshes the on-page history. If transcription fails, the in-memory recording remains available for retry.

Existing audio can also be uploaded into the same transcription pipeline. Completed transcripts can be downloaded as plain text, SRT, or WebVTT. History supports search, loading a transcript back into the editor, sending it to narration, and ownership-checked deletion.

Completed transcripts can be summarized on demand with Cloudflare Workers AI using `@cf/meta/llama-3.2-3b-instruct`. Summaries are editable, copyable, and can be sent to the narration workspace. They are generated only when requested and are not persisted in Convex.

## Repository layout

- `app/` — browser recorder, audio upload, automatic transcription workflow, history interface, and transcription proxy
- `lib/transcriptExport.ts` — TXT, SRT, and WebVTT transcript downloads adapted from the source project
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

Clerk is optional during development. Without `NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY`, the app runs anonymously and applies the one-hour retention policy. The live prototype currently uses a Clerk development instance; move to production keys after attaching a custom domain and completing Clerk's DNS setup.

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

- The live prototype uses Clerk development mode and its associated usage limits until a custom domain is available for Clerk production DNS
- No per-user quotas or public-endpoint rate limiting
- Anonymous history is associated with a browser-generated client ID and retained for no more than one hour
- Account history uses the signed-in user's configurable Convex retention policy, defaulting to 90 days
- Batch transcription only; no live partial transcript stream
- System/device voices only for the initial TTS integration; cloud TTS adapters are not yet connected
- Audio uploads are limited to 24 MB by the ASR Worker
- `PARAKEET_API_URL` and `PARAKEET_API_KEY` are legacy configuration names; production inference uses Whisper Large V3 Turbo

These limitations should be addressed before opening the application to untrusted public traffic.
