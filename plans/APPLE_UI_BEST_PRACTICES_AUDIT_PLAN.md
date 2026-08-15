# Apple UI Best Practices Audit Plan

Created: 2026-05-01  
Workspace: `/Users/deborahmangan/Desktop/Prototypes/dev/untitled folder 3`

## Goal

Audit VoiceInk's macOS SwiftUI interface against Apple's current Human Interface Guidelines and correct mismatches without changing product intent, privacy posture, or the app's existing architecture.

This is a codebase-wide UI quality pass. The work should prefer native macOS behavior, semantic SwiftUI controls, accessible labels, dynamic system colors/materials, and predictable keyboard/mouse behavior over custom styling where custom styling does not add product value.

## Source Of Truth

Use Apple's official Human Interface Guidelines and developer documentation as the source of truth:

- Designing for macOS: https://developer.apple.com/design/human-interface-guidelines/designing-for-macos
- Layout: https://developer.apple.com/design/human-interface-guidelines/layout
- Windows: https://developer.apple.com/design/human-interface-guidelines/windows
- Toolbars: https://developer.apple.com/design/human-interface-guidelines/toolbars
- Settings: https://developer.apple.com/design/human-interface-guidelines/settings
- Accessibility: https://developer.apple.com/design/human-interface-guidelines/accessibility
- Buttons: https://developer.apple.com/design/human-interface-guidelines/buttons
- Labels: https://developer.apple.com/design/human-interface-guidelines/labels
- Text fields: https://developer.apple.com/design/human-interface-guidelines/text-fields
- Pickers: https://developer.apple.com/design/human-interface-guidelines/pickers
- SF Symbols: https://developer.apple.com/design/human-interface-guidelines/sf-symbols
- Color: https://developer.apple.com/design/human-interface-guidelines/foundations/color/
- Typography: https://developer.apple.com/design/human-interface-guidelines/typography
- Materials: https://developer.apple.com/design/Human-Interface-Guidelines/materials

## Initial Inventory

The first pass found:

- About 242 SwiftUI `View` structs across `VoiceInk/Views`, `VoiceInk/TTS/Views`, `VoiceInk/PowerMode`, and `VoiceInk.swift`.
- Existing UI test coverage in `VoiceInkUITests` for settings, recorder, model management, onboarding, dictionary, and launch.
- Main shell uses `NavigationSplitView` in `VoiceInk/Views/ContentView.swift`.
- Settings uses a custom navigation rail in `VoiceInk/Views/Settings/SettingsView+Navigation.swift`.
- Shared UI primitives live under `VoiceInk/Views/Common` and `VoiceInk/Utilities/DesignSystem.swift`.
- Dense/custom UI areas include TTS workspace, Power Mode, model management cards, recorder overlays, settings, history, dictionary, and onboarding.

## Immediate Signals From The Inventory

These are not final findings, but they should be checked first:

- Empty labels: `Picker("")`, `Toggle("")`, and `TextField("")` appear in Power Mode, TTS, settings, history, dictionary, and context settings.
- Mixed alert APIs: both `NSAlert` and SwiftUI `.alert` are used in UI flows.
- Hardcoded user-facing strings are common in TTS, settings, dictionary, model management, history, and alerts.
- Several fixed dimensions exist for windows, popovers, sheets, cards, and compact views.
- Custom sidebar/settings rail selection styling may duplicate native macOS list/sidebar behavior.
- Icon-only and `.plain` buttons need consistent accessibility labels, help text, focus behavior, and minimum hit areas.
- Custom cards/shadows may over-card settings and utility surfaces compared with native macOS conventions.
- Some labels use ASCII `...` where the HIG expects an ellipsis character for actions requiring more input.

## Audit Checklist

### 1. macOS App Shell And Navigation

