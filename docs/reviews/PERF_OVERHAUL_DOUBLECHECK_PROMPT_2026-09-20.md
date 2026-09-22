# Prompt for a second independent double-check (2026-09-20)

Work in `~/Developer/voiceink-sync`, not the Desktop/iCloud copy (builds hang there).
Review only: do not edit source or docs, commit, push, or publish. Running the build/test commands
below and producing their normal build artifacts is authorized. If a Debug build succeeds you may run
`bash ./reset_permissions.sh` as `AGENTS.md` requires; that is the only state change permitted.

## What we are trying to achieve

`perf/mac-architecture-overhaul` is a performance and architecture overhaul of the VoiceInk macOS app
(committed head `5d03c7e3`, branched from `87a44f47`). Two independent reviews and one remediation
pass have since produced a large **uncommitted** working tree whose goal is:

1. Make the overhaul safe to merge into `custom-main-v2`: no use-after-free in the Core Audio render
   path, no shared Whisper context released under a concurrent waiter, no streaming provider retained
   by an idle stream, no paste of foreign clipboard content, no Enter keystroke after a failed paste,
   Reduce Motion honoured, no dictated text in native console output.
2. Preserve normal behaviour for everyone else: pastes still land, clipboards still restore, custom
   Whisper prompts still apply per request, animations still run when Reduce Motion is off.
3. Leave an honest record: the changelog describes only what changed, tests exercise production code,
   documents state their limits, and release checks that need real hardware are listed, not implied.

Your job is to decide whether the current tree meets those goals, and to catch anything the previous
agents (including the one who wrote this prompt) got wrong.

## Read first

1. `AGENTS.md`
2. `docs/reviews/PERF_OVERHAUL_DOUBLECHECK_2026-09-20.md` — the latest review, its fixes and results
3. `docs/reviews/PERF_OVERHAUL_VERIFICATION_BRIEF_2026-09-19.md` and the documents it links
4. `docs/reviews/PERF_OVERHAUL_DOUBLECHECK_PROMPT_2026-09-19.md` — the previous review's brief

Treat every statement in those documents, including all merge verdicts, as a claim to verify.

## Run first

```sh
cd ~/Developer/voiceink-sync
xcodebuild test -project VoiceInk.xcodeproj -scheme VoiceInk -configuration Debug \
  -derivedDataPath .local-build -destination 'platform=macOS,arch=arm64' \
  -only-testing:VoiceInkTests -parallel-testing-enabled NO \
  -skipPackagePluginValidation -skipMacroValidation \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

Expected: **251 XCTest cases executed, 2 skipped (no audio input device on the host), 0 failures**;
the `.xcresult` bundle counts 252 including Swift Testing's `example()`. Record the bundle path,
compiler warnings, and how many `VoiceInk/` and `Tests/` sources actually recompiled. If few or none
did, the warning check proves nothing; remove `.local-build/Build` and rerun to get a clean build.
Xcode prunes old bundles, so distinguish pruned historical evidence from new failures.

Known intermittent: the test host has twice exited silently during `TTSViewModelTests`
(`testRapidAllocDealloc`, `testViewModelDoesNotLeak`), once at `5d03c7e3` and once in the 2026-09-20
clean build. Xcode relaunches the host and counts one failure. If it happens, rerun the test alone and
the suite again, report both, and try to explain the exit; do not silently accept it as flaky. When
passing xcodebuild arguments in zsh, write them out; an unquoted `$var` is not word-split.

## Scope

Verify branch and head, then review **all tracked and untracked changes** against `5d03c7e3`
(`git status --short`, `git diff 5d03c7e3`, and every untracked file). Use `87a44f47` to classify
anything as pre-existing. Do not discard the older remediation when reviewing the newest edits.

Changed since the previous review (all uncommitted):
`CursorPaster.swift` (`shouldSkipPaste`, cancelled-wait log guard, `pasteAtCursor` notification),
`CursorPaster+Feedback.swift` (new), `TranscriptionDelivery.swift`, `AudioSampleReader.swift`,
`Localizable.xcstrings` ("Recording", "Recording mode"), `CHANGELOG.md`,
`Tests/VoiceInkTests/Infrastructure/PasteSkipDecisionTests.swift` (new), and the two review documents.

## Priorities

1. **Paste skip decision.** The previous fix relaxed the guard so a paste is skipped only when the
   pasteboard revision moved *and* `string(forType: .string)` differs from the transcript. Argue both
   directions: can foreign content now be pasted (for example, content whose plain-text form equals
   the transcript but whose rich representations differ, or a race between the text read and the
   Cmd+V)? Does a plain-text sanitizer that strips the session marker still paste, and what happens
   to clipboard restoration in that case (restoration still requires the original revision)? Check
   the autoclosure really avoids a pasteboard read on the unchanged path. Confirm the skip
   notification appears exactly once for delivery and for History re-paste, and never for
   `.commandNotPosted`. Inspect `PasteSkipDecisionTests`: it tests a pure helper, not
   `performPasteSession`; say so.
2. **Preserve the earlier clipboard invariants.** Change count captured after the transcript and
   metadata write; restoration scheduled through the `defer` on cancel and skip; `restoreIfOwned`
   requires revision, text and marker and rechecks the revision before `clearContents()`; the
   unavoidable external-write window between that recheck and the clear.
3. **AudioSampleReader.** The unused-result warning fix now trims `samples` when fewer samples were
   decoded than reserved. Confirm `PCMSampleConversion.writeFloatSamples` can only return
   `bytes.count / 2` or 0, that the trim cannot corrupt earlier chunks, and that the carry-byte
   handling around it is unchanged. Confirm no `Data(contentsOf:)` whole-file read returned.
4. **Localization.** Confirm the two new catalogue entries are well formed, sorted where Xcode would
   place them, and that no other new user-facing string in the tree lacks `de`/`zh-Hans` entries
   (compare against neighbouring keys; a few pre-existing keys legitimately have none).
5. **Everything the earlier prompts asked for**, re-verified rather than trusted: Whisper generation
   lifetime and prompt isolation (including that an empty native prompt is equivalent to none);
   audio close/stop/unbounded-drain ordering, gate reopen precondition, `audioSetupQueue` ownership
   including deinit; Reduce Motion at every explicit animation site under `Features/Recording`;
   the nine init-only LLMkit client streams at the pinned revision and the 10 s final-commit timeout;
   prewarm cancellation and coalescing; auto-send never firing for a non-posted paste.
6. **Documentation honesty.** Check the changelog describes only real behaviour, the "44 added tests"
   count, the result bundles cited in `PERF_OVERHAUL_DOUBLECHECK_2026-09-20.md` still exist, and that
   the pre-existing/introduced classification in that document is correct. Earlier documents describe
   historical states; do not report their stale numbers as errors.

## Report

Only actionable findings, each with severity, `file:line`, trigger, and user impact. Separate:
introduced regressions, pre-existing defects, test or claim gaps, and unverified release checks.
State which tests exercise production code versus copies, and which tests would expose an original
defect versus merely preserve behaviour. Do not interpret unit-test success as live audio,
accessibility, clipboard-manager, Keychain, CloudKit or native-inference validation. Conclude
separately whether the working tree is **ready to merge** and **ready to release**, and list what a
commit of this tree should contain if you judge it ready.
