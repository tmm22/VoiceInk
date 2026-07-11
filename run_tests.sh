#!/bin/bash
set -euo pipefail

echo "🚀 Starting Tests..."

# Remove existing TestResults
rm -rf TestResults

# Check if Xcode project exists
if [ ! -d "VoiceInk.xcodeproj" ]; then
    echo "❌ Error: VoiceInk.xcodeproj not found in current directory"
    exit 1
fi

# Run tests using xcodebuild. Explicitly select VoiceInkTests to avoid running UI
# tests that require code signing.
if command -v xcbeautify >/dev/null 2>&1; then
    echo "✨ Using xcbeautify for output"

    # Capture both statuses so formatter failures cannot hide an xcodebuild failure.
    set +e
    xcodebuild build-for-testing test-without-building \
        -project VoiceInk.xcodeproj \
        -scheme VoiceInk \
        -destination 'platform=macOS' \
        -resultBundlePath TestResults \
        -only-testing:VoiceInkTests \
        CODE_SIGN_IDENTITY="" \
        CODE_SIGNING_REQUIRED=NO \
        | xcbeautify
    pipeline_status=("${PIPESTATUS[@]}")
    set -e

    xcodebuild_status="${pipeline_status[0]}"
    xcbeautify_status="${pipeline_status[1]}"

    if (( xcodebuild_status != 0 )); then
        echo "❌ xcodebuild failed with status ${xcodebuild_status}"
        exit "${xcodebuild_status}"
    fi

    if (( xcbeautify_status != 0 )); then
        echo "⚠️ xcbeautify failed with status ${xcbeautify_status}; tests still passed"
    fi
else
    echo "⚠️ xcbeautify not found, using raw xcodebuild output"
    xcodebuild build-for-testing test-without-building \
        -project VoiceInk.xcodeproj \
        -scheme VoiceInk \
        -destination 'platform=macOS' \
        -resultBundlePath TestResults \
        -only-testing:VoiceInkTests \
        CODE_SIGN_IDENTITY="" \
        CODE_SIGNING_REQUIRED=NO
fi
