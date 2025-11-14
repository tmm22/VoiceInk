#!/bin/bash

# Reset all VoiceInk permissions

echo "═══════════════════════════════════════════════════════════"
echo "  Resetting VoiceInk Permissions"
echo "═══════════════════════════════════════════════════════════"
echo ""

BUNDLE_ID="com.tmm22.VoiceLinkCommunity"

echo "Resetting all permissions for: $BUNDLE_ID"
echo ""

# Reset all permissions
tccutil reset All $BUNDLE_ID 2>/dev/null

# Reset onboarding flag
defaults write $BUNDLE_ID hasCompletedOnboarding -bool false 2>/dev/null

if [ $? -eq 0 ]; then
    echo "✅ All permissions reset successfully"
    echo "✅ Onboarding flag reset"
    echo ""
    echo "Next steps:"
    echo "1. Quit VoiceInk if it's running"
    echo "2. Launch VoiceInk"
    echo "3. You'll see the full onboarding flow with permission prompts"
else
    echo "⚠️  Some permissions may require manual reset"
    echo ""
    echo "To reset manually:"
    echo "1. Open System Settings"
    echo "2. Privacy & Security"
    echo "3. Find VoiceInk in:"
    echo "   - Microphone"
    echo "   - Accessibility"
    echo "   - Screen Recording"
fi

echo ""
echo "═══════════════════════════════════════════════════════════"
