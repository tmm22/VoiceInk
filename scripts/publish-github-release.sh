#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_SCRIPT="$ROOT_DIR/scripts/build-release-artifact.sh"
PROJECT_FILE="$ROOT_DIR/VoiceInk.xcodeproj/project.pbxproj"
RELEASE_TEMPLATE="$ROOT_DIR/.github/RELEASE_TEMPLATE.md"

if [[ ! -d "$ROOT_DIR/.git" ]]; then
  echo "publish-github-release.sh must run from a git checkout" >&2
  exit 1
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "gh is required" >&2
  exit 1
fi

if [[ -n "$(git -C "$ROOT_DIR" status --short)" ]]; then
  echo "Git worktree is not clean. Commit or stash changes before publishing." >&2
  exit 1
fi

version="$(
  perl -ne 'if (/MARKETING_VERSION = ([0-9.]+);/) { print $1; exit }' "$PROJECT_FILE"
)"
tag="v${version}-community"
repo="${GITHUB_REPO:-tmm22/VoiceInk}"
target_branch="${RELEASE_TARGET_BRANCH:-custom-main-v2}"
artifact_dir="${RELEASE_ARTIFACT_DIR:-$ROOT_DIR/release-artifacts/$tag}"
artifact_path="$artifact_dir/VoiceInk.dmg"
checksum_path="$artifact_path.sha256"
release_body_path="$artifact_dir/release-notes.md"

mkdir -p "$artifact_dir"

"$BUILD_SCRIPT" "$artifact_dir"
cp "$RELEASE_TEMPLATE" "$release_body_path"

git -C "$ROOT_DIR" push origin "$target_branch"

if git -C "$ROOT_DIR" rev-parse "$tag" >/dev/null 2>&1; then
  echo "Local tag $tag already exists" >&2
  exit 1
fi

git -C "$ROOT_DIR" tag "$tag"
git -C "$ROOT_DIR" push origin "$tag"

gh release create "$tag" \
  "$artifact_path" \
  "$checksum_path" \
  --repo "$repo" \
  --target "$target_branch" \
  --title "$tag" \
  --notes-file "$release_body_path"

echo "Published $tag to $repo"
