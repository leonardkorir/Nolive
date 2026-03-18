#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/apps/main_app"
MANIFEST_FILE="$APP_DIR/lib/src/features/settings/application/release_info_manifest.dart"
PUBSPEC_FILE="$APP_DIR/pubspec.yaml"
ANDROID_BUILD_FILE="$APP_DIR/android/app/build.gradle.kts"
CHANGELOG_FILE="$ROOT_DIR/CHANGELOG.md"
README_FILE="$ROOT_DIR/README.md"
SCRIPTS_README_FILE="$ROOT_DIR/scripts/README.md"
ANDROID_GUIDE_FILE="$ROOT_DIR/docs/android-release-guide.md"
RELEASE_CHECKLIST_FILE="$ROOT_DIR/docs/release-checklist.md"

read_single_quoted_value() {
  local pattern="$1"
  local file="$2"
  sed -n "s/.*${pattern} = '\([^']*\)'.*/\1/p" "$file" | head -n 1
}

pubspec_version="$(sed -n 's/^version:[[:space:]]*//p' "$PUBSPEC_FILE" | head -n 1)"
fallback_version="$(read_single_quoted_value 'fallbackVersion' "$MANIFEST_FILE")"
fallback_bundle_id="$(read_single_quoted_value 'fallbackBundleId' "$MANIFEST_FILE")"
primary_platform="$(read_single_quoted_value 'primaryPlatform' "$MANIFEST_FILE")"
build_bundle_id="$(sed -n 's/.*applicationId = "\([^"]*\)".*/\1/p' "$ANDROID_BUILD_FILE" | head -n 1)"
release_version="${pubspec_version%%+*}"

failures=0

check_equal() {
  local label="$1"
  local left="$2"
  local right="$3"
  if [[ "$left" != "$right" ]]; then
    echo "[release-metadata] mismatch: $label => '$left' != '$right'" >&2
    failures=$((failures + 1))
  fi
}

check_contains() {
  local label="$1"
  local needle="$2"
  local file="$3"
  if ! grep -Fq "$needle" "$file"; then
    echo "[release-metadata] missing '$needle' in $label ($file)" >&2
    failures=$((failures + 1))
  fi
}

check_regex() {
  local label="$1"
  local regex="$2"
  local file="$3"
  if ! grep -Eq "$regex" "$file"; then
    echo "[release-metadata] missing pattern '$regex' in $label ($file)" >&2
    failures=$((failures + 1))
  fi
}

if [[ -z "$pubspec_version" ]]; then
  echo '[release-metadata] failed to read version from pubspec' >&2
  exit 1
fi

check_equal 'pubspec version vs fallbackVersion' "$pubspec_version" "$fallback_version"
check_equal 'bundle id vs fallbackBundleId' "$build_bundle_id" "$fallback_bundle_id"
check_equal 'primary platform' "$primary_platform" 'Android mobile'
check_regex 'CHANGELOG release section' "^## ${release_version}( |-|$)" "$CHANGELOG_FILE"
check_contains 'README' '当前正式发布目标是 Android。' "$README_FILE"
check_contains 'README' 'scripts/build_main_app.sh android-release-ready' "$README_FILE"
check_contains 'scripts/README' 'scripts/build_main_app.sh android-release-ready' "$SCRIPTS_README_FILE"
check_contains 'scripts/README' 'scripts/run_main_app_android_smoke.sh' "$SCRIPTS_README_FILE"
check_contains 'Android guide' 'Android mobile first' "$ANDROID_GUIDE_FILE"
check_contains 'Android guide' 'scripts/run_main_app_android_smoke.sh' "$ANDROID_GUIDE_FILE"
check_contains 'Android guide' 'scripts/build_main_app.sh android-release-acceptance' "$ANDROID_GUIDE_FILE"
check_contains 'Release checklist' 'scripts/build_main_app.sh android-release-ready' "$RELEASE_CHECKLIST_FILE"
check_contains 'Release checklist' 'scripts/run_main_app_android_smoke.sh' "$RELEASE_CHECKLIST_FILE"
check_contains 'Release checklist' 'scripts/build_main_app.sh android-release-acceptance' "$RELEASE_CHECKLIST_FILE"

if [[ "$failures" -gt 0 ]]; then
  echo "[release-metadata] verification failed with $failures issue(s)" >&2
  exit 1
fi

cat <<SUMMARY
[release-metadata] verified
- version: $pubspec_version
- release section: $release_version
- bundle id: $build_bundle_id
- primary platform: $primary_platform
SUMMARY