- Verify the root `NavigationSplitView` has native selection behavior, predictable sidebar state, and appropriate column widths.
- Ensure sidebar items are navigation, not actions.
- Avoid custom selection backgrounds that fight `.sidebar` list behavior unless necessary for brand clarity.
- Check that moved/hidden views such as permissions, dictionary, community, and audio input do not leave confusing top-level routes.
- Confirm window titles and navigation titles are meaningful for assistive technologies and window management.
- Ensure menu bar commands expose common app commands and use expected macOS naming.

### 2. Windows, Sheets, Popovers, And Inspectors

- Review all `.frame(width:height:)`, fixed sheet sizes, and minimum window constraints.
- Prefer resizable windows with sensible minimums over fixed dimensions.
- Ensure auxiliary windows are focused, task-specific, and have clear close/cancel affordances.
- Use sheets for modal, document/window-scoped decisions.
- Use popovers for transient contextual controls, not long-running workflows.
- Use inspectors for trailing-side detail/configuration in dense workspaces.
- Avoid hiding system window controls unless the window is intentionally a utility panel with equivalent keyboard and pointer affordances.

### 3. Toolbars And Commands

- Move frequent window-level actions into native toolbar areas where appropriate.
- Keep contextual row/card actions near the object they affect.
- Confirm destructive actions are not primary toolbar actions unless strongly justified.
- Check keyboard shortcuts for conflicts and macOS convention.
- Ensure toolbar labels and symbols remain accessible when labels are hidden.

### 4. Controls

- Replace empty `Picker`, `Toggle`, and `TextField` labels with meaningful labels plus `.labelsHidden()` where a visible label already exists.
- Use native `Button` styles (`.bordered`, `.borderedProminent`, `.plain`, `.borderless`) before custom button styles.
- Reserve prominent buttons for primary actions.
- Use roles (`.destructive`, `.cancel`) consistently.
- Use menus for secondary action groups.
- Use segmented pickers for short mutually exclusive modes only.
- Use radio groups where a settings choice benefits from visible alternatives.
- Use secure fields for API keys by default; reveal controls must have labels, help text, and privacy-conscious behavior.
- Ensure icon-only buttons have `accessibilityLabel`, `.help`, and a minimum practical hit area.

### 5. Text, Labels, And Localization

- Convert hardcoded user-facing strings to `Localization` where this project already expects localized UI.
- Use action labels that describe the result, such as `Save`, `Cancel`, `Export Settings...`, and `Choose Audio...`.
- Use the ellipsis character (`...` can remain only if the existing localization system cannot represent `...` cleanly; otherwise prefer `...` to be replaced in localized strings with the proper ellipsis if the file already contains Unicode).
- Avoid instructional in-app text that explains obvious UI mechanics.
- Keep labels concise, sentence case, and consistent across equivalent actions.

### 6. Accessibility

- Check VoiceOver labels for empty labels, icon-only buttons, cards acting as buttons, and custom row controls.
- Ensure UI does not rely on color alone for state.
- Pair audio feedback with visual status.
- Respect reduced motion for decorative or continuous animation.
- Maintain keyboard-only operation for main workflows.
- Keep target sizes close to Apple's macOS guidance: default 28x28 pt and minimum 20x20 pt where practical.
- Ensure status/progress changes expose useful accessibility values.
- Confirm contrast in light mode, dark mode, and increased contrast.

### 7. Layout And Resizing

- Check every main screen at common desktop sizes and at its minimum supported window size.
- Avoid hard-coded widths where content should adapt.
- Use semantic spacing and alignment instead of arbitrary offsets.
- Ensure text wraps or truncates intentionally.
- Avoid nested cards unless the inner card is a repeated item or a real framed tool.
- Ensure dense operational screens stay scannable without becoming marketing/landing-page layouts.

### 8. Typography

- Prefer semantic fonts (`.title`, `.headline`, `.body`, `.caption`, etc.) where possible.
- Avoid unnecessary fixed font sizes that do not adapt well.
- Keep display-scale type out of compact panels, sidebars, and cards.
- Use system font weights and sizes that maintain legibility.
- Avoid negative letter spacing and viewport-scaled font sizing.

