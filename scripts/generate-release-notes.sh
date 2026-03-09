#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_FILE="$ROOT_DIR/VoiceInk.xcodeproj/project.pbxproj"
CHANGELOG_FILE="$ROOT_DIR/CHANGELOG.md"
TEMPLATE_FILE="$ROOT_DIR/.github/RELEASE_TEMPLATE.md"

repo="${GITHUB_REPO:-tmm22/VoiceInk}"
version="$(
  perl -ne 'if (/MARKETING_VERSION = ([0-9.]+);/) { print $1; exit }' "$PROJECT_FILE"
)"
tag="v${version}-community"
output_path="${1:-$ROOT_DIR/release-artifacts/$tag/release-notes.md}"

if [[ -z "$version" ]]; then
  echo "Failed to read version from $PROJECT_FILE" >&2
  exit 1
fi

latest_entry="$(
  awk '
    /^## [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/ {
      if (capture) exit
      capture=1
      next
    }
    capture { print }
  ' "$CHANGELOG_FILE"
)"

latest_entry="$(
  printf '%s\n' "$latest_entry" | awk '
    started || NF {
      started=1
      print
    }
  '
)"

if [[ -z "$latest_entry" ]]; then
  echo "Failed to extract latest changelog entry from $CHANGELOG_FILE" >&2
  exit 1
fi

highlights="$(
  printf '%s\n' "$latest_entry" | awk '
    /^- / {
      print
      count++
      if (count == 6) exit
    }
  '
)"

if [[ -z "$highlights" ]]; then
  highlights="- See the project release notes below."
fi

downloads_and_below="$(
  awk '
    /^## Downloads$/ { capture=1 }
    capture { print }
  ' "$TEMPLATE_FILE"
)" 

downloads_and_below="$(
  printf '%s\n' "$downloads_and_below" | awk '
    /^- Add release-specific notes here, or paste generated release notes below this heading\.$/ { next }
    /^- If you are using the automation scripts, this section is filled from `CHANGELOG\.md` automatically\.$/ { next }
    { print }
  '
)"

previous_tag="$(
  git -C "$ROOT_DIR" tag --list 'v*-community' --sort=-v:refname | awk -v current="$tag" '$0 != current { print; exit }'
)"

compare_url=""
if [[ -n "$previous_tag" ]]; then
  compare_url="https://github.com/$repo/compare/$previous_tag...$tag"
fi

mkdir -p "$(dirname "$output_path")"

{
  printf '## Highlights\n\n'
  printf '%s\n' "$highlights"
  printf '\n## Project Release Notes\n\n'
  printf '%s\n' "$latest_entry"
  printf '\n%s\n' "$downloads_and_below"
  if [[ -n "$compare_url" ]]; then
    printf '\n- %s\n' "$compare_url"
  fi
} > "$output_path"

echo "$output_path"
