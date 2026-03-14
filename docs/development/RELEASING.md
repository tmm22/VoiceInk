# Releasing on GitHub

GitHub does not currently support a repository file that automatically pre-fills the body of manual releases in the web UI.

For this repository, the release body source of truth is:

- [`.github/RELEASE_TEMPLATE.md`](../../.github/RELEASE_TEMPLATE.md)

## Recommended Maintainer Flow

1. Draft a new GitHub release.
2. Open [`.github/RELEASE_TEMPLATE.md`](../../.github/RELEASE_TEMPLATE.md).
3. Copy that template into the release description.
4. Replace the placeholder summary under `Highlights`.
5. Attach the app asset.
6. Optionally click `Generate release notes` and append the generated changelog under `Full Changelog`.
7. Publish the release.

## Local Release Automation

The repository currently lives under Desktop in some local setups, which can cause `xcodebuild` to stall inside macOS file coordination before it even starts compiling. To avoid that, release builds should be staged into a temporary non-synced path first.

Public GitHub/community releases in this repository are intentionally unsigned. That is a maintainer/project constraint, not an accidental omission: this project does not assume an Apple Developer subscription or paid signing/notarization workflow.

Available scripts:

- `./scripts/build-release-artifact.sh`
  - Creates a temporary staging copy outside Desktop/iCloud-backed locations
  - Builds the app with the unsigned local-build configuration by default
  - Uses the Xcode `Release` configuration so debug dylibs are not shipped in the DMG
  - Enables Release stripping, dead-code stripping, and `-Osize` so manual and scripted release builds stay aligned on bundle-size optimization
  - Strips non-global symbols in the packaged app to reduce DMG size without changing behavior
  - For unsigned artifacts, thins universal embedded binaries to `arm64` and re-signs the app bundle ad hoc
  - This means public unsigned GitHub DMGs are Apple Silicon-only by policy
  - Produces `release-artifacts/vX.YY-community/VoiceInk.dmg`
  - Produces `release-artifacts/vX.YY-community/VoiceInk.dmg.sha256`
- `./scripts/generate-release-notes.sh`
  - Reads the latest top entry from `CHANGELOG.md`
  - Merges those project release notes with the GitHub/Gatekeeper instructions from `.github/RELEASE_TEMPLATE.md`
  - Produces `release-artifacts/vX.YY-community/release-notes.md`
- `./scripts/publish-github-release.sh`
  - Requires a clean git worktree and authenticated GitHub CLI
  - Builds the DMG through the staging workflow above
  - Refuses non-`unsigned` signing mode for GitHub publishing so the public release path cannot drift away from the documented size-optimized artifact policy
  - Generates the final release body from both `CHANGELOG.md` and `.github/RELEASE_TEMPLATE.md`
  - Pushes `custom-main-v2`, tags `vX.YY-community`, and creates the GitHub release on `tmm22/VoiceInk`

## Release Build Contract

For public GitHub/community releases, the artifact policy is:

- Build from Xcode `Release`
- Stage outside Desktop/iCloud-backed paths
- Preserve these size-focused build settings:
  - `DEPLOYMENT_POSTPROCESSING=YES`
  - `STRIP_INSTALLED_PRODUCT=YES`
  - `COPY_PHASE_STRIP=YES`
  - `DEAD_CODE_STRIPPING=YES`
  - `STRIPFLAGS=-x`
  - `SWIFT_OPTIMIZATION_LEVEL=-Osize`
- For unsigned artifacts, prune bundled ESpeakNG dictionary data to the English-only Pocket TTS subset used by the current shipped voices
- For unsigned artifacts, thin universal embedded binaries to `arm64`
- Publish via `./scripts/publish-github-release.sh`, not by manually uploading a hand-built app or DMG

If this contract changes, update the release scripts, `AGENTS.md`, `docs/development/BUILDING.md`, and `.github/RELEASE_TEMPLATE.md` together.

If you only want the binary artifact, run:

```bash
make release-artifact
```

## Preserving macOS Permissions During Local Testing

If you want Accessibility, Microphone, and Screen Recording permissions to survive across your own local test releases, install the app over the same path and use a stable signing identity.

For this repository, that means:

- Public GitHub release artifacts remain `unsigned` by default.
- Public GitHub release artifacts are Apple Silicon-only by default.
- Local maintainer test builds can opt into project signing with:

```bash
VOICEINK_RELEASE_SIGNING_MODE=project ./scripts/build-release-artifact.sh
```

That mode uses the Xcode project's normal signing configuration instead of `LocalBuild.xcconfig`. On a machine that has working project signing, macOS is much more likely to treat successive builds as the same app for TCC purposes.

Important limits:

- This does not change the public GitHub release flow, which still uses unsigned local-build artifacts.
- This does not change the public GitHub release flow, which still publishes Apple Silicon-only DMGs.
- This local project-signed mode is only for maintainer testing on machines that already have working signing configured; it is not the project default and must not replace the unsigned public release strategy without an explicit policy change.
- Permissions are managed by macOS TCC, not by app code, so persistence depends on:
  - stable bundle identifier
  - stable signing identity
  - replacing the app in the same installed location (for example `/Applications/VoiceInk.app`)
- If you intentionally run `reset_permissions.sh`, macOS will forget those permissions by design.

## Why the Template Includes Gatekeeper Notes

VoiceLink Community releases are currently unsigned and not notarized. The template keeps the Gatekeeper workaround visible in every release so users do not have to hunt through the README before opening the app.

It also explains the reason plainly: as of March 10, 2026, the Apple Developer Program costs 99 USD per year, and this project is an open-source accessibility effort maintained independently by a disabled developer.

The template should also clearly state that attached unsigned DMGs are Apple Silicon-only and that Intel users should build from source instead.
