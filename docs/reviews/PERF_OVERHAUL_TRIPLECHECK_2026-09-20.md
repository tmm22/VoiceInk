# Remediation and triple-check — 2026-09-20

> This records the earlier verification and conservative assessment. See the subsequent
> [merge assessment](PERF_OVERHAUL_MERGE_ASSESSMENT_2026-09-20.md) for the clean five-run check,
> baseline comparison, startup-recovery fix and final merge recommendation.

Repository: `/Users/deborahmangan/Developer/voiceink-sync`, branch
`perf/mac-architecture-overhaul`, HEAD `5d03c7e3`. User authorized implementation after the
independent review. Existing remediation was preserved. No commit or publication performed.

## Findings addressed

- **Clipboard representations:** the production skip decision now permits a changed revision only
  when it has one item, the expected plain text, exclusively known plain-text/metadata types, and a
  revision that remains stable during inspection. Same-text RTF, HTML, attachments, extra items and
  unknown types skip. A plain-text sanitizer can still paste, but its newer clipboard is not restored
  over. The former text-only helper was removed; its tests now use the production decision on named
  pasteboards. This was an incomplete remediation, not a newly introduced foreign-paste regression
  against `5d03c7e3` (which had no skip guard).
- **Snapshot responsiveness:** representation data is captured on a detached worker, constructing
  its own pasteboard handle there. Main-actor code checks the captured revision before writing and
  honors cancellation. A slow promised representation can still delay that paste, but the read no
  longer blocks the UI executor. No timeout discards the user's clipboard contents.
- **Device-switch failures:** all reconfiguration errors run the same recovery transaction. Recovery
  rebuilds the old device and its formats/buffers, not just its device property. Failure of recovery
  closes the recording and informs the engine, which uses cancellation to save the partial file and
  reset the recording UI. Hardware state stays on the serial setup queue.
- **Stalled callbacks:** resources are still retained until callbacks return. A five-second drain
  watchdog reports the wait to the user; polling backs off after 200 ms. A separate five-second stop
  watchdog restores system audio independently of the drain, including a stuck OS stop call. Normal
  stops restore media only after capture ends, avoiding resumed media in the recording tail.
  This mitigates the silent/muted hang without
  reintroducing use-after-free. It does **not** guarantee that a permanently stalled driver returns,
  nor show the callback-drain warning for a hang inside the OS stop call before that drain begins.
- **Integration coverage:** seven new paste-session/feedback tests invoke the production session,
  writer, snapshot and ownership check on private named pasteboards. Injected dependencies replace
  only waiting, command posting, restore scheduling and notification display. No real Cmd+V or Enter
  is sent and the user's general clipboard is not touched. Tests cover rich rewrites, extra items,
  sanitizer rewrites, owned restoration, cancellation, failed posting and notification selection.
  Three tests exercise the actual device-switch transaction with injected setup/recovery failures;
  they do not inject errors into HAL itself. One test verifies the stall watchdog retains ownership.
- **Test isolation:** lifecycle tests previously invoked actual preview loading, including downloaded
  PocketTTS assets. They now inject asynchronous cancellation-aware preview dependencies and omit
  notification authorization. Nine lifecycle cases were moved out of the oversized test file;
  the main file is now below 500 lines. This removes a demonstrated source of external interference,
  but does not establish the cause of the earlier exit-code-zero test-host interruptions. App
  termination call sites and the delegate were inspected; no test-triggered termination was found.
- **Async test harness:** removed a custom `fulfillment` overload that synchronously blocked inside
  a checked continuation. Callers now use XCTest's native async API. A regression test schedules
  main-actor work while awaiting an expectation. This is an independently verified harness defect,
  not an established cause of the intermittent exit.
- **Claims:** changelog now qualifies clipboard safety, describes the recovery/watchdog boundaries,
  and records 56 added tests rather than 44. Earlier reports remain historical, not current proof.

## Verification

