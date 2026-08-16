# Operating costs

Prices below are estimates in USD using published rates checked on August 15, 2026. Cloud pricing changes over time, so verify the linked pricing pages before making budget commitments.

## Current cost drivers

### Cloudflare Workers

The Workers Paid plan has a $5 monthly minimum and includes:

- 10 million dynamic Worker requests per month
- 30 million CPU milliseconds per month
- unlimited free static-asset requests

Additional dynamic requests are $0.30 per million and additional CPU is $0.02 per million CPU milliseconds. The private `voiceink-web` → `voiceink-asr` service-binding call does not add another request charge; CPU across both Workers is aggregated.

Source: [Cloudflare Workers pricing](https://developers.cloudflare.com/workers/platform/pricing/)

### Workers AI transcription

Transcription routes between two models. English audio (the common case) uses `@cf/deepgram/nova-3`, which costs approximately:

```text
$0.0052 per audio minute
```

Non-English audio is detected by nova-3 and re-transcribed by `@cf/openai/whisper-large-v3-turbo`, which costs approximately:

```text
$0.00051 per audio minute
```

A non-English request therefore pays for both models (≈ $0.00571 per audio minute). Source: [Cloudflare Workers AI pricing](https://developers.cloudflare.com/workers-ai/platform/pricing/)

Examples (English audio on nova-3):

| Audio transcribed per month | Workers AI estimate |
| ---: | ---: |
| 100 minutes | $0.52 |
| 1,000 minutes | $5.20 |
| 10,000 minutes | $52.00 |
| 100,000 minutes | $520.00 |

### Workers AI summaries and text enhancement

The summary and text-enhancement features use `@cf/meta/llama-3.2-3b-instruct`, currently priced at approximately $0.051 per million input tokens and $0.335 per million output tokens.

Source: [Cloudflare Workers AI pricing](https://developers.cloudflare.com/workers-ai/platform/pricing/)

For example, 10,000 summaries averaging 1,000 input tokens and 200 output tokens would cost approximately $1.18 in model usage. Enhancement uses the same token pricing; actual cost depends on source and response length.

### Convex

The Free/Starter allowance currently includes approximately:

- 1 million function calls
- 0.5 GB database storage
- 1 GB database I/O
- 1 GB network egress

Starter overage rates shown by Convex include $2.20 per additional million function calls, $0.22 per additional GB of database storage, $0.22 per additional GB of database I/O, and $0.132 per additional GB of egress. The Professional plan starts at $25 per developer per month and carries larger included allowances.

Source: [Convex pricing](https://www.convex.dev/pricing)

This prototype stores transcript text and metadata only. It does not store audio, so database and egress consumption should remain modest at early usage levels. Anonymous transcript rows are automatically deleted after one hour. Signed-in history defaults to 90 days, with user-selectable 7-day, 30-day, 90-day, one-year, or indefinite retention.

## Estimated combined monthly cost

These scenarios assume:

- the $5 Cloudflare Workers Paid minimum
- Worker requests and CPU remain inside the included allowance
- Convex remains inside its free allowances
- no custom domain registration, observability vendor, authentication vendor, or audio storage

| Usage scenario | Audio minutes | Approximate total |
| --- | ---: | ---: |
| Personal testing | 100 | $5.05/month |
| Small prototype | 1,000 | $5.50/month |
| Early beta | 10,000 | $10.00/month |
| Growing product | 100,000 | $55.00/month |

The simple planning formula is:

```text
monthly cost ≈ $5 + (English audio minutes × $0.0052) + (non-English audio minutes × $0.00571) + Llama token usage + Convex overages + Worker overages
```

## Costs not currently incurred

- No GPU server or Cloudflare Container
- No R2 audio storage
- No D1 database
- No external ASR provider
- No cloud TTS charges; current text-to-speech uses device/browser voices
- No separate AI enhancement provider; enhancement shares the existing Workers AI model and controls
- Authentication cost depends on the active Clerk production plan and monthly active users
- The canonical custom domain is `v.paul.im`

The unused `parakeet-service/` reference would create a materially different cost profile if deployed. Production currently uses managed Workers AI instead.

## Active cost and abuse controls

Anonymous transcription remains available, but the following controls limit cost and storage abuse:

1. A SQLite durable object in the ASR Worker enforces a hard global spend ceiling: every inference call must reserve budget before it runs, priced at the worst-case low bitrate for the declared bytes across both transcription models and settled to the provider-reported duration and the models that actually ran. The default ceiling is $10.00 per UTC day (`DAILY_SPEND_LIMIT_MICROS = 10000000`), which bounds the worst-case Workers AI bill at roughly $310 per month even under sustained attack. The ceiling must stay above the worst-case reservation for one full 24 MB upload (≈ $4.79), or maximum-size uploads would always be denied. If the ledger is unreachable, inference is denied.
2. The same ledger caps each client IP at 2 hours of transcribed audio per UTC day (`DAILY_CLIENT_AUDIO_SECONDS = 7200`, about $0.62 of English transcription). A single request's seconds estimate is clamped to that daily quota at admission — worst-case byte pricing wildly overestimates real recordings, and without the clamp any upload over ~3.4 MB would be denied outright — then settles to the provider-reported duration.
3. `/api/transcribe` requires a server-verified, single-use Cloudflare Turnstile token whenever `TURNSTILE_SECRET_KEY` is configured, stopping headless-bot volume before any inference spend.
4. Anonymous visitors are limited to 10 minutes of audio per recording or upload; signed-in users keep 30-minute recordings and 2-hour uploads.
5. Cloudflare applies fail-closed, route-specific limits: transcription 4/minute, summary 6/minute, enhancement 6/minute, import 10/minute, and history 30/minute per edge key.
6. All Convex history access is brokered through the protected web Worker.
7. Convex independently enforces per-minute, daily, record-count, and stored-character account quotas.
8. Anonymous history is limited to 30 active records and expires after one hour.
9. Request, upload, transcript, summary, and imported-content sizes are bounded.
10. The private ASR Worker requires its shared secret and rejects non-audio uploads.
11. Retention updates are versioned and cleanup drains expired backlogs through continuations.

Cloudflare rate-limit bindings are local, permissive pressure controls; the durable-object ledger is the durable spend accounting behind them. Additionally configure a billing budget alert (informational only), keep the zone-level WAF checklist in `docs/HARDENING.md` applied, and do not enable response caching for audio, transcripts, summaries, or enhancement output.
