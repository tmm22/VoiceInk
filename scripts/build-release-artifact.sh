#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_FILE="$ROOT_DIR/VoiceInk.xcodeproj/project.pbxproj"
signing_mode="${VOICEINK_RELEASE_SIGNING_MODE:-unsigned}"

if ! command -v rsync >/dev/null 2>&1; then
  echo "rsync is required" >&2
  exit 1
fi

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "xcodebuild is required" >&2
  exit 1
fi

if ! command -v hdiutil >/dev/null 2>&1; then
  echo "hdiutil is required" >&2
  exit 1
fi

version="$(
  perl -ne 'if (/MARKETING_VERSION = ([0-9.]+);/) { print $1; exit }' "$PROJECT_FILE"
)"
build_number="$(
  perl -ne 'if (/CURRENT_PROJECT_VERSION = ([0-9]+);/) { print $1; exit }' "$PROJECT_FILE"
)"

if [[ -z "${version}" || -z "${build_number}" ]]; then
  echo "Failed to read version metadata from $PROJECT_FILE" >&2
  exit 1
fi

tag="v${version}-community"
output_root="${1:-$ROOT_DIR/release-artifacts/$tag}"
stage_dir="$(mktemp -d "${TMPDIR:-/tmp}/voiceink-release.XXXXXX")"
derived_data_dir="$stage_dir/.release-derived"
artifact_name="VoiceInk.dmg"
artifact_path="$output_root/$artifact_name"
checksum_path="$artifact_path.sha256"
dmg_staging_dir="$stage_dir/dmg-root"
build_configuration="Release"
strip_build_args=(
  DEPLOYMENT_POSTPROCESSING=YES
  STRIP_INSTALLED_PRODUCT=YES
  COPY_PHASE_STRIP=YES
  STRIPFLAGS=-x
)

thin_arm64_unsigned_app() {
  local app_bundle="$1"
  local path=""
  local info=""
  local temp_output=""

  echo "Thinning universal embedded binaries to arm64"

  while IFS= read -r -d '' path; do
    info="$(lipo -info "$path" 2>/dev/null || true)"
    if [[ "$info" != *"x86_64 arm64"* && "$info" != *"arm64 x86_64"* ]]; then
      continue
    fi

    temp_output="${path}.arm64"
    lipo "$path" -thin arm64 -output "$temp_output"
    mv "$temp_output" "$path"
  done < <(find "$app_bundle/Contents" -type f -perm -111 -print0)

  echo "Re-signing thinned app bundle"
  while IFS= read -r -d '' path; do
    codesign --force --sign - \
      --preserve-metadata=identifier,entitlements,requirements,flags,runtime \
      "$path"
  done < <(find "$app_bundle/Contents" \
    \( -name '*.app' -o -name '*.xpc' -o -name '*.framework' -o -name '*.dylib' \) \
    -depth -print0)

  codesign --force --sign - \
    --preserve-metadata=identifier,entitlements,requirements,flags,runtime \
    "$app_bundle"
}

cleanup() {
  if [[ -d "$stage_dir" ]]; then
    rm -rf "$stage_dir"
  fi
}
trap cleanup EXIT

mkdir -p "$output_root"

echo "Staging repository into $stage_dir"
rsync -a \
  --exclude '.git' \
  --exclude 'build' \
  --exclude '.derivedData-local' \
  --exclude '.derivedData-local-2' \
  --exclude 'release-artifacts' \
  --exclude 'TestResults*' \
  --exclude '*.xcresult' \
  "$ROOT_DIR/" \
  "$stage_dir/"

echo "Building VoiceInk $version ($build_number) [$build_configuration]"
(
  cd "$stage_dir"
  case "$signing_mode" in
    unsigned)
      xcodebuild \
        -project VoiceInk.xcodeproj \
        -scheme VoiceInk \
        -configuration "$build_configuration" \
        -derivedDataPath "$derived_data_dir" \
        -xcconfig LocalBuild.xcconfig \
        "${strip_build_args[@]}" \
        CODE_SIGN_IDENTITY="-" \
        CODE_SIGNING_REQUIRED=NO \
        CODE_SIGNING_ALLOWED=YES \
        DEVELOPMENT_TEAM="" \
        "CODE_SIGN_ENTITLEMENTS=$stage_dir/VoiceInk/VoiceInk.local.entitlements" \
        clean build
      ;;
    project)
      xcodebuild \
        -project VoiceInk.xcodeproj \
        -scheme VoiceInk \
        -configuration "$build_configuration" \
        -derivedDataPath "$derived_data_dir" \
        "${strip_build_args[@]}" \
        CODE_SIGNING_ALLOWED=YES \
        clean build
      ;;
    *)
      echo "Unsupported VOICEINK_RELEASE_SIGNING_MODE: $signing_mode" >&2
      echo "Expected 'unsigned' or 'project'" >&2
      exit 1
      ;;
  esac
)

app_path="$derived_data_dir/Build/Products/$build_configuration/VoiceInk.app"
if [[ ! -d "$app_path" ]]; then
  echo "Expected app bundle not found at $app_path" >&2
  exit 1
fi

mkdir -p "$dmg_staging_dir"
ditto "$app_path" "$dmg_staging_dir/VoiceInk.app"
ln -s /Applications "$dmg_staging_dir/Applications"

if [[ "$signing_mode" == "unsigned" ]]; then
  thin_arm64_unsigned_app "$dmg_staging_dir/VoiceInk.app"
fi

rm -f "$artifact_path" "$checksum_path"

echo "Creating DMG at $artifact_path"
hdiutil create \
  -volname "VoiceInk $version" \
  -srcfolder "$dmg_staging_dir" \
  -format UDZO \
  "$artifact_path" \
  >/dev/null

shasum -a 256 "$artifact_path" > "$checksum_path"

echo "Built:"
echo "  App: $app_path"
echo "  DMG: $artifact_path"
echo "  SHA: $checksum_path"
