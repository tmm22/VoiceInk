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

`@cf/openai/whisper-large-v3-turbo` costs approximately:

```text
$0.00051 per audio minute
```

Source: [Cloudflare Workers AI pricing](https://developers.cloudflare.com/workers-ai/platform/pricing/)

Examples:

| Audio transcribed per month | Workers AI estimate |
| ---: | ---: |
| 100 minutes | $0.05 |
| 1,000 minutes | $0.50 |
| 10,000 minutes | $5.00 |
| 100,000 minutes | $50.00 |
| 1,000,000 minutes | $500.00 |

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
monthly cost ≈ $5 + (audio minutes × $0.00051) + Llama token usage + Convex overages + Worker overages
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

1. Cloudflare applies fail-closed, route-specific limits: transcription 4/minute, summary 6/minute, enhancement 6/minute, import 10/minute, and history 30/minute per edge key.
2. All Convex history access is brokered through the protected web Worker.
3. Convex independently enforces per-minute, daily, record-count, and stored-character account quotas.
4. Anonymous history is limited to 30 active records and expires after one hour.
5. Request, upload, transcript, summary, and imported-content sizes are bounded.
6. The private ASR Worker requires its shared secret and rejects non-audio uploads.
7. Retention updates are versioned and cleanup drains expired backlogs through continuations.

Cloudflare rate-limit bindings are local, permissive pressure controls, not durable spend accounting. Configure billing and Workers AI usage alerts, a tested operator kill switch, WAF rules, and server-validated Turnstile for sustained anonymous abuse. Do not enable response caching for audio, transcripts, summaries, or enhancement output.
