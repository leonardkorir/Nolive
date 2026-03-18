#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHANGELOG_FILE="$ROOT_DIR/CHANGELOG.md"

usage() {
  cat <<'USAGE'
Usage: scripts/render_release_notes.sh <version>

Examples:
  scripts/render_release_notes.sh v0.2.0
  scripts/render_release_notes.sh 0.2.0
USAGE
}

if [[ $# -ne 1 ]]; then
  usage >&2
  exit 1
fi

version="${1#v}"

if [[ ! -f "$CHANGELOG_FILE" ]]; then
  echo "missing changelog file: $CHANGELOG_FILE" >&2
  exit 1
fi

release_notes="$(
  awk -v version="$version" '
    BEGIN {
      target = "## " version " - "
      found = 0
    }
    index($0, target) == 1 {
      found = 1
    }
    /^## / && found && index($0, target) != 1 {
      exit
    }
    found {
      print
    }
  ' "$CHANGELOG_FILE"
)"

if [[ -z "$release_notes" ]]; then
  echo "failed to find release notes for version $version in $CHANGELOG_FILE" >&2
  exit 1
fi

printf '%s\n' "$release_notes"
