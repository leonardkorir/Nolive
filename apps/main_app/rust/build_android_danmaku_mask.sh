#!/usr/bin/env bash
set -euo pipefail

warn() {
  echo "[nolive-rust] $*" >&2
}

fail_enabled_build() {
  warn "$*"
  exit 1
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CRATE_DIR="$SCRIPT_DIR/danmaku_mask"
OUT_DIR="${1:?output dir required}"
SDK_DIR_INPUT="${2:-}"
ENABLE_NATIVE_BUILD="${3:-false}"

if [[ ! "$ENABLE_NATIVE_BUILD" =~ ^([Tt][Rr][Uu][Ee]|1|[Yy][Ee][Ss])$ ]]; then
  warn "Rust danmaku mask build disabled, skip native build."
  exit 0
fi

if ! command -v cargo >/dev/null 2>&1; then
  fail_enabled_build "cargo not found, cannot build native danmaku mask."
fi

if ! command -v rustup >/dev/null 2>&1; then
  fail_enabled_build "rustup not found, cannot build native danmaku mask."
fi

if [[ -n "$SDK_DIR_INPUT" ]]; then
  SDK_DIR="$SDK_DIR_INPUT"
elif [[ -n "${ANDROID_SDK_ROOT:-}" ]]; then
  SDK_DIR="$ANDROID_SDK_ROOT"
elif [[ -n "${ANDROID_HOME:-}" ]]; then
  SDK_DIR="$ANDROID_HOME"
else
  fail_enabled_build "Android SDK not found, cannot build native danmaku mask."
fi

if [[ ! -d "$SDK_DIR" ]]; then
  fail_enabled_build "Android SDK directory does not exist: $SDK_DIR"
fi

NDK_ROOT="$(find "$SDK_DIR/ndk" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort -V | tail -1)"
if [[ -z "$NDK_ROOT" || ! -d "$NDK_ROOT" ]]; then
  fail_enabled_build "Android NDK not found under $SDK_DIR/ndk, cannot build native danmaku mask."
fi

case "$(uname -s)" in
  Linux)
    HOST_TAG="linux-x86_64"
    ;;
  Darwin)
    HOST_TAG="darwin-x86_64"
    if [[ ! -d "$NDK_ROOT/toolchains/llvm/prebuilt/$HOST_TAG" &&
      -d "$NDK_ROOT/toolchains/llvm/prebuilt/darwin-aarch64" ]]; then
      HOST_TAG="darwin-aarch64"
    fi
    ;;
  MINGW*|MSYS*|CYGWIN*)
    HOST_TAG="windows-x86_64"
    ;;
  *)
    fail_enabled_build "Unsupported host for Android NDK prebuilt toolchain: $(uname -s)"
    ;;
esac
TOOLCHAIN_BIN="$NDK_ROOT/toolchains/llvm/prebuilt/$HOST_TAG/bin"
if [[ ! -d "$TOOLCHAIN_BIN" ]]; then
  fail_enabled_build "Android NDK llvm toolchain not found: $TOOLCHAIN_BIN"
fi

mkdir -p "$OUT_DIR"
BUILD_ROOT="$(cd "$OUT_DIR/.." && pwd)"
TARGET_DIR="$BUILD_ROOT/rust-target"
built_any=0

targets=(
  "arm64-v8a:aarch64-linux-android:aarch64-linux-android23-clang"
  "armeabi-v7a:armv7-linux-androideabi:armv7a-linux-androideabi23-clang"
  "x86_64:x86_64-linux-android:x86_64-linux-android23-clang"
)

for spec in "${targets[@]}"; do
  IFS=":" read -r abi target linker <<<"$spec"
  if ! rustup target list --installed | grep -qx "$target"; then
    warn "Rust target $target is not installed, skip ABI $abi."
    continue
  fi

  env_key="$(printf '%s' "$target" | tr '[:lower:]-' '[:upper:]_')"
  linker_path="$TOOLCHAIN_BIN/$linker"
  if [[ ! -x "$linker_path" ]]; then
    warn "Android linker not found: $linker_path"
    continue
  fi

  mkdir -p "$OUT_DIR/$abi"
  env "CARGO_TARGET_${env_key}_LINKER=$linker_path" \
    cargo build \
      --manifest-path "$CRATE_DIR/Cargo.toml" \
      --target "$target" \
      --release \
      --target-dir "$TARGET_DIR"

  cp "$TARGET_DIR/$target/release/libnolive_danmaku_mask.so" \
    "$OUT_DIR/$abi/libnolive_danmaku_mask.so"
  built_any=1
done

if [[ "$built_any" -eq 0 ]]; then
  fail_enabled_build "No native danmaku mask artifacts were built."
fi
