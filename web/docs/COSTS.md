# Operating costs

Prices below are estimates in USD using published rates checked on July 12, 2026. Cloud pricing changes over time, so verify the linked pricing pages before making budget commitments.

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
$0.0005 per audio minute
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

### Convex

The Free/Starter allowance currently includes approximately:

- 1 million function calls
- 0.5 GB database storage
- 1 GB database I/O
- 1 GB network egress

Starter overage rates shown by Convex include $2.20 per additional million function calls, $0.22 per additional GB of database storage, $0.22 per additional GB of database I/O, and $0.132 per additional GB of egress. The Professional plan starts at $25 per developer per month and carries larger included allowances.

Source: [Convex pricing](https://www.convex.dev/pricing)

This prototype stores transcript text and metadata only. It does not store audio, so database and egress consumption should remain modest at early usage levels. Anonymous transcript rows are automatically deleted after one hour; signed-in history is retained for the account.

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
monthly cost ≈ $5 + (audio minutes × $0.0005) + Convex overages + Worker overages
```

## Costs not currently incurred

- No GPU server or Cloudflare Container
- No R2 audio storage
- No D1 database
- No external ASR provider
- No cloud TTS charges; current text-to-speech uses device/browser voices
- No AI enhancement model
- No authentication-provider charge while Clerk remains unconfigured; review Clerk's current plan limits before enabling accounts publicly
- No custom domain requirement

The unused `parakeet-service/` reference would create a materially different cost profile if deployed. Production currently uses managed Workers AI instead.

## Cost and abuse controls recommended before launch

The public transcription endpoint can currently be invoked without a user account. Before broader distribution, add:

1. Enable the implemented Clerk integration before broader account-based distribution.
2. Add per-user daily audio-minute quotas.
3. Add Cloudflare rate limiting on `/api/transcribe`.
4. Add a maximum recording duration in the browser in addition to the 24 MB server limit.
5. Configure Cloudflare billing alerts and Workers AI usage alerts.
6. Add a hard failure when the configured monthly quota is reached.

Without these controls, a third party could consume Workers AI credits through the public endpoint.
