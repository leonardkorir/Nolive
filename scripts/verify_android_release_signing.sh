#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/apps/main_app"
ANDROID_DIR="$APP_DIR/android"
APP_MODULE_DIR="$ANDROID_DIR/app"
KEY_PROPERTIES_PATH="$ANDROID_DIR/key.properties"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing required command: $1" >&2
    exit 1
  }
}

key_properties_value() {
  local key="$1"
  sed -n "s/^${key}=//p" "$KEY_PROPERTIES_PATH" | head -n1
}

resolve_store_file() {
  local raw_path="$1"
  python3 - "$raw_path" "$APP_MODULE_DIR" <<'PY'
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

require_cmd keytool
require_cmd python3

if [[ ! -f "$KEY_PROPERTIES_PATH" ]]; then
  echo "missing Android signing file: $KEY_PROPERTIES_PATH" >&2
  exit 1
fi

store_password="$(key_properties_value storePassword)"
key_password="$(key_properties_value keyPassword)"
key_alias="$(key_properties_value keyAlias)"
raw_store_file="$(key_properties_value storeFile)"

if [[ -z "$store_password" || -z "$key_password" || -z "$key_alias" || -z "$raw_store_file" ]]; then
  echo "Android signing config is incomplete: $KEY_PROPERTIES_PATH" >&2
  exit 1
fi

store_file="$(resolve_store_file "$raw_store_file")"
if [[ ! -f "$store_file" ]]; then
  echo "Android keystore not found: $store_file" >&2
  exit 1
fi
if [[ "$store_file" == *debug.keystore || "$key_alias" == "androiddebugkey" ]]; then
  echo "debug keystore/debug alias is not allowed for release verification" >&2
  exit 1
fi

keystore_sha256="$(
  keytool -list -v \
    -keystore "$store_file" \
    -storepass "$store_password" \
    -alias "$key_alias" \
    -keypass "$key_password" |
    sed -n 's/^[[:space:]]*SHA256: //p' | head -n1
)"

if [[ -z "$keystore_sha256" ]]; then
  echo "failed to read keystore certificate fingerprint" >&2
  exit 1
fi

artifacts=("$@")
if [[ "${#artifacts[@]}" -eq 0 ]]; then
  default_artifacts=(
    "$APP_DIR/build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk"
    "$APP_DIR/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk"
    "$APP_DIR/build/app/outputs/flutter-apk/app-x86_64-release.apk"
    "$APP_DIR/build/app/outputs/bundle/release/app-release.aab"
  )
  for artifact in "${default_artifacts[@]}"; do
    if [[ -f "$artifact" ]]; then
      artifacts+=("$artifact")
    fi
  done
fi

if [[ "${#artifacts[@]}" -eq 0 ]]; then
  echo "no Android release artifacts found to verify" >&2
  exit 1
fi

for artifact in "${artifacts[@]}"; do
  if [[ ! -f "$artifact" ]]; then
    echo "missing Android artifact: $artifact" >&2
    exit 1
  fi

  cert_output="$(keytool -printcert -jarfile "$artifact")"
  artifact_owner="$(printf '%s\n' "$cert_output" | sed -n 's/^Owner: //p' | head -n1)"
  artifact_sha256="$(printf '%s\n' "$cert_output" | sed -n 's/^[[:space:]]*SHA256: //p' | head -n1)"

  if [[ -z "$artifact_owner" || -z "$artifact_sha256" ]]; then
    echo "failed to read signing certificate from $artifact" >&2
    exit 1
  fi
  if [[ "$artifact_owner" == *"Android Debug"* ]]; then
    echo "artifact is still debug-signed: $artifact" >&2
    exit 1
  fi
  if [[ "$artifact_sha256" != "$keystore_sha256" ]]; then
    echo "artifact signer fingerprint does not match keystore: $artifact" >&2
    echo "expected: $keystore_sha256" >&2
    echo "actual:   $artifact_sha256" >&2
    exit 1
  fi

  echo "verified release signing: $artifact"
  echo "  owner:  $artifact_owner"
  echo "  sha256: $artifact_sha256"
done
