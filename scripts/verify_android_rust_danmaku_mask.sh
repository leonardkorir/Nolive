#!/usr/bin/env bash
# Ensure release APKs ship the native danmaku batch-mask library.
# Required for the in-app "原生弹幕频控" path (otherwise silent Dart fallback).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APK_DIR="$ROOT_DIR/apps/main_app/build/app/outputs/flutter-apk"
LIB_NAME="libnolive_danmaku_mask.so"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing required command: $1" >&2
    exit 1
  }
}

require_cmd unzip

# Opt out only when explicitly disabled (same knobs as Gradle).
enabled="${NOLIVE_BUILD_RUST_DANMAKU_MASK:-true}"
if [[ "$enabled" =~ ^([Ff][Aa][Ll][Ss][Ee]|0|[Nn][Oo])$ ]]; then
  echo "[rust-danmaku] NOLIVE_BUILD_RUST_DANMAKU_MASK disabled; skip APK .so check."
  exit 0
fi

declare -a expected=(
  "app-armeabi-v7a-release.apk:lib/armeabi-v7a/$LIB_NAME"
  "app-arm64-v8a-release.apk:lib/arm64-v8a/$LIB_NAME"
  "app-x86_64-release.apk:lib/x86_64/$LIB_NAME"
)

found_any=0
for entry in "${expected[@]}"; do
  apk_name="${entry%%:*}"
  so_path="${entry#*:}"
  apk="$APK_DIR/$apk_name"
  if [[ ! -f "$apk" ]]; then
    echo "[rust-danmaku] missing APK: $apk" >&2
    echo "  build with: scripts/build_main_app.sh android-apk-split (or android-release-ready)" >&2
    exit 1
  fi
  # Avoid `grep -q` under pipefail: early close can SIGPIPE unzip and fail the pipe.
  listing="$(unzip -l "$apk" 2>/dev/null || true)"
  if [[ "$listing" != *"$so_path"* ]]; then
    echo "[rust-danmaku] $apk_name is missing $so_path" >&2
    echo "  ensure cargo + Android NDK are available and NOLIVE_BUILD_RUST_DANMAKU_MASK is not false." >&2
    echo "  Gradle property: nolive.buildRustDanmakuMask=true" >&2
    exit 1
  fi
  echo "[rust-danmaku] ok: $apk_name contains $so_path"
  found_any=1
done

if [[ "$found_any" -ne 1 ]]; then
  echo "[rust-danmaku] no APKs verified" >&2
  exit 1
fi

echo "[rust-danmaku] release APKs include $LIB_NAME for all split ABIs."
