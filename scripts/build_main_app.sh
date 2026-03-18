#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/apps/main_app"
TARGET="${1:-verify}"

if ! command -v flutter >/dev/null 2>&1; then
  export PATH="$HOME/.local/share/flutter/bin:$PATH"
fi

if ! command -v flutter >/dev/null 2>&1; then
  echo "flutter not found; please install Flutter or export PATH first" >&2
  exit 1
fi

prepare() {
  cd "$ROOT_DIR"
  flutter pub get
  flutter pub run melos bootstrap
}

build_host_guard() {
  local required="$1"
  local current
  current="$(uname -s)"
  case "$required" in
    Linux) [[ "$current" == "Linux" ]] ;;
    Darwin) [[ "$current" == "Darwin" ]] ;;
    MINGW*|MSYS*|CYGWIN*) [[ "$current" == MINGW* || "$current" == MSYS* || "$current" == CYGWIN* ]] ;;
    *) return 1 ;;
  esac
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing required command: $1" >&2
    exit 1
  }
}

key_properties_value() {
  local key="$1"
  local file="$2"
  sed -n "s/^${key}=//p" "$file" | head -n1
}

resolve_android_store_file() {
  local raw_path="$1"
  python3 - "$raw_path" "$APP_DIR/android/app" <<'PY'
from pathlib import Path
import sys

raw = sys.argv[1].strip()
base = Path(sys.argv[2])
path = Path(raw)
if not path.is_absolute():
    path = (base / path).resolve()
print(path)
PY
}

preflight_linux() {
  require_cmd cmake
  require_cmd ninja
  if ! command -v c++ >/dev/null 2>&1 && ! command -v g++ >/dev/null 2>&1 && ! command -v clang++ >/dev/null 2>&1; then
    echo "missing required C++ compiler: install c++, g++, or clang++" >&2
    exit 1
  fi
}

require_android_signing() {
  local key_properties="$APP_DIR/android/key.properties"
  local raw_store_file
  local store_file
  local key_alias
  if [[ ! -f "$key_properties" ]]; then
    echo "missing Android signing file: $key_properties" >&2
    echo "copy apps/main_app/android/key.properties.example to key.properties first" >&2
    exit 1
  fi
  if grep -Fq 'replace-me' "$key_properties"; then
    echo "Android signing file still contains placeholder values: $key_properties" >&2
    exit 1
  fi
  raw_store_file="$(key_properties_value storeFile "$key_properties")"
  key_alias="$(key_properties_value keyAlias "$key_properties")"
  if [[ -z "$raw_store_file" || -z "$key_alias" ]]; then
    echo "Android signing file is incomplete: $key_properties" >&2
    exit 1
  fi
  store_file="$(resolve_android_store_file "$raw_store_file")"
  if [[ ! -f "$store_file" ]]; then
    echo "Android keystore not found: $store_file" >&2
    exit 1
  fi
  if [[ "$store_file" == *debug.keystore || "$key_alias" == "androiddebugkey" ]]; then
    echo "Android release signing still points to debug keystore/debug alias" >&2
    echo "run scripts/create_main_app_android_signing.sh to generate real release signing materials" >&2
    exit 1
  fi
}

usage() {
  cat <<USAGE
Usage: scripts/build_main_app.sh <target>

Targets:
  verify                  Run release metadata checks, analyze, and tests
  verify-release-metadata Check pubspec / manifest / changelog release metadata
  provider-live-smoke     Run remote provider smoke checks (optional, non-hermetic)
  android-apk-split       Build Android split-per-abi APK release
  linux                   Build Linux release (Linux host only)
  windows                 Build Windows release (Windows host only)
  macos                   Build macOS release (macOS host only)
  ios                     Build iOS release without codesign (macOS host only)
  android-apk             Build Android APK release
  android-appbundle       Build Android App Bundle release
  android-release-ready   Run verify + signed Android split APK/AAB release builds
  android-release-acceptance Run release-ready + install + launch-check + connected smoke on device
  android-mobile-release  Build Android split APK + App Bundle for first release
  android-release-launch-check Verify installed Android release app launches on device
  android-connected-smoke Run deterministic Android connected-device smoke
USAGE
}

