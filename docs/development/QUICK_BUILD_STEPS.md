# Quick Build Steps - 2 Minutes ⏱️

## In Xcode (Already Open):

### Step 1: Enable Automatic Signing (30 seconds)
1. Click **"VoiceInk"** project in left sidebar (blue icon at top)
2. Select **"VoiceInk"** target in center panel
3. Click **"Signing & Capabilities"** tab at top
4. ✅ Check **"Automatically manage signing"**
5. Select your **Team** from dropdown (your Apple ID)

### Step 2: Build & Run (30 seconds)
1. Press **Cmd+R** (or click ▶️ Play button)
2. Wait for build (~1 minute)
3. App launches automatically!

---

## That's It! ✅

The app will:
- ✅ Launch with fresh permissions (we already reset them)
- ✅ Prompt for Microphone, Accessibility, Screen Recording
- ✅ Be ready to test all the fixes

---

## If Build Fails:

**Error: "No Account"**
- Xcode → Settings → Accounts
- Click **+** → Add Apple ID
- Sign in
- Try building again

**Error: "Signing Failed"**
- Select VoiceInk target
- Signing & Capabilities
- Change Team to your Apple ID
- Try again

---

## Testing Checklist:

Once app launches:

### 1. Grant Permissions ✅
- Allow Microphone
- Allow Accessibility  
- Allow Screen Recording

### 2. Basic Functionality ✅
- Try recording something
- Check transcription works
- Try pasting in different apps

### 3. API Key Security ✅
If you have API keys:
- Add one in Settings
- Quit and relaunch
- Key should persist
- Check Keychain Access.app - should see it there

### 4. Migration Test ✅
If you had old keys:
- They should still work
- Check Console.app for migration logs
- Search for "APIKeyMigration"

---

**Ready in 2 minutes!** 🚀
