# Quick Start: Running VoiceInk Tests

Document role:
- Fast-start checklist for a short first test pass.
- Keep this concise and action-oriented.

Update this file when:
- The shortest recommended test entry flow changes.
- Key shortcuts or first-pass expectations change.

For deep execution/troubleshooting details, use `BUILD_AND_TEST_GUIDE.md` and `NEXT_STEPS_TESTING.md`.

**⚡ 5-Minute Guide to Execute 249 Tests**

---

## Step 1: Open Project (30 seconds)

```bash
open VoiceInk.xcodeproj
```

Wait for Xcode to load and index the project.

---

## Step 2: Run Basic Tests (2 minutes)

In Xcode:
1. Click on the **VoiceInk** scheme dropdown (top left)
2. Confirm "VoiceInk" is selected
3. Press **⌘U** (or Product → Test)
4. Watch the tests run in real-time

**What you'll see:**
- Test navigator (⌘6) shows tests executing
- Green ✅ = passing tests
- Red ❌ = failing tests
- Yellow ⊘ = skipped tests (normal if models unavailable)

**Expected:** Most tests should pass, some may skip gracefully.

---

## Step 3: Check Results (1 minute)

Press **⌘6** to open Test Navigator and see:

```
✅ VoiceInkTests (187 tests)
  ✅ AudioSystem/
    ✅ RecorderTests (17 tests)
    ✅ AudioDeviceManagerTests (21 tests)
    ✅ AudioLevelMonitorTests (21 tests) ← Watch this one!
  ✅ Transcription/
    ✅ WhisperStateTests (26 tests)
  ✅ TTS/
    ✅ TTSViewModelTests (39 tests) ← Watch this one!
  ✅ Services/ (63 tests)
  ✅ Integration/ (17 tests)
  ✅ Stress/ (28 tests) ← Important!

✅ VoiceInkUITests (17 tests)
```

**Look for crashes:** "Test session crashed" = bug found! 🎯

---

## Step 4: Run Thread Sanitizer (CRITICAL) (10 minutes)

This finds race conditions like the AudioLevelMonitor deinit bug!

1. Click "VoiceInk" scheme dropdown → Edit Scheme
2. Select **Test** in left sidebar
3. Click **Diagnostics** tab
4. Check ✅ **Thread Sanitizer**
5. Click Close
6. Press **⌘U** again

**What to look for:**
```
WARNING: ThreadSanitizer: data race
  Write of size X at 0x...
  Previous read at 0x...
```

This means: **RACE CONDITION FOUND!** 🚨

---

## Step 5: Run Address Sanitizer (10 minutes)

This finds memory corruption and use-after-free bugs!

1. Edit Scheme → Test → Diagnostics
2. **Uncheck** Thread Sanitizer (only one at a time)
3. Check ✅ **Address Sanitizer**
4. Click Close
5. Press **⌘U**

**What to look for:**
```
AddressSanitizer: heap-use-after-free
AddressSanitizer: heap-buffer-overflow
```

This means: **MEMORY BUG FOUND!** 🚨

---

## Step 6: Document Findings (5 minutes)

Open `CRASH_FIXES.md` and fill in:

- Test pass rate (e.g., 235/249 passed)
- Number of races found by Thread Sanitizer
- Number of memory issues found by Address Sanitizer
- Specific failing tests
- Any crash logs

---

## 🎯 Most Important Tests

These target known high-risk areas:

### 1. AudioLevelMonitorTests ⭐⭐⭐
```
testNonisolatedDeinitWithTaskExecution
testDeinitRaceCondition (20 rapid cycles)
```
**Why:** Tests THE critical nonisolated deinit race condition

### 2. ConcurrencyStressTests ⭐⭐⭐
```
testAudioLevelMonitorConcurrentStartStop
testRecorderMassiveConcurrentStops (1000 ops)
```
**Why:** Exposes race conditions under extreme load

### 3. MemoryStressTests ⭐⭐⭐
```
testAudioLevelMonitorExtremeCycles (100 cycles)
testRecorderHundredSessions
```
**Why:** Exposes memory leaks

### 4. TTSViewModelTests ⭐⭐
```
testDeinitCancelsAllTasks
testRapidAllocDealloc
```
**Why:** Tests 5 tasks cancelled in deinit

---

## 🐛 Expected Issues

Based on code analysis, expect to find:

1. **AudioLevelMonitor deinit race** ← Very likely
2. **AudioDeviceManager.isReconfiguring race** ← Likely
3. **WhisperState.shouldCancelRecording race** ← Possible
4. **Memory leaks in timer cleanup** ← Possible
5. **Observer retention** ← Possible

---

## ✅ Success Looks Like

```
Basic Tests:     235/249 passed (94%)
Thread Sanitizer: 3 races found (documented)
Address Sanitizer: 0 issues found ✅
Memory Leaks:    0 found ✅
Crashes:         0 unhandled ✅
```

---

## 🆘 Troubleshooting

**"Signing certificate not found"**
→ Product → Scheme → Edit Scheme → Signing → Disable automatic signing

**"Test session crashed immediately"**
→ 🎉 You found a crash! Document which test caused it

**"No tests available"**
→ Make sure VoiceInk scheme is selected (not VoiceInkTests)

**"Tests take forever"**
→ Normal with sanitizers (3-5x slower). Be patient!

**"Many tests skipped"**
→ Normal if Whisper models not downloaded. Tests gracefully skip.

---

## ⚡ Total Time

- Basic run: ~5 minutes
- Thread Sanitizer: ~10 minutes
- Address Sanitizer: ~10 minutes
- Documentation: ~5 minutes

**Total: ~30 minutes to complete full test suite** ⏱️

---

## 📞 Quick Reference

**Run all tests:** ⌘U  
**Stop tests:** ⌘.  
**View tests:** ⌘6  
**View console:** ⌘⇧C  
**Clear console:** ⌘K  

**Edit scheme:** Click scheme dropdown → Edit Scheme  
**Enable sanitizer:** Edit Scheme → Test → Diagnostics  

---

**Ready to find bugs? Press ⌘U!** 🚀
