# Feature: CloudSync for AI Enhancement Profiles

## Overview
This PR introduces **CloudSync**, a feature allowing users to synchronize their custom AI enhancement prompts across multiple devices using their iCloud account. This implementation uses `NSUbiquitousKeyValueStore`, requiring no separate user account or login.

## Changes
- **CloudSyncService**: A new singleton service handling iCloud KVS synchronization.
- **AIEnhancementService**: Integrated with `CloudSyncService` to sync custom prompts.
- **Settings UI**:
    - Added a new **Enhancement** settings tab (formerly accessible via AI settings).
    - Added a **"Sync with iCloud"** toggle for opt-in synchronization.
- **Documentation**:
    - Created `CLOUDSYNC_DOCUMENTATION.md`.
    - Updated `AGENTS.md` and `DESIGN_DOCUMENT.md`.

## User Facing Changes
- **New Settings Tab**: "Enhancement" tab in the Settings window.
- **Sync Toggle**: Users can now choose to sync their prompts via iCloud.

## Verification
- **Manual Verification**:
    1.  Enabled "Sync with iCloud" in Settings -> Enhancement.
    2.  Created a custom prompt.
    3.  Verified sync (simulated) and loop prevention logic.
- **Build**: Successfully built with `xcodebuild`.

## Notes
- This feature is **Opt-in**: Sync is disabled by default to respect user privacy and preference.
- Requires `com.apple.developer.ubiquity-kvstore-identifier` entitlement.
