#!/usr/bin/env bash
set -euo pipefail

warn() {
  echo "[nolive-rust] $*" >&2
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
  warn "cargo not found, skip native danmaku mask build."
  exit 0
fi

if ! command -v rustup >/dev/null 2>&1; then
  warn "rustup not found, skip native danmaku mask build."
  exit 0
fi

if [[ -n "$SDK_DIR_INPUT" ]]; then
  SDK_DIR="$SDK_DIR_INPUT"
elif [[ -n "${ANDROID_SDK_ROOT:-}" ]]; then
  SDK_DIR="$ANDROID_SDK_ROOT"
elif [[ -n "${ANDROID_HOME:-}" ]]; then
  SDK_DIR="$ANDROID_HOME"
else
  warn "Android SDK not found, skip native danmaku mask build."
  exit 0
fi

if [[ ! -d "$SDK_DIR" ]]; then
  warn "Android SDK directory does not exist: $SDK_DIR"
  exit 0
fi

NDK_ROOT="$(find "$SDK_DIR/ndk" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort -V | tail -1)"
if [[ -z "$NDK_ROOT" || ! -d "$NDK_ROOT" ]]; then
  warn "Android NDK not found under $SDK_DIR/ndk, skip native danmaku mask build."
  exit 0
fi

HOST_TAG="linux-x86_64"
TOOLCHAIN_BIN="$NDK_ROOT/toolchains/llvm/prebuilt/$HOST_TAG/bin"
if [[ ! -d "$TOOLCHAIN_BIN" ]]; then
  warn "Android NDK llvm toolchain not found: $TOOLCHAIN_BIN"
  exit 0
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
  warn "No native danmaku mask artifacts were built; Android runtime will fall back to Dart."
fi