### 9. Color, Materials, And Visual Hierarchy

- Prefer system colors by semantic purpose: label, secondaryLabel, windowBackground, controlBackground, separator, accentColor.
- Use materials for structure, not as arbitrary color effects.
- Test custom colors against light/dark/increased contrast.
- Avoid using the accent color for noninteractive emphasis in ways that make text look clickable.
- Reduce heavy custom shadows on surfaces that should feel native.
- Keep brand styling subordinate to macOS behavior and accessibility.

### 10. SF Symbols And Icons

- Verify symbols directly represent the action/content.
- Use outline vs fill variants consistently: fill for selected state or strong emphasis, outline for normal toolbar/list actions.
- Use `.symbolRenderingMode` only where it improves semantic clarity.
- Ensure custom app icons are not used where an SF Symbol would communicate a standard action better.
- Avoid Apple-restricted SF Symbol customization.

### 11. Alerts, Confirmations, And Error UX

- Prefer SwiftUI `.alert`/`.confirmationDialog` for SwiftUI views.
- Keep `NSAlert` only for app lifecycle/AppKit contexts where SwiftUI state is not available.
- Ensure destructive actions confirm clearly and do not use ambiguous titles.
- Error alerts should describe what failed and how to recover when possible.
- Avoid success alerts for routine saves if inline confirmation or disabled/enabled state is enough.

### 12. Testing And Verification

- Build with:
  - `xcodebuild -scheme VoiceInk -destination 'platform=macOS' build`
- Run targeted UI tests where practical:
  - `VoiceInkUITests/SettingsUITests.swift`
  - `VoiceInkUITests/RecorderUITests.swift`
  - `VoiceInkUITests/ModelManagementUITests.swift`
  - `VoiceInkUITests/OnboardingUITests.swift`
  - `VoiceInkUITests/DictionaryUITests.swift`
- Manually inspect:
  - Light mode
  - Dark mode
  - Increased contrast
  - Reduced motion
  - Keyboard-only navigation
  - VoiceOver labels for main actions
  - Window resizing and minimum sizes

## Execution Sequence

1. Build an audit matrix with file, screen, issue category, severity, proposed fix, and verification note.
2. Fix shared primitives first so downstream screens inherit improvements:
   - `VoiceInk/Views/Common`
   - `VoiceInk/Utilities/DesignSystem.swift`
   - `VoiceInk/Utilities/View+VoiceInkStyle.swift`
3. Fix app shell and settings:
   - `VoiceInk/Views/ContentView.swift`
   - `VoiceInk/Views/Settings`
   - `VoiceInk/Views/MenuBarView.swift`
   - relevant parts of `VoiceInk/VoiceInk.swift`
4. Fix high-traffic workflows:
   - Recorder
   - Audio transcription
   - History
   - Model management
   - Dictionary
   - Power Mode
5. Fix TTS workspace as its own phase because it is dense and has a separate layout system.
6. Fix onboarding and auxiliary sheets after shared patterns are stable.
7. Run build/tests and do visual/accessibility inspection.

## Parallel Worker Split

The work is split into disjoint ownership areas to reduce merge conflicts:

### Worker 1: Shared App Shell And Common UI

Owns:

- `VoiceInk/Views/Common/**`
- `VoiceInk/Utilities/DesignSystem.swift`
- `VoiceInk/Utilities/View+VoiceInkStyle.swift`
- `VoiceInk/Views/ContentView.swift`
- `VoiceInk/Views/MenuBarView.swift`
- relevant UI-only portions of `VoiceInk/VoiceInk.swift`

Focus:

- Native sidebar behavior
- Shared card/button/section primitives
- Window sizing and root layout
- Menu bar command labels
- App shell accessibility

### Worker 2: Settings And Preferences

Owns:

