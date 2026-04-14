#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/apps/main_app"
DEVICE_ID="${ANDROID_DEVICE_ID:-}"
RESTORE_RELEASE="${ANDROID_SMOKE_RESTORE_RELEASE:-1}"

# shellcheck source=/dev/null
source "$ROOT_DIR/scripts/lib/flutter_toolchain.sh"
require_flutter_toolchain

if ! command -v adb >/dev/null 2>&1; then
  echo "adb not found; please install Android platform-tools first" >&2
  exit 1
fi

if [[ -z "$DEVICE_ID" ]]; then
  DEVICE_ID="$(adb devices | awk 'NR>1 && $2=="device" {print $1; exit}')"
fi

if [[ -z "$DEVICE_ID" ]]; then
  echo "no Android device detected; connect a phone or start an emulator" >&2
  exit 1
fi

if ! rg -q 'io\.flutter\.embedding\.android\.EnableImpeller' \
  "$APP_DIR/android/app/src/main/AndroidManifest.xml"; then
  echo "Android manifest is missing io.flutter.embedding.android.EnableImpeller metadata" >&2
  exit 1
fi

has_release_artifact() {
  [[ -f "$APP_DIR/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk" ]] ||
    [[ -f "$APP_DIR/build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk" ]] ||
    [[ -f "$APP_DIR/build/app/outputs/flutter-apk/app-x86_64-release.apk" ]]
}

restore_release_if_needed() {
  local smoke_status="$1"
  local restore_status=0

  if [[ "$RESTORE_RELEASE" != "1" ]]; then
    return "$smoke_status"
  fi

  if ! has_release_artifact; then
    echo "Release APK not found after smoke; skipping automatic release restore." >&2
    echo "Run scripts/build_main_app.sh android-mobile-release or android-release-ready first." >&2
    return "$smoke_status"
  fi

  echo "Restoring release APK after smoke on device: $DEVICE_ID"
  if ! ANDROID_DEVICE_ID="$DEVICE_ID" "$ROOT_DIR/scripts/install_main_app_android.sh"; then
    restore_status=$?
  elif ! ANDROID_DEVICE_ID="$DEVICE_ID" "$ROOT_DIR/scripts/verify_main_app_android_launch.sh"; then
    restore_status=$?
  fi

  if [[ "$smoke_status" -ne 0 ]]; then
    return "$smoke_status"
  fi
  return "$restore_status"
}

cleanup() {
  local smoke_status=$?
  trap - EXIT
  restore_release_if_needed "$smoke_status"
  exit $?
}

trap cleanup EXIT

cd "$APP_DIR"
flutter pub get
echo "Running Android connected smoke on device: $DEVICE_ID"
flutter test integration_test/android_release_smoke_test.dart -d "$DEVICE_ID"
