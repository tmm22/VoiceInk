# Fork Differentiation Opportunities

## Current Fork Differences (Curated Highlights)

Comparison baseline: `upstream/main` at `6ab3705` vs `custom-main-v2` at `f138c96`.

- **Community edition unlock and rebrand**: Removes paywall/trial gating, rebrands UI copy/storage to VoiceLink Community.  
  **References**: `README.md`, `VoiceInk/Views/LicenseManagementView.swift`
- **Local-first model bundling and expansion**: Bundled Whisper/Parakeet plus FastConformer and SenseVoice integrations.  
  **References**: `docs/LOCAL_TRANSCRIPTION_UPDATES.md`, `VoiceInk/Whisper/WhisperState.swift`
- **Text-to-Speech Workspace**: Full TTS studio with batch queue, translation, export, and inspector tooling.  
  **References**: `VoiceInk/TTS`, `docs/TTS_WORKSPACE_GUIDE.md`
- **Dictionary + Quick Rules**: Predictable offline cleanup with word replacements and custom vocabulary.  
  **References**: `QUICK_RULES_USER_GUIDE.md`, `docs/DICTIONARY_GUIDE.md`
- **Audio feedback customization**: Theme-based and custom sound controls for recording feedback.  
  **References**: `docs/AUDIO_FEEDBACK_CUSTOMIZATION.md`
- **AI enhancement modernization**: Provider expansion (ZAI, Gemini 3, GPT‑5.2), reasoning effort control, and richer context.  
  **References**: `docs/AI_ENHANCEMENT_GUIDE.md`, `docs/ZAI_INTEGRATION_GUIDE.md`
- **Data lifecycle controls**: Trash system plus transcript/audio retention cleanup.  
  **References**: `docs/DATA_MANAGEMENT_GUIDE.md`, `VoiceInk/Services/TrashCleanupService.swift`
- **Settings + UI redesign**: Unified settings layout, search, and responsive layout polish.  
  **References**: `VoiceInk/Views/Settings`, `UI_CONSISTENCY_AUDIT_PLAN.md`
- **Expanded documentation set**: Feature guides and build/operational docs added for fork workflows.  
  **References**: `docs/README.md`, `BUILDING.md`

## Current Fork Differences (Exhaustive Inventory)

Comparison baseline: `upstream/main` at `6ab3705` vs `custom-main-v2` at `f138c96`.

- **Community edition unlock and rebrand**: Community license UI, app copy updates, and storage identifiers reflect VoiceLink Community.  
  **References**: `README.md`, `VoiceInk/Views/LicenseManagementView.swift`, `VoiceInk/VoiceInk.swift`
- **Local transcription expansion**: FastConformer provider, SenseVoice integration, and Parakeet model workflows.  
  **References**: `docs/LOCAL_TRANSCRIPTION_UPDATES.md`, `VoiceInk/Whisper/WhisperState+FastConformer.swift`, `VoiceInk/Whisper/WhisperState+SenseVoice.swift`, `VoiceInk/Whisper/WhisperState+Parakeet.swift`
- **Text-to-Speech Workspace**: TTS studio with batch generation, voice preview, translation, URL import, and export.  
  **References**: `VoiceInk/TTS`, `docs/TTS_WORKSPACE_GUIDE.md`
- **TTS inspector and settings**: Dedicated inspector panels, style controls, export settings, and provider cost notes.  
  **References**: `VoiceInk/TTS/Views/TTSInspectorView.swift`, `VoiceInk/TTS/Views/TTSSettingsView.swift`
- **TTS security and audits**: Provider security hardening and audits specific to TTS workflows.  
  **References**: `TTS_SECURITY_AUDIT.md`
- **Dictionary + Quick Rules**: Quick Rules automation, word replacements, and custom vocabulary tools.  
  **References**: `QUICK_RULES_USER_GUIDE.md`, `docs/DICTIONARY_GUIDE.md`, `VoiceInk/Views/Dictionary`
- **Audio feedback customization**: Multi-theme sounds and custom audio file imports.  
  **References**: `docs/AUDIO_FEEDBACK_CUSTOMIZATION.md`, `VoiceInk/SoundManager.swift`
- **Keyboard shortcuts and cheat sheet**: Shortcut reference UI plus expanded shortcut options.  
  **References**: `VoiceInk/Views/KeyboardShortcutCheatSheet.swift`, `docs/KEYBOARD_SHORTCUTS_GUIDE.md`
- **Recorder UX upgrades**: Duration indicator, visible cancel button, and richer status feedback.  
  **References**: `QOL_IMPROVEMENTS_CHANGELOG.md`, `VoiceInk/Views/Recorder`
- **Settings redesign**: Unified settings layout, sidebar navigation, and searchable sections.  
  **References**: `VoiceInk/Views/Settings`, `UI_CONSISTENCY_AUDIT_PLAN.md`
- **Power Mode enhancements**: Power Mode settings panel, auto-restore option, and shortcuts.  
  **References**: `docs/POWER_MODE_GUIDE.md`, `VoiceInk/Views/Settings/PowerModeSettingsSection.swift`
- **AI enhancement modernization**: Provider list expansion, reasoning effort tuning, and enriched prompt context.  
  **References**: `docs/AI_ENHANCEMENT_GUIDE.md`, `VoiceInk/Services/AIEnhancement/AIService.swift`
- **Z.AI integration**: Z.AI transcription and enhancement provider wiring.  
  **References**: `docs/ZAI_INTEGRATION_GUIDE.md`, `VoiceInk/Services/CloudTranscription/ZAITranscriptionService.swift`
