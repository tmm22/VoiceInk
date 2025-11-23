#!/bin/bash
set -e

echo "🚀 Starting Tests..."

# Remove existing TestResults
rm -rf TestResults

# Check if Xcode project exists
if [ ! -d "VoiceInk.xcodeproj" ]; then
    echo "❌ Error: VoiceInk.xcodeproj not found in current directory"
    exit 1
fi

# Run tests using xcodebuild
# Explicitly selecting the VoiceInkTests target to avoid running UI tests that require code signing
xcodebuild build-for-testing test-without-building \
    -project VoiceInk.xcodeproj \
    -scheme VoiceInk \
    -destination 'platform=macOS' \
    -resultBundlePath TestResults \
    -only-testing:VoiceInkTests \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGNING_REQUIRED=NO \
    | xcbeautify || true

# Note: piped to xcbeautify if available, otherwise just runs. 
# The '|| true' ensures the pipe doesn't fail the script if xcbeautify isn't installed,
# but we actually want to see the output. If xcbeautify isn't there, it might fail the pipe.
# Better approach for CI/scripts without external dependencies:

if command -v xcbeautify &> /dev/null; then
    echo "✨ Using xcbeautify for output"
else
    echo "⚠️ xcbeautify not found, using raw xcodebuild output"
fi
