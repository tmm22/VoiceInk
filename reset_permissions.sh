#!/usr/bin/env bash

# Reset all VoiceInk permissions
set -u

echo "═══════════════════════════════════════════════════════════"
echo "  Resetting VoiceInk Permissions"
echo "═══════════════════════════════════════════════════════════"
echo ""

BUNDLE_ID="${1:-com.tmm22.VoiceLinkCommunity}"

echo "Resetting all permissions for: $BUNDLE_ID"
echo ""

# Reset all permissions
if tccutil reset All "$BUNDLE_ID"; then
    reset_status=0
else
    reset_status=$?
fi

# Reset onboarding flag
if defaults write "$BUNDLE_ID" hasCompletedOnboarding -bool false; then
    defaults_status=0
else
    defaults_status=$?
fi

if [ "$reset_status" -eq 0 ] && [ "$defaults_status" -eq 0 ]; then
    echo "✅ All permissions reset successfully"
    echo "✅ Onboarding flag reset"
    echo ""
    echo "Next steps:"
    echo "1. Quit VoiceInk if it's running"
    echo "2. Launch VoiceInk"
    echo "3. You'll see the full onboarding flow with permission prompts"
else
    echo "⚠️  Some permissions may require manual reset"
    echo "tccutil status: $reset_status"
    echo "defaults status: $defaults_status"
    echo ""
    echo "To reset manually:"
    echo "0. Run: tccutil reset All \"$BUNDLE_ID\""
    echo "1. Open System Settings"
    echo "2. Privacy & Security"
    echo "3. Find VoiceInk in:"
    echo "   - Microphone"
    echo "   - Accessibility"
    echo "   - Screen Recording"
fi

echo ""
echo "═══════════════════════════════════════════════════════════"