case "$TARGET" in
  verify)
    prepare
    cd "$ROOT_DIR"
    scripts/verify_release_metadata.sh
    flutter pub run melos run analyze
    flutter pub run melos run test
    ;;
  verify-release-metadata)
    scripts/verify_release_metadata.sh
    ;;
  provider-live-smoke)
    prepare
    cd "$ROOT_DIR/packages/live_providers"
    dart run tool/smoke_live_providers.dart
    ;;
  linux)
    build_host_guard Linux || { echo "linux build requires a Linux host" >&2; exit 1; }
    preflight_linux
    prepare
    cd "$APP_DIR"
    flutter build linux --release
    ;;
  windows)
    build_host_guard 'MINGW*' || { echo "windows build requires a Windows host" >&2; exit 1; }
    prepare
    cd "$APP_DIR"
    flutter build windows --release
    ;;
  macos)
    build_host_guard Darwin || { echo "macos build requires a macOS host" >&2; exit 1; }
    prepare
    cd "$APP_DIR"
    flutter build macos --release
    ;;
  ios)
    build_host_guard Darwin || { echo "ios build requires a macOS host" >&2; exit 1; }
    prepare
    cd "$APP_DIR"
    flutter build ios --release --no-codesign
    ;;
  android-apk)
    prepare
    cd "$APP_DIR"
    flutter build apk --release
    ;;
  android-apk-split)
    prepare
    cd "$APP_DIR"
    flutter build apk --release --split-per-abi
    ;;
  android-appbundle)
    prepare
    cd "$APP_DIR/android"
    ./gradlew :app:bundleRelease
    ;;
  android-release-ready)
    require_android_signing
    prepare
    cd "$ROOT_DIR"
    scripts/verify_release_metadata.sh
    flutter pub run melos run analyze
    flutter pub run melos run test
    cd "$APP_DIR"
    flutter build apk --release --split-per-abi
    cd "$APP_DIR/android"
    ./gradlew :app:bundleRelease
    cd "$ROOT_DIR"
    scripts/verify_android_release_signing.sh
    ;;
  android-release-acceptance)
    require_android_signing
    prepare
    cd "$ROOT_DIR"
    scripts/verify_release_metadata.sh
    flutter pub run melos run analyze
    flutter pub run melos run test
    cd "$APP_DIR"
    flutter build apk --release --split-per-abi
    cd "$APP_DIR/android"
    ./gradlew :app:bundleRelease
    cd "$ROOT_DIR"
    scripts/verify_android_release_signing.sh
    scripts/install_main_app_android.sh
    scripts/verify_main_app_android_launch.sh
    scripts/run_main_app_android_smoke.sh
    scripts/install_main_app_android.sh
    scripts/verify_main_app_android_launch.sh
    ;;
  android-mobile-release)
    prepare
    cd "$APP_DIR"
    flutter build apk --release --split-per-abi
    cd "$APP_DIR/android"
    ./gradlew :app:bundleRelease
    cat <<ARTIFACTS
Android release artifacts:
- $APP_DIR/build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk
- $APP_DIR/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
- $APP_DIR/build/app/outputs/flutter-apk/app-x86_64-release.apk
- $APP_DIR/build/app/outputs/bundle/release/app-release.aab
ARTIFACTS
    ;;
  android-release-launch-check)
    cd "$ROOT_DIR"
    scripts/verify_main_app_android_launch.sh
    ;;
  android-connected-smoke)
    prepare
    cd "$ROOT_DIR"
    scripts/run_main_app_android_smoke.sh
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    usage >&2
    exit 1
    ;;
esac
