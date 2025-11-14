# Build and Test Guide

## Building Release Version

### Option 1: Build in Xcode (Recommended)

1. **Open the project:**
   ```bash
   open VoiceInk.xcodeproj
   ```

2. **Select Release scheme:**
   - Click the scheme dropdown (next to Play button)
   - Select "VoiceInk" scheme
   - Hold Option key and click the scheme
   - Change "Build Configuration" to "Release"

3. **Configure Signing:**
   - Select "VoiceInk" project in sidebar
   - Select "VoiceInk" target
   - Go to "Signing & Capabilities" tab
   - Enable "Automatically manage signing"
   - Select your Team

4. **Build:**
   - Press Cmd+B to build
   - Or Product → Build

5. **Run:**
   - Press Cmd+R to run
   - Or click Play button

### Option 2: Archive for Distribution

1. **Archive:**
   - Product → Archive
   - Wait for build to complete

2. **Export:**
   - Click "Distribute App"
   - Choose "Direct Distribution"
   - Click "Export"
   - Save to Desktop

3. **Install:**
   - Drag exported app to Applications folder
   - Right-click → Open (first time only)

---

## Resetting macOS Permissions

VoiceInk requires several permissions. Here's how to reset them all:

### Quick Reset (All Permissions)

Run this command:

```bash
tccutil reset All com.tmm22.VoiceLinkCommunity
```

Then quit and relaunch VoiceInk - it will prompt for permissions again.

---

### Reset Individual Permissions

**1. Microphone Access:**
```bash
tccutil reset Microphone com.tmm22.VoiceLinkCommunity
```

**2. Accessibility Access:**
```bash
tccutil reset Accessibility com.tmm22.VoiceLinkCommunity
```

**3. Screen Recording:**
```bash
tccutil reset ScreenCapture com.tmm22.VoiceLinkCommunity
```

**4. Calendar Access (if used):**
```bash
tccutil reset Calendar com.tmm22.VoiceLinkCommunity
```

**5. Contacts Access (if used):**
```bash
tccutil reset AddressBook com.tmm22.VoiceLinkCommunity
```

---

### Manual Permission Reset (System Settings)

1. **Open System Settings:**
   - Click Apple menu → System Settings

2. **Privacy & Security:**
   - Click "Privacy & Security" in sidebar

3. **Reset Each Permission:**
   
   **Microphone:**
   - Click "Microphone"
   - Find "VoiceInk" or "VoiceLinkCommunity"
   - Toggle OFF, then ON
   
   **Accessibility:**
   - Click "Accessibility"
   - Find "VoiceInk" and remove it
   - Relaunch app to re-grant
   
   **Screen Recording:**
   - Click "Screen Recording"
   - Find "VoiceInk" and toggle OFF
   - Relaunch app to re-grant

---

## Testing the Fixes

### What to Test

**1. Crash Fixes (Tier 1):**

✅ **WhisperState Fix:**
- Launch app without any models downloaded
- Try to transcribe
- Should show error, NOT crash

✅ **PasteEligibilityService Fix:**
- Record something
- Try to paste in Terminal
- Try to paste in TextEdit
- Should work in both, no crashes

✅ **AudioFileTranscriptionManager Fix:**
- Drag an audio file to VoiceInk
- Try to transcribe it
- Should handle missing services gracefully

✅ **PolarService Fix:**
- Check license validation
- Should handle errors gracefully

**2. Security Fixes (Tier 2):**

✅ **API Key Migration:**
- If you have existing API keys in the app
- They should continue working after update
- Check Keychain Access.app to verify they're in Keychain:
  - Open Keychain Access.app
  - Search for "GROQ" or "OpenAI"
  - Should see entries for VoiceLinkCommunity

✅ **Keychain Storage:**
- Add a new API key in Settings
- Quit and relaunch app
- Key should persist
- Check it's NOT in UserDefaults:
  ```bash
  defaults read com.tmm22.VoiceLinkCommunity | grep -i "APIKey"
  ```
  Should return nothing

**3. Backward Compatibility:**

✅ **Fallback Logic:**
- If migration hasn't completed, services should still work
- No "Invalid API Key" errors on first launch

---

## Verifying Migration

**Check if migration ran:**
```bash
defaults read com.tmm22.VoiceLinkCommunity | grep -i "api"
```

**Expected:**
- Old keys: Should be GONE from UserDefaults
- New location: Keychain (check Keychain Access.app)

**If keys are still in UserDefaults:**
- That's OK - fallback will use them
- Migration will complete on subsequent launches
- Keys will be removed progressively

---

## Clean Install Testing

To test a completely fresh install:

1. **Remove app:**
   ```bash
   rm -rf /Applications/VoiceInk.app
   ```

2. **Clear preferences:**
   ```bash
   defaults delete com.tmm22.VoiceLinkCommunity
   ```

3. **Clear Keychain entries:**
   - Open Keychain Access.app
   - Search "VoiceLinkCommunity"
   - Delete all entries

4. **Reset permissions:**
   ```bash
   tccutil reset All com.tmm22.VoiceLinkCommunity
   ```

5. **Install and test:**
   - Build new version
   - Grant permissions
   - Add API keys
   - Test transcription

---

## Expected Behavior

### First Launch (Clean Install):
1. ✅ Prompts for permissions
2. ✅ No API keys exist
3. ✅ Add keys through Settings
4. ✅ Keys saved directly to Keychain
5. ✅ No migration needed

### First Launch (Upgrade from Old Version):
1. ✅ App launches normally
2. ✅ Migration attempts in background
3. ✅ Services work immediately (fallback to UserDefaults)
4. ✅ Keys move to Keychain progressively
5. ✅ Eventually all keys in Keychain only

### Subsequent Launches:
1. ✅ Migration checks status
2. ✅ Skips already-migrated keys
3. ✅ Retries any failed migrations
4. ✅ Services use Keychain
5. ✅ Fallback available if needed

---

## Troubleshooting

### "Build Failed" in Xcode

**Problem:** Code signing issues

**Solution:**
1. Select VoiceInk target
2. Signing & Capabilities tab
3. Enable "Automatically manage signing"
4. Select your Apple Developer Team
5. Clean Build Folder (Cmd+Shift+K)
6. Build again (Cmd+B)

### App Won't Launch

**Problem:** Quarantine flag

**Solution:**
```bash
xattr -cr /Applications/VoiceInk.app
```

### Permissions Not Working

**Problem:** Permission cache

**Solution:**
```bash
tccutil reset All com.tmm22.VoiceLinkCommunity
killall Finder
```

Then relaunch app.

### Migration Not Running

**Problem:** Check logs

**Solution:**
```bash
log stream --predicate 'subsystem == "com.tmm22.voicelinkcommunity" AND category == "APIKeyMigration"' --level debug
```

Then launch app and watch for migration logs.

---

## Build Artifacts Location

**After building in Xcode:**
```
~/Library/Developer/Xcode/DerivedData/VoiceInk-*/Build/Products/Release/VoiceInk.app
```

**After command line build:**
```
build/Build/Products/Release/VoiceInk.app
```

---

## Quick Commands

**Reset everything and start fresh:**
```bash
# Reset permissions
tccutil reset All com.tmm22.VoiceLinkCommunity

# Clear preferences
defaults delete com.tmm22.VoiceLinkCommunity

# Remove app
rm -rf /Applications/VoiceInk.app

# Rebuild
open VoiceInk.xcodeproj
# Then build in Xcode
```

---

**Ready to test!** 🚀
