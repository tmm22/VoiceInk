# Apple UI Best Practices Audit Report

Date: 2026-05-01  
Plan: `plans/APPLE_UI_BEST_PRACTICES_AUDIT_PLAN.md`

## Summary

VoiceInk's macOS SwiftUI interface was audited against Apple's Human Interface Guidelines, focusing on native control behavior, accessibility, window sizing, labels, settings conventions, and high-traffic workflow polish.

Five parallel implementation slices completed the audit:

- Shared app shell and common UI primitives
- Settings and preferences
- TTS workspace
- Power Mode
- Primary feature screens

The combined patch updates 70+ Swift UI files plus the audit plan and this report.

## Major Improvements

### App Shell And Shared UI

- Moved the root sidebar closer to native macOS sidebar behavior.
- Removed custom selected-row styling that fought system list behavior.
- Added meaningful navigation titles and a more flexible sidebar width.
- Adjusted app window sizing to use a default size plus content minimum size.
- Made shared cards quieter with less shadow and more semantic typography.
- Updated shared copy/save/drop-zone controls with clearer labels and help text.
- Improved menu bar command wording and state-aware recording labels.

### Settings And Preferences

- Replaced empty picker, toggle, and text field labels with semantic labels.
- Used `.labelsHidden()` only where a visible label already exists.
- Improved Settings search accessibility, clear-button labeling, and empty-results copy.
- Added help text and practical hit targets to icon-only controls.
- Made shortcut keycaps read as reference information rather than tappable controls.
- Replaced a custom permission action button with a native prominent bordered button.

### TTS Workspace

- Replaced custom playback scrubber tracks with native `Slider` controls.
- Added accessible playback values and better media control labels.
- Added help text and minimum hit areas to icon-only toolbar/media/inspector controls.
- Fixed empty picker labels in TTS settings and inspector views.
- Relaxed rigid popover and settings sizing with min/ideal/max frame constraints.
- Clarified the command strip menus so Actions and More are distinct controls.

### Power Mode

- Replaced SwiftUI-view `NSAlert` delete confirmations with SwiftUI confirmation dialogs.
- Added semantic labels and accessibility help to trigger, emoji, app picker, and model refresh controls.
- Relaxed fixed picker/popover sizing.
- Switched important actions toward native `.bordered` and `.borderedProminent` styles.
- Removed forced unwraps from Power Mode navigation actions.

### Primary Feature Screens

- Added semantic labels, help text, and hit areas to icon-only controls in recorder, model cards, history, trash, audio player, dictionary, and copy controls.
- Added destructive roles to model/delete actions where missing.
- Improved history/card row accessibility for selection and row actions.
- Converted onboarding skip affordances into real buttons.
- Added minimum onboarding window sizing.
- Removed duplicated `OnboardingModelDownloadView` content paths and split the view into smaller helpers.

## Integration Cleanup

After merging the worker slices, the integration pass fixed:

- Three trailing-whitespace issues in common UI files.
- Remaining empty controls in `EnhancementSettingsView.swift`.
- Aggregate empty-label checks across audited UI folders.

## Verification

Passed:

- `git diff --check`
- `xcrun swiftc -parse` over all changed Swift files
- `rg 'Picker\(\"\"|Toggle\(\"\"|TextField\(\"\"|SecureField\(\"\"' VoiceInk/Views VoiceInk/TTS/Views VoiceInk/PowerMode VoiceInk/VoiceInk.swift`

The empty-label search now finds no remaining matches in the audited UI folders.

Blocked:

- Full `xcodebuild -scheme VoiceInk -destination 'platform=macOS' build`

Multiple attempts reported an out-of-date local CoreSimulator framework:

```text
current 1051.49.0, required 1051.50.0
```

After reporting that framework mismatch, `xcodebuild` stopped progressing without Swift compiler diagnostics. Worker duplicate build attempts were terminated to avoid leaving stuck build processes.

## Residual Risk

- Full app build and launch QA still need to run after the local Xcode/CoreSimulator installation is repaired.
- Visual QA should still cover light mode, dark mode, increased contrast, reduced motion, VoiceOver labels, keyboard-only navigation, and resized windows.
- Some app-lifecycle `NSAlert` usage remains in `VoiceInk.swift`; this was intentionally left because it is AppKit lifecycle UI rather than SwiftUI view-local confirmation UI.

