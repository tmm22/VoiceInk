#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_FILE="$ROOT_DIR/VoiceInk.xcodeproj/project.pbxproj"
signing_mode="${VOICEINK_RELEASE_SIGNING_MODE:-unsigned}"

if ! command -v tar >/dev/null 2>&1; then
  echo "tar is required" >&2
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
build_scheme="VoiceInkRelease"
dmg_format="UDBZ"
# Public GitHub/community artifacts rely on these settings for bundle-size control.
strip_build_args=(
  ENABLE_CODE_COVERAGE=NO
  CLANG_COVERAGE_MAPPING=NO
  CLANG_ENABLE_CODE_COVERAGE=NO
  DEPLOYMENT_POSTPROCESSING=YES
  STRIP_INSTALLED_PRODUCT=YES
  COPY_PHASE_STRIP=YES
  DEAD_CODE_STRIPPING=YES
  GENERATE_PROFILING_CODE=NO
  GCC_GENERATE_TEST_COVERAGE_FILES=NO
  LLVM_LTO=YES_THIN
  OTHER_SWIFT_FLAGS='$(inherited) -cross-module-optimization'
  STRIPFLAGS=-x
  SWIFT_OPTIMIZATION_LEVEL=-Osize
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

  echo "Removing inherited code signatures from embedded code"
  while IFS= read -r -d '' path; do
    codesign --remove-signature "$path" 2>/dev/null || true
  done < <(find "$app_bundle/Contents" \
    \( -name '*.app' -o -name '*.xpc' -o -name '*.framework' -o -name '*.dylib' \) \
    -depth -print0)
  codesign --remove-signature "$app_bundle" 2>/dev/null || true

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

prune_espeak_to_english_only() {
  local app_bundle="$1"
  local data_dir="$app_bundle/Contents/Frameworks/ESpeakNG.framework/Versions/A/Resources/espeak-ng-data/espeak-ng-data"
  local keep_name=""

  if [[ ! -d "$data_dir" ]]; then
    echo "ESpeakNG data directory not found, skipping language-data pruning"
    return
  fi

  echo "Pruning ESpeakNG dictionaries to the English-only Pocket TTS subset"

  while IFS= read -r -d '' path; do
    keep_name="$(basename "$path")"
    case "$keep_name" in
      en_dict|phondata|phondata-manifest|phonindex|phontab|intonations)
        continue
        ;;
      *_dict)
        rm -f "$path"
        ;;
    esac
  done < <(find "$data_dir" -maxdepth 1 -type f -print0)
}

cleanup() {
  if [[ -d "$stage_dir" ]]; then
    rm -rf "$stage_dir"
  fi
}
trap cleanup EXIT

mkdir -p "$output_root"

echo "Staging repository into $stage_dir"
tar -C "$ROOT_DIR" \
  --exclude './.git' \
  --exclude './.codex_quarantine_duplicates' \
  --exclude './.build' \
  --exclude './build' \
  --exclude './.local-build' \
  --exclude './.derivedData-local' \
  --exclude './.derivedData-local-2' \
  --exclude './release-artifacts' \
  --exclude './web/node_modules' \
  --exclude './web/cloudflare-asr/node_modules' \
  --exclude './web/.next' \
  --exclude './web/dist' \
  --exclude './web/.wrangler' \
  --exclude './web/.env.local' \
  --exclude './TestResults*' \
  --exclude './*.xcresult' \
  -cf - . | tar -C "$stage_dir" -xf -

echo "Building VoiceInk $version ($build_number) [$build_configuration]"
(
  cd "$stage_dir"
  case "$signing_mode" in
    unsigned)
      xcodebuild \
        -project VoiceInk.xcodeproj \
        -scheme "$build_scheme" \
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
        -scheme "$build_scheme" \
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
  prune_espeak_to_english_only "$dmg_staging_dir/VoiceInk.app"
  thin_arm64_unsigned_app "$dmg_staging_dir/VoiceInk.app"
fi

rm -f "$artifact_path" "$checksum_path"

echo "Creating DMG at $artifact_path"
hdiutil create \
  -volname "VoiceInk $version" \
  -srcfolder "$dmg_staging_dir" \
  -format "$dmg_format" \
  "$artifact_path" \
  >/dev/null

shasum -a 256 "$artifact_path" > "$checksum_path"

echo "Built:"
echo "  App: $app_path"
echo "  DMG: $artifact_path"
echo "  SHA: $checksum_path"
