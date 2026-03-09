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

Available scripts:

- `./scripts/build-release-artifact.sh`
  - Creates a temporary staging copy outside Desktop/iCloud-backed locations
  - Builds the app with the unsigned local-build configuration
  - Produces `release-artifacts/vX.YY-community/VoiceInk.dmg`
  - Produces `release-artifacts/vX.YY-community/VoiceInk.dmg.sha256`
- `./scripts/generate-release-notes.sh`
  - Reads the latest top entry from `CHANGELOG.md`
  - Merges those project release notes with the GitHub/Gatekeeper instructions from `.github/RELEASE_TEMPLATE.md`
  - Produces `release-artifacts/vX.YY-community/release-notes.md`
- `./scripts/publish-github-release.sh`
  - Requires a clean git worktree and authenticated GitHub CLI
  - Builds the DMG through the staging workflow above
  - Generates the final release body from both `CHANGELOG.md` and `.github/RELEASE_TEMPLATE.md`
  - Pushes `custom-main-v2`, tags `vX.YY-community`, and creates the GitHub release on `tmm22/VoiceInk`

If you only want the binary artifact, run:

```bash
make release-artifact
```

## Why the Template Includes Gatekeeper Notes

VoiceLink Community releases are currently unsigned and not notarized. The template keeps the Gatekeeper workaround visible in every release so users do not have to hunt through the README before opening the app.

It also explains the reason plainly: as of March 10, 2026, the Apple Developer Program costs 99 USD per year, and this project is an open-source accessibility effort maintained independently by a disabled developer.