- **Data lifecycle controls**: Trash system, retention cleanup, and manual purge flows.  
  **References**: `docs/DATA_MANAGEMENT_GUIDE.md`, `VoiceInk/Services/TrashCleanupService.swift`, `VoiceInk/Views/TrashView.swift`
- **Export tooling**: CSV/JSON/TXT export for transcription history and TTS transcript exports.  
  **References**: `VoiceInk/Services/TranscriptionExportService.swift`, `VoiceInk/TTS/Views/TTSWorkspaceView+CommandStrip.swift`
- **API key migration**: One-time migration from UserDefaults to Keychain.  
  **References**: `VoiceInk/Services/APIKeyMigrationService.swift`
- **Security and performance remediations**: HTTPS validation, async audio file loading, and main-thread cleanup.  
  **References**: `VOICELINK_COMMUNITY_REMEDIATIONS.md`
- **Testing framework expansion**: Fork-specific testing infrastructure and stress suites.  
  **References**: `TESTING_FRAMEWORK_COMPLETE.md`, `TESTING_ACHIEVEMENT_SUMMARY.md`
- **Build and release documentation**: Build guides, quick start steps, and submission docs.  
  **References**: `BUILDING.md`, `BUILD_AND_TEST_GUIDE.md`, `READY_TO_SUBMIT.md`
- **UI responsiveness and scaling**: Responsive layouts, breakpoint system, and TTS workspace sizing fixes.  
  **References**: `DYNAMIC_SCALING_SUMMARY.md`, `UI_CONSISTENCY_AUDIT_PLAN.md`

## Platform Reach & Accessibility
- **Current VoiceInk**: macOS-only app that depends on AppKit/SwiftUI infrastructure and officially targets macOS 14+.  
- **Fork Angle**: Deliver a cross-platform or broader Apple ecosystem build (older macOS, Catalyst/iPad, iPhone companion, or a Swift/Flutter reimplementation for Windows/Linux) with shared preferences and model storage.  
- **Why It Differentiates**: Expands the addressable market (enterprise fleets stuck on older OS versions, teams that float between desktop and mobile) and unlocks multi-device workflows competitors neglect.  
- **References**: `README.md:59`, `VoiceInk/VoiceInk.swift:4`

## Community & Licensing Philosophy
- **Current VoiceInk**: Ships with a gated “VoiceInk Pro” experience and paywall UI, and contributions are tightly stewarded by maintainers.  
- **Fork Angle**: Reposition as a community-driven distribution—fully free tier, community plugin marketplace, transparent governance, and looser contribution policy.  
- **Why It Differentiates**: Appeals to open-source purists and organizations wary of licensing toggles, while inviting broader contributor energy. **Status: Shipped in VoiceLink Community.**
- **References**: `VoiceInk/Views/ContentView.swift:17`, `VoiceInk/Views/LicenseManagementView.swift:16`, `CONTRIBUTING.md:9`

## Live Overlay & Accessibility Workflows
- **Current VoiceInk**: UX revolves around discrete dashboard/history/settings panes; no persistent, on-screen captioning surface is exposed.  
- **Fork Angle**: Build an always-on caption HUD, configurable teleprompter, or floating transcript timeline with accessibility presets (font, contrast, multi-language subtitles).  
- **Why It Differentiates**: Targets streamers, hard-of-hearing users, and presenters who need live captions without switching apps.  
- **References**: `VoiceInk/Views/ContentView.swift:6`

## Shared Workspaces & Sync
- **Current VoiceInk**: Stores transcripts via SwiftData in the user’s Application Support folder with no sync logic.  
- **Fork Angle**: Introduce optional encrypted cloud sync, team workspaces, and automated backups (iCloud, Nextcloud, Supabase, or self-hosted backends).  
- **Why It Differentiates**: Aligns with team note-taking needs, offers compliance-friendly audit logs, and provides resilience for power users juggling multiple Macs. **Status: Planned.**
- **References**: `VoiceInk/VoiceInk.swift:40`

## Meeting & Conversation Intelligence
- **Current VoiceInk**: Records a single audio channel with a lightweight VAD pipeline; there is no diarization or structured meeting summary stack.  
- **Fork Angle**: Layer in multi-channel capture, speaker diarization, calendar-aware meeting detection, and automated action-item drafting.  
- **Why It Differentiates**: Creates a turnkey alternative to SaaS meeting assistants while keeping processing local or self-hosted.  
- **References**: `VoiceInk/Recorder.swift:92`

## Automation & Extensibility
- **Current VoiceInk**: Automation hinges on global hotkeys and middle-click toggles; no plugin, CLI, or API surface exists.  
- **Fork Angle**: Ship a scriptable engine (Apple Shortcuts, command-line client, HTTP/WebSocket API) and lightweight plugin SDK so users can wire custom post-processing or exports.  
- **Why It Differentiates**: Gives developers and ops teams tooling parity with SaaS transcription services and encourages third-party ecosystem growth. **Status: In progress.**
- **References**: `VoiceInk/HotkeyManager.swift:76`

## Model Onboarding & Ops
- **Current VoiceInk**: Users must juggle API keys and external model choices; only Ollama offers a turnkey local story.  
- **Fork Angle**: Provide curated, auto-updating on-device model bundles, streaming while-downloading, and policy presets (privacy tiers, cost controls) plus self-hosted inference adapters.  
- **Why It Differentiates**: Reduces setup friction, attracts privacy-conscious teams, and positions the fork as the quickest path to productive transcription. **Status: Shipped in VoiceLink Community.**
- **References**: `VoiceInk/Services/AIService.swift:149`
