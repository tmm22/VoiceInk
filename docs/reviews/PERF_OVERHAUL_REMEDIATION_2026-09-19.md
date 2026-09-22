# Performance overhaul remediation — 2026-09-19

Implemented in the working tree of `perf/mac-architecture-overhaul` at `5d03c7e3`, in `~/Developer/voiceink-sync`. This records the response to [the independent review](PERF_OVERHAUL_REVIEW_2026-09-16.md). Changes are not committed or published.

Follow-up: [2026-09-19 independent review of this remediation](PERF_OVERHAUL_REMEDIATION_REVIEW_2026-09-19.md), which also records the small adjustments made after that review.

Current verification and remaining qualifications: [follow-up fixes](PERF_OVERHAUL_FOLLOWUP_2026-09-19.md).
The 17-12-10 and 17-45-03 result bundles cited below have also since been pruned by Xcode;
the follow-up report identifies the full run of the current tree.

## Correctness fixes

- **Audio callback lifetime:** `AudioCallbackGate` atomically couples admission and active-callback count. Stop, switch and teardown close admission and wait for admitted callbacks before resetting/reusing/freeing resources. The 200 ms threshold now logs a diagnostic rather than allowing unsafe progress. Teardown from Recorder destruction or missing-device preparation runs on the serial hardware queue, retaining the core until disposal completes. Successful stop returns only after final PCM is drained, converter tail flushed and WAV closed. Converter setup failure now throws instead of silently producing an empty recording.
- **Whisper shared model ownership:** model loading, publication, invalidation and active inference are tracked by generation identity. Every successful waiter receives the same live generation. Old completions cannot delete replacements; invalidated results are released once, only after that generation's last inference. Cancelling a waiter does not cancel other waiters. Language/prompt/inference/result extraction are performed within one synchronous context-actor operation to prevent cross-request state changes.
- **Streaming lifetime:** the forwarding task does not retain the provider across indefinite stream waits. Deallocation cancels forwarding and disconnects the client. Cancellation no longer synthesizes Cartesia's successful finalization event. Vendor model/language mappings remain unchanged.
- **Paste and auto-send:** modifier state is rechecked after clipboard settling; cancelled policy waits stop rather than spinning. Paste is not posted if the clipboard changed while waiting. Owned clipboard restoration is still scheduled when cancelled. A failed or cancelled paste cannot trigger an automatic Enter/Command-Enter. Key-up remains paired with an already-posted key-down.

## Additional production cleanup

- Native Whisper realtime/timestamp console output is disabled to avoid exposing dictated text; removed an adjacent prompt force unwrap.
- Prewarm tasks are retained and cancelled on sleep/destruction, repeated wake events are coalesced, overlapping preparation is avoided, and test bootstrap does not schedule prewarming.
- Recorder waveform animation pauses in silence and respects Reduce Motion. Processing animations respect Reduce Motion, decorative indicators are hidden from accessibility navigation, and close/mode/recording elements have accessible labels.
- Split the oversized recorder and recorder-components files into focused files, each below 500 lines.

## Verification

The prescribed Debug arm64 `xcodebuild test` command passed against the combined production changes:

- **239 passed, 2 skipped, 0 failures**, 241 total including Swift Testing's example.
- **33 additional tests** compared with the reviewed head: 4 callback/file-lifecycle, 3 audio-continuity, 3 modifier-wait/cancellation, 6 auto-send, 9 streaming-lifecycle, 8 Whisper-lifetime tests.
- Result: the original `Test-VoiceInk-2026.09.19_11-22-19-+1000.xcresult` bundle has since been pruned from `.local-build/Logs/Test/`. The independent re-run `Test-VoiceInk-2026.09.19_17-12-10-+1000.xcresult` reproduced the same counts (241 cases including Swift Testing's example: 239 passed, 2 skipped, 0 failures). The run covering the follow-up adjustments is `Test-VoiceInk-2026.09.19_17-45-03-+1000.xcresult` (242 cases: 240 passed, 2 skipped, 0 failures).
- Audio coverage includes a held callback past the former timeout, final PCM preserved in a readable WAV, converter setup failure, six sample rates/four chunk sizes, short utterances and no audio leaking between recordings.
- Whisper tests use the actual production manager with fake loaders/contexts: shared success, cancellation, invalidated results released once, replacement generations, sample-read failure and retirement after all active inferences finish.
- Streaming and paste tests do not contact providers, read real credentials or send keystrokes to other applications.
- The Whisper implementation received an independent agent review. A separate paste review identified cancellation/restoration and cancelled-paste auto-send concerns; both were corrected before the full test run.
- `git diff --check` passes. After test-only compiler-warning cleanup, the focused streaming rerun passed **9/9** with no compiler warnings reported. Its result bundle (`Test-VoiceInk-2026.09.19_16-59-51-+1000.xcresult`) has since been pruned by Xcode; the 17-45-03 full run above includes the same nine tests.

## Remaining release verification and scope limits

This is a tested correctness patch, not certification of accessibility or reliability across all supported machines.

1. Perform live built-in/USB/Bluetooth microphone recordings, unplug/switch/sleep/wake tests and WAV inspection. A permanently stalled HAL callback intentionally keeps stop pending on the hardware queue while the UI actor remains available; freeing its resources would be unsafe. No live driver stall was induced.
2. Verify VoiceOver, Full Keyboard Access, Sticky Keys, Reduce Motion, alternate layouts and actual paste delivery/restoration in native, Electron and terminal editors. Posting an event is not proof that another app consumed the transcript. Auto-send still relies on the existing target/focus behavior.
3. Verify a real-model XPC round trip and native Whisper inference on supported hardware. Cancellation of native loading/inference remains cooperative; it does not release resources underneath native code.
4. Exercise real Keychain upgrades and CloudKit/background dictionary maintenance with concurrent edits. Freeze historical SwiftData model definitions before a future schema change.
5. The private FluidAudio prewarm registry/runtime remains a separate owner. Sharing it with inference safely requires handling preparation/inference/cleanup reentrancy; this patch improves task lifecycle without introducing that broader runtime redesign.
6. Collect base-versus-branch latency, idle CPU, retained memory and long-session/drop measurements. Offline-mode network isolation still needs an end-to-end release check.

The two P1 review findings are addressed. The broader checks above remain explicit follow-up work rather than being represented as completed by unit tests.
