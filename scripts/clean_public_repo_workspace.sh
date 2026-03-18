#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

remove_path() {
  local relative_path="$1"
  local absolute_path="$ROOT_DIR/$relative_path"
  if [[ -e "$absolute_path" ]]; then
    rm -rf "$absolute_path"
    echo "removed $relative_path"
  fi
}

remove_file_matches() {
  local pattern="$1"
  while IFS= read -r match; do
    [[ -n "$match" ]] || continue
    rm -f "$match"
    echo "removed ${match#"$ROOT_DIR"/}"
  done < <(find "$ROOT_DIR" -type f -name "$pattern" -print)
}

remove_dir_matches() {
  local pattern="$1"
  while IFS= read -r match; do
    [[ -n "$match" ]] || continue
    rm -rf "$match"
    echo "removed ${match#"$ROOT_DIR"/}"
  done < <(find "$ROOT_DIR" -type d -name "$pattern" -print)
}

remove_path ".dart_tool"
remove_path ".pub"
remove_path ".pub-cache"
remove_path ".flutter-plugins"
remove_path ".flutter-plugins-dependencies"
remove_path ".packages"
remove_path "coverage"
remove_path "node_modules"
remove_path ".idea"
remove_path ".vscode"
remove_path ".ace-tool"
remove_path ".tmp-device"
remove_path ".tmp-branding"

remove_dir_matches ".dart_tool"
remove_dir_matches "build"
remove_dir_matches ".gradle"
remove_dir_matches ".kotlin"
remove_dir_matches ".idea"
remove_dir_matches "ephemeral"

remove_file_matches ".flutter-plugins"
remove_file_matches ".flutter-plugins-dependencies"
remove_file_matches "pubspec_overrides.yaml"
remove_file_matches "local.properties"
remove_file_matches "key.properties"
remove_file_matches "Generated.xcconfig"
remove_file_matches "flutter_export_environment.sh"
remove_file_matches "GeneratedPluginRegistrant.java"
remove_file_matches "GeneratedPluginRegistrant.h"
remove_file_matches "GeneratedPluginRegistrant.m"
remove_file_matches "*.apk"
remove_file_matches "*.aab"
remove_file_matches "*.iml"
remove_file_matches "*.log"

remove_path "apps/main_app/android/keystore"

echo "public workspace cleanup complete"