- `VoiceInk/Views/Settings/**`
- `VoiceInk/Views/PermissionsView.swift`
- `VoiceInk/Views/KeyboardShortcutCheatSheet.swift`
- `VoiceInk/Views/KeyboardShortcutView.swift`
- `VoiceInk/Views/KeyboardShortcutsListView.swift`

Focus:

- Settings organization and labels
- Empty labels
- Search field behavior
- Toggles/pickers/text fields
- Alerts and sheets
- Keyboard shortcut presentation

### Worker 3: TTS Workspace

Owns:

- `VoiceInk/TTS/Views/**`

Focus:

- Dense toolbar/command strip conventions
- Inspector behavior
- Playback controls
- Empty labels
- Popover sizing
- Hardcoded strings
- Accessibility for icon-only controls and media controls

### Worker 4: Power Mode

Owns:

- `VoiceInk/PowerMode/**`

Focus:

- Navigation and configuration flows
- App/website triggers
- Emoji picker
- Alerts and destructive confirmations
- Empty labels
- Popover/sheet sizing
- Accessible toggles and icon-only buttons

### Worker 5: Primary Feature Screens

Owns:

- `VoiceInk/Views/AI Models/**`
- `VoiceInk/Views/History/**`
- `VoiceInk/Views/Dictionary/**`
- `VoiceInk/Views/Recorder/**`
- `VoiceInk/Views/Onboarding/**`
- `VoiceInk/Views/AudioTranscribeView.swift`
- `VoiceInk/Views/TranscriptionCard.swift`
- `VoiceInk/Views/TranscriptionResultView.swift`
- `VoiceInk/Views/AudioPlayerView.swift`
- `VoiceInk/Views/TrashView.swift`
- `VoiceInk/Views/Metrics/**`
- `VoiceInk/Views/MetricsView.swift`

Focus:

- High-traffic flow polish
- Card/list row accessibility
- Recorder controls
- Model card actions
- History selection/delete/export flows
- Dictionary add/edit/delete flows
- Onboarding window sizing and navigation

## Coordination Rules For Workers

- Do not revert edits made by others.
- Keep edits within the assigned ownership scope unless a compile error requires a small adjacent fix.
- Prefer existing project patterns and `Localization`.
- Do not introduce new dependencies.
- Do not rewrite feature architecture.
- Keep changes focused on Apple UI best practices and accessibility.
- If a problem crosses ownership boundaries, document it in the final response instead of editing another worker's files.
- Run the narrowest useful verification command available. If full build is too slow or unavailable, report that clearly.

## Definition Of Done

- Major empty control labels are fixed or intentionally hidden with accessible labels.
- Common controls expose consistent accessible labels/help where icon-only.
- Fixed sizing is reduced where it harms macOS resizing.
- Alerts and destructive actions are more consistent.
- Hardcoded strings touched by the work are localized when practical.
- Custom styling is adjusted where it conflicts with native macOS behavior.
- Build/tests have been attempted and results are reported.

## Worker 1 Progress

Status: implemented shared app shell/common UI fixes.

- Replaced custom root sidebar selection colors with native `List`/`NavigationLink` sidebar behavior and flexible sidebar column width.
- Reduced root window minimum size pressure and changed window resizability to content minimum sizing.
- Swapped the detail shell background from custom HUD/gradient treatment to window background material.
- Tuned shared cards/buttons/sections toward quieter system colors, semantic typography, standard control heights, and less shadow.
- Added accessible labels/help for shared copy/save controls, warning indicators, app icon/menu bar label, and sidebar branding.
- Updated menu bar labels to clearer macOS command names with ellipses where commands open additional UI.

Verification:

- `xcrun swiftc -parse` over Worker 1 Swift files passed.
- Full `xcodebuild -scheme VoiceInk -destination 'platform=macOS' build` was deferred while parallel workers already had build processes running; `xcodebuild -list` also emitted a CoreSimulator version warning and did not complete promptly.