- Initial implementation run (`08-22-41`): 260 XCTest cases, two hardware skips, no failures.
- Expanded implementation run (`08-25-24`): 262 XCTest cases, two hardware skips, no failures.
- Three fresh-process repetitions (`08-28-04`): 789 total runs including Swift Testing, 783 passed,
  six skipped, zero failures. This preceded the final normal-stop media-restoration refinement.
- **Clean rebuild and three repetitions** (`Test-VoiceInk-2026.09.20_08-31-15-+1000.xcresult`):
  all 509 `VoiceInk/` and 41 `Tests/` Swift sources recompiled. No Swift compiler warnings; four
  MLX C++17-extension warnings and two AppIntents metadata-extraction warnings. Compilation passed,
  but the tests did **not**: 789 runs, 780 passed, six skipped, three test-host exit-code-zero
  interruptions (`testHiddenPocketVoicesPersistAcrossViewModelInstances`, `testTextSnippetsProperty`,
  `testArticleSummaryTaskCancellation`). Preview dependency isolation therefore does not fix the
  host exit. No assertion failure was reported, but these are still failed test runs.
- Follow-up diagnostics: five isolated TTS-suite repetitions passed. Temporary test-only `atexit`
  backtraces showed XCTest's normal termination after those completed runs. The mediaremote-adapter
  dependency's `exit(0)` was inspected and ruled out as an in-process path: its parent monitor is
  bootstrapped by its separate Perl helper. Five full-suite diagnostic repetitions also passed
  (`Test-VoiceInk-2026.09.20_12-21-51-+1000.xcresult`: 1,315 runs, 1,305 passed, ten skipped).
  All captured exit backtraces were XCTest's normal exit after completion, not an abnormal exit.
  The temporary backtrace instrumentation was removed; the abnormal exit's cause remains unknown.

- **Final verification**, after removing the blocking expectation helper and temporary diagnostics:
  `Test-VoiceInk-2026.09.20_12-25-07-+1000.xcresult`, three fresh-process full-suite repetitions,
  each **263 XCTest cases, two hardware skips, zero failures**. Including Swift Testing: 792 runs,
  786 passed, six skipped. No unexpected host restart and no Swift compiler warnings. This was an
  incremental test-harness rebuild atop the clean compilation above, not a second clean build.
- `git diff --check`, new-file whitespace inspection and JSON validation of `Localizable.xcstrings`
  passed. The watchdog message has German and Simplified Chinese translations. Static test method
  counts using the same search pattern are 226 at HEAD versus 282 now: 56 added tests.
- `bash ./reset_permissions.sh` ran after the successful final Debug verification, as required by
  the repository instructions. This resets app permissions and the onboarding flag; the next launch
  will request permissions again. Build cleaning removed only generated build products.

Result bundles are under `.local-build/Logs/Test/`; Xcode may prune older runs.

## Remaining platform limits and release checks

NSPasteboard has no atomic compare-and-paste or compare-and-restore operation. Another process can
write after the last revision check and before Cmd+V is consumed or restoration clears the board.
These windows cannot be honestly described as eliminated by this patch.

A permanently stuck render callback intentionally retains its resources and keeps stop pending.
Freeing or reusing them at a deadline is unsafe. The warning/backoff/media restoration are mitigations,
not a claim of bounded driver recovery. Device-switch rollback and the partial-recording UI path
still need physical-microphone testing, including unplugged/unavailable old devices.

Also outstanding: live capture/device switching/sleep-wake; clipboard-manager and target-app delivery;
VoiceOver and Reduce Motion; Keychain upgrades; CloudKit maintenance; native Whisper inference/prompt
isolation and console privacy; performance measurements and offline/network isolation. Unit tests do
not certify these. Repeated passing TTS tests do not prove the prior silent host exit is fixed.

## Assessment

The identified clipboard/audio code defects and coverage gaps have fixes and regression coverage.
The driver-lifetime and clipboard atomicity limits are explicitly retained, not hidden by unsafe
timeouts or stronger claims. There is **no unconditional merge sign-off** while the intermittent
test-host exit remains unexplained. Release readiness is **not verified** pending the platform checks
above. A later commit should include the complete existing remediation, the new helpers/tests,
localizations and updated review/changelog; nothing has been staged, committed or pushed here.
