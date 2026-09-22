# Merge assessment — 2026-09-20

## Decision

**Recommend merging the complete remediated working tree into `custom-main-v2`.** This is an
engineering recommendation based on review and repeatable checks, not a guarantee of zero defects
or a release certification. Do not merge committed HEAD `5d03c7e3` alone: the fixes and their new
helper/test files are still uncommitted.

This supersedes the conservative assessment in
[the earlier triple-check](PERF_OVERHAUL_TRIPLECHECK_2026-09-20.md). The additional evidence is a
fresh clean build with five successful suite repetitions, a separate baseline control build, a
startup-failure correction with engine-level tests, and three successful final suite repetitions.
No currently reproducible test failure or identified regression in the remediated changes remains.

## Verification

- **Clean current-tree build:** all 509 app and 42 test Swift source files recompiled. No Swift
  compiler warnings. Four existing MLX C++17-extension warnings and two AppIntents metadata-extraction
  warnings remain. Five fresh-process repetitions each executed 263 XCTest cases with two hardware
  skips and zero failures. Including Swift Testing: 1,320 runs, 1,310 passed, ten skipped.
  Original bundle: `Test-VoiceInk-2026.09.20_14-38-18-+1000.xcresult`.
- **Unchanged committed baseline:** detached worktree at `5d03c7e3`, no source edits, separate clean
  build directory and identical dependency revisions. Three repetitions each executed 207 XCTest
  cases with two skips and zero failures. Including Swift Testing: 624 runs, 618 passed, six skipped.
  Baseline compilation also reproduced the `AudioSampleReader` unused-result warning already fixed
  in the current tree. Original bundle: `Test-VoiceInk-2026.09.20_14-45-02-+1000.xcresult`.
- **Final tree:** after the startup correction and removal of temporary exit diagnostics, three
  fresh-process full-suite repetitions each executed **266 XCTest cases, two hardware skips,
  zero failures**. Including Swift Testing: **801 runs, 795 passed, six skipped**. No unexpected
  restart or Swift compiler warning. This was an incremental rebuild atop the clean compilation,
  not a claim of another clean build. Original bundle:
  `Test-VoiceInk-2026.09.20_19-41-25-+1000.xcresult`.
- **Merge target:** both local and remote `custom-main-v2` were checked at
  `87a44f4784b21f231f9253c25db22c30435f378f`, an ancestor of HEAD. The target has zero unique commits;
  this branch has twelve. There is no divergent target integration to resolve at the checked state.
  Recheck this if the remote advances before merging.
- `git diff --check` and string-catalogue JSON validation passed. No temporary `atexit` instrumentation
  remains. The source review rechecked callback resource ownership, device recovery, Whisper
  generations/prompt isolation, streaming-task ownership, paste/restore/auto-send paths and the
  Reduce Motion changes.

Preserved bundles and build logs are under `.local-build/merge-verification/`:
`clean-five-runs.xcresult`, `baseline-5d03c7e3.xcresult`, and `final-three-runs.xcresult`.
These copies are outside Xcode's normal test-log pruning directory. The temporary baseline worktree
and its generated products were removed after preserving evidence; the user's working tree was not
reset or overwritten. Permissions/onboarding were reset after the final Debug build as repository
instructions require.

## Last correction

The device-failure callback previously cancelled only `.recording`, leaving a narrow startup window
unhandled. It now cancels both `.starting` and `.recording`. Three tests invoke the real engine callback
and cancellation path against an in-memory, non-CloudKit model container. They verify startup
cancellation, active-capture cancellation, and no cancellation of an already-finished capture's
transcription/enhancement pipeline. They do not claim to simulate an actual HAL device failure.

There are now 59 added tests relative to HEAD: 207 to 266 executed XCTest cases. The changelog was
updated accordingly. The earlier clipboard, callback-gate, device-switch recovery, Whisper,
streaming, accessibility, preview-isolation and async-expectation fixes are all preserved.

## Historical test-host exits and residual risk

The earlier exit-code-zero interruptions remain genuine historical failures. **Their exact cause
has not been established, and this report does not claim they are fixed.** The new clean five-run
check confirmed the isolated test runtime was active. Temporary exit backtraces captured only
XCTest's normal shutdown after completed suites; there was no abnormal exit to diagnose. Both the
baseline control and final candidate passed. The baseline pass does not establish the cause or
prove the historical exits predate the patch.

The recommendation changed because verification now includes clean repeated execution after the
test-harness correction, the control build, targeted engine coverage, and final repeated execution
without diagnostic instrumentation. The non-reproducing historical symptom remains a tracked
investigation item, not an identified regression on which to block this merge indefinitely. If it
returns in CI, preserve that failed result and capture its exit stack before treating a rerun as
resolution.

Release still needs live microphone capture/switching/sleep-wake, cross-application clipboard
delivery, VoiceOver/Reduce Motion, native inference/privacy, Keychain/CloudKit and performance checks.
NSPasteboard's external-write windows cannot be made atomic, and a permanently stalled callback
must retain its resources rather than free them on a deadline. The existing diagnostics and media
restoration mitigate that stall; they do not guarantee recovery from a broken driver.

## Commit/merge scope

Include the complete tracked remediation, all new production helpers and test files, localization,
changelog and review records. In particular, do not omit currently untracked Swift files: compilation
and verification included them. No commit, push or merge was performed during this assessment.
