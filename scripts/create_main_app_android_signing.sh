#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ANDROID_DIR="$ROOT_DIR/apps/main_app/android"
KEYSTORE_DIR="$ANDROID_DIR/keystore"
KEYSTORE_PATH="$KEYSTORE_DIR/nolive-release.jks"
KEY_PROPERTIES_PATH="$ANDROID_DIR/key.properties"
KEY_ALIAS="${ANDROID_KEY_ALIAS:-nolive-upload}"
DNAME="${ANDROID_KEY_DNAME:-CN=Nolive, OU=Mobile, O=Nolive, L=Shanghai, ST=Shanghai, C=CN}"
VALIDITY_DAYS="${ANDROID_KEY_VALIDITY_DAYS:-36500}"
KEY_SIZE="${ANDROID_KEY_SIZE:-4096}"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing required command: $1" >&2
    exit 1
  }
}

generate_password() {
  python3 - <<'PY'
import secrets
print(secrets.token_urlsafe(24))
PY
}

backup_existing_key_properties_if_needed() {
  if [[ ! -f "$KEY_PROPERTIES_PATH" ]]; then
    return
  fi

  local current_store_file
  current_store_file="$(sed -n 's/^storeFile=//p' "$KEY_PROPERTIES_PATH" | head -n1)"
  if grep -Fq 'replace-me' "$KEY_PROPERTIES_PATH" || [[ "$current_store_file" == *debug.keystore* ]]; then
    local backup_path="${KEY_PROPERTIES_PATH}.bak.$(date +%Y%m%d-%H%M%S)"
    mv "$KEY_PROPERTIES_PATH" "$backup_path"
    echo "backed up existing signing config to $backup_path"
    return
  fi

  echo "existing non-debug signing config found: $KEY_PROPERTIES_PATH" >&2
  echo "refusing to overwrite an existing release signing config" >&2
  exit 1
}

require_cmd keytool
require_cmd python3

mkdir -p "$KEYSTORE_DIR"
backup_existing_key_properties_if_needed

if [[ -f "$KEYSTORE_PATH" ]]; then
  echo "existing keystore found: $KEYSTORE_PATH" >&2
  echo "refusing to overwrite the current release keystore" >&2
  exit 1
fi

STORE_PASSWORD="${ANDROID_STORE_PASSWORD:-$(generate_password)}"
KEY_PASSWORD="${ANDROID_KEY_PASSWORD:-$STORE_PASSWORD}"

keytool -genkeypair \
  -v \
  -keystore "$KEYSTORE_PATH" \
  -storepass "$STORE_PASSWORD" \
  -alias "$KEY_ALIAS" \
  -keypass "$KEY_PASSWORD" \
  -keyalg RSA \
  -keysize "$KEY_SIZE" \
  -validity "$VALIDITY_DAYS" \
  -dname "$DNAME" >/dev/null

cat > "$KEY_PROPERTIES_PATH" <<EOF
storePassword=$STORE_PASSWORD
keyPassword=$KEY_PASSWORD
keyAlias=$KEY_ALIAS
storeFile=../keystore/nolive-release.jks
EOF

chmod 600 "$KEYSTORE_PATH" "$KEY_PROPERTIES_PATH"

echo "generated Android release signing materials:"
echo "- keystore: $KEYSTORE_PATH"
echo "- key.properties: $KEY_PROPERTIES_PATH"
echo "- alias: $KEY_ALIAS"
echo
echo "back up both files securely before publishing any store build."
echo "future updates must keep using the same keystore."
echo
keytool -list -v \
  -keystore "$KEYSTORE_PATH" \
  -storepass "$STORE_PASSWORD" \
  -alias "$KEY_ALIAS" | sed -n '1,24p'
