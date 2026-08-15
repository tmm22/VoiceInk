# CloudSync Feature Documentation

## Overview
CloudSync allows users to synchronize their AI Enhancement Profiles (Custom Prompts) across multiple Mac devices using their iCloud account. This feature functions without a dedicated user account, leveraging Apple's native iCloud Key-Value Store (`NSUbiquitousKeyValueStore`).

## Features
- **Opt-in Sync**: Users must enable "Sync with iCloud" in Enhancement Settings.
- **Automatic Sync**: Changes to custom prompts (additions, edits, deletions) are automatically pushed to iCloud when enabled.
- **Real-time Updates**: Other devices signed into the same iCloud account receive updates in real-time (latency depends on iCloud).
- **No Login Required**: Works out-of-the-box for any user signed into their Mac with an Apple ID.

## Architecture
- **CloudSyncService**: A singleton service (`CloudSyncService.shared`) that manages the interaction with `NSUbiquitousKeyValueStore`.
- **Integration**: The service is integrated into `AIEnhancementService`, which holds the source of truth for custom prompts.
- **Entitlement**: Uses the `com.apple.developer.ubiquity-kvstore-identifier` entitlement.

## Troubleshooting
- **Not Syncing?**:
    - Ensure the device is signed into iCloud.
    - Check "iCloud Drive" properties in System Settings.
    - Verify the app has the "iCloud" entitlement enabled in Xcode.
- **Latency**: iCloud KVS sync is generally fast but not instant. It may throttle frequent updates.

## Technical Details
- **Storage Key**: `cloud_sync_custom_prompts`
- **Data Format**: JSON-encoded array of `CustomPrompt` objects.
- **Conflict Resolution**: Currently last-writer-wins. The `AIEnhancementService` updates its local state whenever a remote change notification is received.
