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

# Run the Debug unit-test host directly. Package plug-ins are already pinned by
# Package.resolved; skip interactive validation so CI and fresh machines behave
# the same as the documented build command.
test_args=(
    test
    -project VoiceInk.xcodeproj
    -scheme VoiceInk
    -configuration Debug
    -destination 'platform=macOS,arch=arm64,name=My Mac'
    -resultBundlePath TestResults
    -only-testing:VoiceInkTests
    -parallel-testing-enabled NO
    -skipPackagePluginValidation
    -skipMacroValidation
    'CODE_SIGN_IDENTITY='
    CODE_SIGNING_REQUIRED=NO
    CODE_SIGNING_ALLOWED=NO
)

if command -v xcbeautify >/dev/null 2>&1; then
    echo "✨ Using xcbeautify for output"

    # Capture both statuses so formatter failures cannot hide an xcodebuild failure.
    set +e
    xcodebuild "${test_args[@]}" | xcbeautify
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
    xcodebuild "${test_args[@]}"
fi
