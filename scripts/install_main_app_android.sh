#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/apps/main_app"
APK_DIR="$APP_DIR/build/app/outputs/flutter-apk"
DEVICE_ID="${ANDROID_DEVICE_ID:-}"

if ! command -v adb >/dev/null 2>&1; then
  echo "adb not found; please install Android platform-tools first" >&2
  exit 1
fi

if [[ -n "$DEVICE_ID" ]]; then
  adb_cmd=(adb -s "$DEVICE_ID")
else
  device_count="$(adb devices | awk 'NR>1 && $2=="device" {count++} END {print count+0}')"
  if [[ "$device_count" -eq 0 ]]; then
    echo "no Android device detected; connect a phone or start an emulator" >&2
    exit 1
  fi
  if [[ "$device_count" -gt 1 ]]; then
    echo "multiple Android devices detected; set ANDROID_DEVICE_ID explicitly" >&2
    adb devices
    exit 1
  fi
  DEVICE_ID="$(adb devices | awk 'NR>1 && $2=="device" {print $1; exit}')"
  adb_cmd=(adb -s "$DEVICE_ID")
fi

abi="$(${adb_cmd[@]} shell getprop ro.product.cpu.abi | tr -d '\r' | tr -d '\n')"
case "$abi" in
  arm64-v8a)
    apk_path="$APK_DIR/app-arm64-v8a-release.apk"
    ;;
  armeabi-v7a)
    apk_path="$APK_DIR/app-armeabi-v7a-release.apk"
    ;;
  x86_64)
    apk_path="$APK_DIR/app-x86_64-release.apk"
    ;;
  *)
    echo "unsupported or unknown Android ABI: $abi" >&2
    echo "run scripts/build_main_app.sh android-mobile-release first" >&2
    exit 1
    ;;
esac

if [[ ! -f "$apk_path" ]]; then
  echo "APK not found: $apk_path" >&2
  echo "run scripts/build_main_app.sh android-mobile-release first" >&2
  exit 1
fi

echo "Installing $apk_path to Android device $DEVICE_ID ($abi)..."
"${adb_cmd[@]}" install -r "$apk_path"
echo "Install complete on $DEVICE_ID. Continue Android manual smoke checks from docs/release-checklist.md."
