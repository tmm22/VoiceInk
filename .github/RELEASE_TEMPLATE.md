# VoiceLink Community Release Template

## Highlights

- Summarize the main changes in this release.

## Downloads

- Download the app asset attached to this release.
- The attached unsigned DMG is Apple Silicon-only (`arm64`).
- The attached DMG is built from the repository's automated `Release` packaging flow with stripping and arm64-thinning to keep downloads smaller without removing app functionality.
- Verify `VoiceInk.dmg.sha256` if you want to confirm the downloaded DMG matches the published checksum.
- If you need an Intel build or would rather build it yourself, see `docs/development/BUILDING.md` in the repository.

## Running This Release on macOS

This release is currently distributed without Apple code signing and notarization.

It is also packaged as an Apple Silicon-only community artifact to keep the GitHub DMG smaller without removing functionality from the shipped app.

As of March 10, 2026, the Apple Developer Program costs [99 USD per year](https://developer.apple.com/programs/whats-included/). This project is an open-source accessibility effort maintained independently by a disabled developer, so that recurring cost is currently not being absorbed just to clear Gatekeeper warnings for GitHub releases.

If macOS blocks the app on first launch:

1. Download the app from this GitHub release.
2. Move it to `/Applications` if you want to keep it installed there.
3. Open it once and dismiss the warning.
4. Open `System Settings > Privacy & Security`.
5. Scroll to the security section and click `Open Anyway`.
6. Confirm the prompt to open the app.

You can also Control-click the app in Finder, choose `Open`, then confirm `Open`.

Only bypass Gatekeeper for builds downloaded from this repository. If you need Intel support or are unsure, build the app from source instead.

Full guide: `docs/RUNNING_UNSIGNED_RELEASES.md`

## Full Changelog

- Add release-specific notes here, or paste generated release notes below this heading.
- If you are using the automation scripts, this section is filled from `CHANGELOG.md` automatically.
