# Performance overhaul follow-up fixes — 2026-09-19

Repository: `~/Developer/voiceink-sync`; branch `perf/mac-architecture-overhaul`;
committed head `5d03c7e3`; pre-overhaul baseline `87a44f47`.
All remediation and follow-up changes remain uncommitted. Nothing was published.

This report supersedes the earlier review's remaining clipboard and Reduce Motion findings.
The original remediation documents remain historical records, not current test inventories.

## Changes

- Clipboard restoration now uses the production `ClipboardSnapshot` helper. It retains the
  original readable representations and restores only when the post-transcript-write change
  count, transcript text, and session marker still match. It rechecks the count immediately
  before clearing. `CursorPaster` passes the captured count through its existing deferred
  restoration path, including cancelled paste sessions. A clipboard-manager rewrite retaining
  both text and marker no longer passes the restoration guard.
- All explicit animation sites under `Features/Recording` now honor Reduce Motion: record
  button and status transitions, assistant scrolling, mini recorder resizing, notch resizing
  and delayed fades, alongside the existing waveform/spinner/progress-dot changes.
- Removed the unused `promptDidChange` notification, engine observer, manager `updatePrompt`,
  and protocol/fake `setPrompt` requirement. Kept concrete Whisper context prompt assignment
  inside the synchronous inference operation, including clearing the prompt for a nil request.
- Strengthened the slow-callback test: after the diagnostic it holds the callback for another
  100 ms, observes an inverted premature-completion expectation, and checks the gate is drained
  before the waiting worker returns.
- Updated the changelog and current verification brief.

## Correction to the earlier prompt finding

The cached-prompt update was redundant, not evidence that user customization was ignored.
Production transcription requests already resolve saved language prompts and forward them to
Whisper. `FileTranscriptionSession.prepare` captures the prompt for that recording. Removing
out-of-band context mutation preserves request isolation; it does not add a cached fallback.

## Verification

- Full prescribed Debug arm64 command: **247 XCTest cases executed, 2 skipped, 0 failures**.
  Including Swift Testing's example: **248 total, 246 passed, 2 skipped, 0 failures**.
- Full result: `.local-build/Logs/Test/Test-VoiceInk-2026.09.19_19-31-43-+1000.xcresult`.
- No Swift compiler warnings reported; this was incremental compilation, not a clean build.
- Five new `ClipboardSnapshotTests` use unique named pasteboards and call the actual production
  restore helper: changed revision with preserved marker/text, ordinary user copy, full readable
  multi-item restoration, empty original clipboard, and text/session mismatch. They do not touch
  the user's general clipboard or send keys. The preserved-marker rewrite case exposes the
  pre-existing defect; other cases preserve existing behavior.
- One new `FileTranscriptionSessionPromptTests` case exercises real preparation, language-prompt
  resolution and session snapshots with a capturing service. It restores the saved defaults.
  This is preservation coverage, not a native-inference test or a reproduction of the removed
  no-op observer. There are now 40 added tests relative to the reviewed head.
- The full run covered the first drain-return assertion. A subsequent focused audio run covers
  the final 100 ms observation window: **4 passed, 0 failures**. Result:
  `.local-build/Logs/Test/Test-VoiceInk-2026.09.19_19-33-39-+1000.xcresult`.
- Repository-required `reset_permissions.sh` succeeded after both Debug runs, resetting TCC
  permissions and onboarding for `com.tmm22.VoiceLinkCommunity`.

## Independent sub-agent review

A read-only sub-agent independently reviewed the follow-up implementation, call sites, tests,
and baseline distinctions while the primary agent ran the full test command. It found no
introduced blocking regression and recommended merge subject to successful verification.
It confirmed production-helper clipboard coverage, removal of all obsolete prompt callers,
request-scoped prompt preservation, and Reduce Motion guards at every explicit animation site
under `Features/Recording`. Its suggestion to strengthen slow-drain observation was applied.
The primary agent separately inspected the changes and verified the test results.

## Limits and release checks

- `NSPasteboard` has no atomic compare-and-swap. A different process can still write between the
  final revision check and `clearContents()`. This fix rejects newer revisions observable at the
  check; it does not promise elimination of all cross-process races. Snapshot restoration covers
  readable representations; unavailable promised data was already omitted by the old code.
- No end-to-end paste-session cancellation/restoration test or direct notification-count test
  was added. Existing source checks and auto-send tests are not proof of cross-app consumption.
- No live VoiceOver/Reduce Motion UI validation was performed. Source coverage is not a visual
  accessibility certification.
- The WAV stop test still uses a held gate admission without a real audio unit. It would fail the
  old stop path, which skips waiting and closes the file in that configuration, but does not
  specifically reproduce a hardware callback stuck in AudioUnitRender or a device-switch stall.
- Streaming tests still use the production shared base with a subclass mirroring Cartesia hooks;
  the native Cartesia client and real vendor sessions remain untested.
- Prewarm cancellation is cooperative. An active async method retains its service until it
  returns; deinit does not forcibly interrupt native loading. No overlapping preparation found.
- Live microphone/device/sleep/wake checks, clipboard managers and target editors, native
  Whisper/XPC inference, real Keychain upgrades, concurrent CloudKit maintenance, performance
  measurements and offline network isolation remain release checks.

Merge assessment: ready as a corrective patch. Release assessment: not yet verified.
