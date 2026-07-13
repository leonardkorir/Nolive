#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="${ROOT_DIR}/apps/main_app"
APK_PATH="${APP_DIR}/build/app/outputs/flutter-apk/app-debug.apk"
DEVICE_ID="${ANDROID_DEVICE_ID:-}"
BUILD_APK="${BUILD_APK:-1}"

usage() {
  cat <<'EOF'
Usage:
  scripts/install_main_app_android_debug.sh

Environment:
  ANDROID_DEVICE_ID   Explicit adb device id when multiple devices are connected.
  BUILD_APK           Build debug APK before install. Default: 1.
EOF
}

require_adb() {
  if ! command -v adb >/dev/null 2>&1; then
    echo "adb not found; please install Android platform-tools first" >&2
    exit 1
  fi
}

select_device() {
  if [[ -n "${DEVICE_ID}" ]]; then
    adb_cmd=(adb -s "${DEVICE_ID}")
    return
  fi

  local device_count
  device_count="$(adb devices | awk 'NR>1 && $2=="device" {count++} END {print count+0}')"
  if [[ "${device_count}" -eq 0 ]]; then
    echo "no Android device detected; connect a phone or start an emulator" >&2
    exit 1
  fi
  if [[ "${device_count}" -gt 1 ]]; then
    echo "multiple Android devices detected; set ANDROID_DEVICE_ID explicitly" >&2
    adb devices
    exit 1
  fi

  DEVICE_ID="$(adb devices | awk 'NR>1 && $2=="device" {print $1; exit}')"
  adb_cmd=(adb -s "${DEVICE_ID}")
}

main() {
  case "${1:-}" in
    -h|--help|help)
      usage
      return
      ;;
    '')
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac

  require_adb
  select_device

  if [[ "${BUILD_APK}" == "1" ]]; then
    (
      cd "${APP_DIR}"
      flutter build apk --debug --target=lib/main.dart
    )
  fi

  if [[ ! -f "${APK_PATH}" ]]; then
    echo "debug APK not found: ${APK_PATH}" >&2
    exit 1
  fi

  echo "Installing ${APK_PATH} to Android device ${DEVICE_ID}..."
  "${adb_cmd[@]}" install -r -d "${APK_PATH}"
  echo "Debug install complete on ${DEVICE_ID}."
}

main "$@"
