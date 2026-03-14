# Running Unsigned Releases

VoiceLink Community releases are currently distributed without Apple code signing and notarization.

The prebuilt GitHub DMGs are also Apple Silicon-only (`arm64`) release artifacts.

As of March 10, 2026, the Apple Developer Program costs [99 USD per year](https://developer.apple.com/programs/whats-included/). This project is an open-source accessibility effort maintained independently by a disabled developer, so that recurring cost is currently not being absorbed just to clear Gatekeeper warnings for GitHub releases.

## What to Expect

When you download the app from GitHub Releases, macOS may block it on first launch with a message that Apple cannot verify it.

This does **not** mean the app is known malware. It means the app was not signed and notarized through Apple's paid developer pipeline.

If you are on an Intel Mac, use the source build flow instead of the attached DMG.

## How to Open the App

Use the standard macOS override flow:

1. Download the release from the project's GitHub Releases page.
2. Move the app to `/Applications` if you want it installed system-wide.
3. Double-click the app once and let macOS show the warning.
4. Open `System Settings`.
5. Go to `Privacy & Security`.
6. Scroll down until you see the blocked app message.
7. Click `Open Anyway`.
8. Confirm `Open` in the follow-up prompt.

You can also use Finder:

1. Control-click the app.
2. Choose `Open`.
3. Confirm `Open`.

## Safety Notes

- Only bypass Gatekeeper for builds downloaded from this repository.
- If a checksum or release hash is published, verify it before opening the app.
- If you need Intel support or are unsure, build the app yourself from source instead.

## Build Instead

If you would rather avoid running a prebuilt unsigned release, use the local build flow in [Building from Source](development/BUILDING.md).

## Apple References

- [Apple Developer Program pricing](https://developer.apple.com/programs/whats-included/)
- [Open apps safely on your Mac](https://support.apple.com/en-gb/HT202491)
