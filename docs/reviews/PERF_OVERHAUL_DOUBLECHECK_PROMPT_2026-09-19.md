# Prompt for an independent double-check

Work in `~/Developer/voiceink-sync`, not the Desktop/iCloud copy.
Review only: do not edit source/docs, commit, publish, or reset permissions/settings. Running the
requested build/test command and its normal build artifacts is authorized. If local AGENTS.md
asks for permission/onboarding resets, this explicit review-only instruction takes precedence.

Read `AGENTS.md`, `docs/reviews/PERF_OVERHAUL_VERIFICATION_BRIEF_2026-09-19.md`, its referenced
review/remediation documents, and `docs/reviews/PERF_OVERHAUL_FOLLOWUP_2026-09-19.md`.
Treat their claims and the previous agents' merge verdicts as unverified.

Run this command before inspecting implementation changes:

```sh
cd ~/Developer/voiceink-sync
xcodebuild test -project VoiceInk.xcodeproj -scheme VoiceInk -configuration Debug \
  -derivedDataPath .local-build -destination 'platform=macOS,arch=arm64' \
  -only-testing:VoiceInkTests -parallel-testing-enabled NO \
  -skipPackagePluginValidation -skipMacroValidation \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

Expected current count: 247 XCTest cases, 2 skipped, 0 failures; 248 including Swift Testing's
example. Record the actual result bundle, compiler warnings and whether compilation was
incremental. Xcode prunes old bundles: distinguish pruned historical evidence from new failures.

Verify branch/head and independently review all tracked AND untracked changes against
`5d03c7e3`, using `87a44f47` to classify pre-existing behavior. Do not discard the older
uncommitted remediation when reviewing these latest additions.

Prioritize:

1. Clipboard: follow the actual CursorPaster defer/scheduling path into ClipboardSnapshot.
   Confirm the expected count is captured after the transcript/metadata write and never replaced
   by a later revision. Confirm newer clipboard-manager revisions retaining text and marker are
   rejected, unchanged sessions restore readable multi-item contents, and cancellation retains
   restoration scheduling. Inspect all five tests: they must call production code and the
   preserved-marker rewrite case must expose the old defect. Be explicit about the unavoidable
   non-atomic external-write interval between checking changeCount and clearing the pasteboard.
   Recheck skipped-result notification and auto-send guards; helper tests do not prove those
   integration paths.
2. Whisper prompts: verify no promptDidChange/updatePrompt callers remain. Trace saved custom
   language prompts through runtime configuration, FileTranscriptionSession preparation and
   WhisperTranscriptionService into native inference. Confirm prepared sessions retain their
   original prompt, new sessions see changed preferences, and nil clears the previous native
   prompt. Do not characterize removal of the redundant cache setter as fixing ignored custom
   prompts; the per-request path already existed. Check the new session test's real production
   coverage and defaults restoration.
3. Accessibility: inspect every explicit animation/withAnimation/TimelineView under
   Features/Recording, including mini/notch expansion and fades, recorder controls/status,
   assistant scrolling, waveform, spinner and dots. Confirm Reduce Motion is respected without
   changing normal animation behavior. Separate source verification from unperformed live UI
   checks; consider any inherited animation or AppKit window-animation paths separately.
4. Audio: recheck close/stop/unbounded-drain ordering, queue ownership and gate reopen invariants.
   Check the strengthened slow-drain test's inverted 100 ms observation and return assertion.
   Explain exactly why the readable-WAV test fails the old no-unit stop path and why it is not
   evidence of live device-switch or HAL-stall coverage.
5. Preserve the original generation-lifetime, streaming ownership/finalization, paste
   cancellation/notification/auto-send and prewarm invariants in the earlier brief. Recheck the
   nine init-only client streams and final-commit timeout against the checked-out dependency.
6. Documentation: verify changelog behavior, localization, 40 added tests, current counts and
   available result bundles. Check the follow-up report's corrected prompt finding and explicit
   test/manual-check limitations. Earlier documents describe historical states.

Report only actionable findings with severity, file:line, trigger and user impact. Separate
introduced regressions, pre-existing defects, test/claim gaps and unverified release checks.
State which tests exercise production code versus copies, and distinguish preservation tests
from tests that expose an original defect. Conclude separately whether the working tree is
ready to merge and ready to release. Do not interpret unit-test success as live audio,
accessibility, clipboard-manager, Keychain, CloudKit or native-inference validation.
