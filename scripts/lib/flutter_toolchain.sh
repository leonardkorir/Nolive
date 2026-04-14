#!/usr/bin/env bash

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "source this file instead of executing it" >&2
  exit 1
fi

NOLIVE_FLUTTER_TOOLCHAIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NOLIVE_FLUTTER_TOOLCHAIN_ROOT="$(
  cd "$NOLIVE_FLUTTER_TOOLCHAIN_DIR/../.." && pwd
)"

nolive_prepend_path_once() {
  local path_entry="$1"
  if [[ -z "$path_entry" || ! -d "$path_entry" ]]; then
    return 1
  fi
  case ":${PATH:-}:" in
    *":$path_entry:"*) ;;
    *)
      if [[ -n "${PATH:-}" ]]; then
        PATH="$path_entry:$PATH"
      else
        PATH="$path_entry"
      fi
      export PATH
      ;;
  esac
}

nolive_add_flutter_bin_candidate() {
  local bin_dir="$1"
  if [[ -z "$bin_dir" || ! -x "$bin_dir/flutter" ]]; then
    return 1
  fi
  nolive_prepend_path_once "$bin_dir"
}

nolive_add_flutter_root_candidate() {
  local root_dir="$1"
  if [[ -z "$root_dir" ]]; then
    return 1
  fi
  nolive_add_flutter_bin_candidate "$root_dir/bin"
}

nolive_read_flutter_root_from_export_file() {
  local export_file="$1"
  if [[ ! -f "$export_file" ]]; then
    return 1
  fi
  sed -n 's/^export "FLUTTER_ROOT=\(.*\)"$/\1/p' "$export_file" | head -n 1
}

nolive_resolve_flutter_toolchain() {
  local flutter_root_from_export
  local export_file

  if command -v flutter >/dev/null 2>&1; then
    nolive_prepend_path_once "$(dirname "$(command -v flutter)")"
  fi

  if command -v flutter >/dev/null 2>&1 && command -v dart >/dev/null 2>&1; then
    return 0
  fi

  nolive_add_flutter_root_candidate "${FLUTTER_ROOT:-}"
  nolive_add_flutter_root_candidate "${FLUTTER_HOME:-}"
  nolive_add_flutter_root_candidate "${FVM_FLUTTER_SDK:-}"
  nolive_add_flutter_bin_candidate "${FLUTTER_BIN:-}"

  if [[ -n "${HOME:-}" ]]; then
    nolive_add_flutter_root_candidate "$HOME/flutter"
    nolive_add_flutter_root_candidate "$HOME/.local/share/flutter"
    nolive_add_flutter_root_candidate "$HOME/development/flutter"
  fi

  for export_file in \
    "$NOLIVE_FLUTTER_TOOLCHAIN_ROOT/apps/main_app/ios/Flutter/flutter_export_environment.sh" \
    "$NOLIVE_FLUTTER_TOOLCHAIN_ROOT/apps/main_app/macos/Flutter/ephemeral/flutter_export_environment.sh"; do
    flutter_root_from_export="$(
      nolive_read_flutter_root_from_export_file "$export_file" || true
    )"
    nolive_add_flutter_root_candidate "$flutter_root_from_export"
  done

  if command -v flutter >/dev/null 2>&1; then
    nolive_prepend_path_once "$(dirname "$(command -v flutter)")"
  fi

  command -v flutter >/dev/null 2>&1 && command -v dart >/dev/null 2>&1
}

require_flutter_toolchain() {
  nolive_resolve_flutter_toolchain || true

  if ! command -v flutter >/dev/null 2>&1; then
    echo "flutter not found; checked PATH, FLUTTER_ROOT, \$HOME/flutter, \$HOME/.local/share/flutter, and app export files" >&2
    return 1
  fi

  nolive_prepend_path_once "$(dirname "$(command -v flutter)")"

  if ! command -v dart >/dev/null 2>&1; then
    echo "dart not found; Flutter SDK was resolved but dart is still unavailable from $(dirname "$(command -v flutter)")" >&2
    return 1
  fi
}
