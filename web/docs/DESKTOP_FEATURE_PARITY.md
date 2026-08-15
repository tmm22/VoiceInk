# Desktop-to-web feature feasibility

This review maps VoiceInk desktop capabilities to the web product without weakening the community fork's privacy-first, local-first philosophy. Browser features should remain opt-in, disclose when text leaves the device, and avoid pretending that browser security boundaries are equivalent to native macOS integration.

## Available now

| Capability | Web status | Notes |
| --- | --- | --- |
| Record and upload transcription | Available | Cloudflare Workers AI; audio is forwarded in memory and not stored by the application. |
| Transcript history and retention | Available | Convex-backed, with short anonymous retention and account-controlled retention. |
| TXT, SRT, and WebVTT export | Available | Runs in the browser. |
| AI summaries | Available | Explicit cloud request through the private Worker binding. |
| AI text enhancement | Available in 2.11 | Clean-up, concise, professional, and structured-note presets; original text is preserved until explicit replacement. |
| Text-to-speech | Available | Uses device and browser voices, so narration text is not sent to a cloud TTS provider. |
| Public article import | Available | Protected by redirect, timeout, size, and private-address safeguards. |

## Feasible next steps

| Priority | Feature | Recommended web approach |
| ---: | --- | --- |
| 1 | Custom enhancement instructions | Add an optional, clearly scoped instruction field with strict size limits and the same explicit cloud disclosure. Keep presets as safe defaults. |
| 2 | Translation | Add explicit target-language selection and return a separate result before replacement. Treat it as cloud AI processing and preserve the source transcript. |
| 3 | Personal dictionary and replacements | Apply browser-local replacement rules first; add encrypted or account-synced storage only after a clear retention and deletion design. |
| 4 | Better transcript structure | Offer timestamp cleanup, paragraphing, and speaker-label assistance when the underlying transcription response contains enough evidence. Never invent speakers. |
| 5 | Reusable web workflows | Let users save enhancement presets or export templates, with local storage as the privacy-preserving default and optional account sync. |

## Possible, but requires a separate product decision

- Streaming partial transcription would materially change inference, buffering, failure recovery, rate limits, and cost controls. It should not be layered onto the current bounded batch path without dedicated architecture work.
- Cloud TTS would provide consistent voices but adds provider credentials, content transfer, usage cost, and audio lifecycle questions. Device voices remain the safer default.
- User-supplied provider keys should not be stored in browser local storage. Supporting them safely would require a server-side encrypted credential design, explicit provider disclosures, rotation, and deletion controls.
- Persisting enhancement revisions would require a history schema that distinguishes original transcripts from derived text and makes retention and deletion behavior obvious.

## Keep desktop-only

- Active-window, browser-URL, selected-text, clipboard, and screen-capture context collection
- Global shortcuts, accessibility-driven paste, auto-send, and menu-bar recording behavior
- Local Whisper, Parakeet, Core ML, Ollama, and native audio-device management
- macOS permissions, App Intents, system audio capture, and application-aware Power Mode automation

These features depend on native operating-system access or local model runtimes. A browser approximation would be less capable and could create misleading privacy expectations. The web app should instead focus on explicit user-provided text, bounded cloud processing, portable history, export, and device-native browser APIs.
