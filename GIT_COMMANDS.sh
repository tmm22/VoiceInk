#!/bin/bash
# Git Workflow for Quality of Life Improvements
# Execute these commands step by step

set -e  # Exit on error

echo "================================================"
echo "VoiceLink Community - QOL Improvements Workflow"
echo "================================================"
echo ""

# Step 1: Check current status
echo "Step 1: Checking current git status..."
git status

echo ""
echo "Step 2: Review changes..."
git diff --stat

echo ""
read -p "Continue with commit? (y/n) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted by user"
    exit 1
fi

# Step 3: Stage all changes
echo "Step 3: Staging changes..."
git add VoiceInk/Recorder.swift
git add VoiceInk/Views/Recorder/RecorderComponents.swift
git add VoiceInk/Views/Recorder/MiniRecorderView.swift
git add VoiceInk/Views/Recorder/NotchRecorderView.swift
git add VoiceInk/Views/ContentView.swift
git add VoiceInk/VoiceInk.swift
git add VoiceInk/Notifications/AppNotifications.swift
git add VoiceInk/Views/KeyboardShortcutCheatSheet.swift
git add VoiceInk/Utilities/AppLogger.swift
git add QOL_IMPROVEMENTS_CHANGELOG.md
git add IMPLEMENTATION_SUMMARY.md
git add UPSTREAM_ISSUE.md
git add UPSTREAM_PR_DESCRIPTION.md
git add QUALITY_OF_LIFE_IMPROVEMENTS.md
git add GIT_COMMANDS.sh

echo ""
echo "Staged files:"
git status --short

echo ""
read -p "Continue with commit? (y/n) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted by user"
    exit 1
fi

# Step 4: Commit changes
echo "Step 4: Creating commit..."
git commit -m "feat: Add 5 critical quality of life improvements

This commit introduces five high-priority UX enhancements:

1. Recording duration indicator with real-time timer
   - Shows MM:SS format during recording
   - Updates every 0.1 seconds
   - Includes accessibility support

2. Enhanced status display with visual feedback
   - Clear \"Ready\", \"Recording\", \"Transcribing\", \"Enhancing\" states
   - Improved accessibility labels
   - Professional, polished UI

3. Visible cancel button during recording
   - Red X button appears when recording
   - Smooth animations
   - Works alongside ESC double-tap

4. Keyboard shortcut cheat sheet (Cmd+?)
   - Comprehensive shortcut reference
   - Organized by category
   - Dynamically shows user's configured shortcuts
   - Accessible via Help menu

5. Structured logging system (AppLogger)
   - Centralized logging with OSLog
   - Category-specific loggers
   - Better production debugging
   - Performance optimized

All changes are backward compatible with no breaking changes.
Tested on macOS 14.0+ (Sonoma).

Files Created:
- VoiceInk/Views/KeyboardShortcutCheatSheet.swift
- VoiceInk/Utilities/AppLogger.swift
- Documentation files

Files Modified:
- VoiceInk/Recorder.swift
- VoiceInk/Views/Recorder/RecorderComponents.swift
- VoiceInk/Views/Recorder/MiniRecorderView.swift
- VoiceInk/Views/Recorder/NotchRecorderView.swift
- VoiceInk/Views/ContentView.swift
- VoiceInk/VoiceInk.swift
- VoiceInk/Notifications/AppNotifications.swift

See QOL_IMPROVEMENTS_CHANGELOG.md for detailed documentation.

Co-authored-by: factory-droid[bot] <138933559+factory-droid[bot]@users.noreply.github.com>"

echo ""
echo "✅ Commit created successfully!"
echo ""

# Step 5: Show commit
echo "Step 5: Verifying commit..."
git log -1 --stat

echo ""
echo "================================================"
echo "Next Steps:"
echo "================================================"
echo ""
echo "FOR FORK INTEGRATION:"
echo "  1. Push to your fork's main branch:"
echo "     git push origin custom-main-v2"
echo ""
echo "FOR UPSTREAM PR:"
echo "  1. Create and switch to feature branch:"
echo "     git checkout -b feature/qol-improvements"
echo ""
echo "  2. Push feature branch to your fork:"
echo "     git push origin feature/qol-improvements"
echo ""
echo "  3. Create GitHub Issue:"
echo "     - Go to upstream repository"
echo "     - Click 'Issues' → 'New Issue'"
echo "     - Copy content from: UPSTREAM_ISSUE.md"
echo "     - Note the issue number (e.g., #42)"
echo ""
echo "  4. Create Pull Request:"
echo "     - Go to your fork on GitHub"
echo "     - Click 'Pull Request' → 'New Pull Request'"
echo "     - Base: upstream/main ← Head: your-fork/feature/qol-improvements"
echo "     - Copy content from: UPSTREAM_PR_DESCRIPTION.md"
echo "     - Replace #XXX with issue number from step 3"
echo "     - Add screenshots to PR description"
echo ""
echo "  5. Capture screenshots before submitting:"
echo "     - Recording with duration timer"
echo "     - Cancel button visible"
echo "     - Keyboard shortcut cheat sheet (Cmd+?)"
echo "     - Different status states"
echo ""
echo "================================================"
echo "IMPORTANT: Review the commit before pushing!"
echo "================================================"
echo ""
echo "To review: git show HEAD"
echo "To amend: git commit --amend"
echo "To undo: git reset HEAD~1"
echo ""
