#!/usr/bin/env bash
# Collect Nolive Linux desktop logs for offline analysis.
#
# Usage:
#   scripts/collect_linux_logs.sh              # pack existing app logs
#   scripts/collect_linux_logs.sh --run        # launch app with stdout/stderr capture, then pack
#   scripts/collect_linux_logs.sh --run --note "twitch enter room black screen"
#
# Output: ~/nolive-linux-logs-YYYYMMDD-HHMMSS.tar.gz  (or $OUT_DIR if set)
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_ID="${NOLIVE_APP_ID:-app.nolive.desktop}"
SUPPORT_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/${APP_ID}"
LOG_DIR="${SUPPORT_DIR}/logs"
BUNDLE_REL="${ROOT_DIR}/apps/main_app/build/linux/x64/release/bundle"
BUNDLE_DBG="${ROOT_DIR}/apps/main_app/build/linux/x64/debug/bundle"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT_DIR="${OUT_DIR:-$HOME}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/nolive-log-collect.XXXXXX")"
NOTE=""
DO_RUN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --run) DO_RUN=1; shift ;;
    --note) NOTE="${2:-}"; shift 2 ;;
    --out-dir) OUT_DIR="${2:-}"; shift 2 ;;
    -h|--help)
      sed -n '2,12p' "$0"
      exit 0
      ;;
    *)
      echo "unknown arg: $1" >&2
      exit 2
      ;;
  esac
done

mkdir -p "$WORK/meta" "$WORK/app-logs" "$WORK/session"

{
  echo "stamp=$STAMP"
  echo "host=$(hostname 2>/dev/null || true)"
  echo "user=$USER"
  echo "display=${DISPLAY:-}"
  echo "wayland=${WAYLAND_DISPLAY:-}"
  echo "uname=$(uname -a)"
  echo "app_id=$APP_ID"
  echo "support_dir=$SUPPORT_DIR"
  echo "log_dir=$LOG_DIR"
  echo "note=${NOTE}"
  command -v mpv >/dev/null && mpv --version 2>&1 | head -1 || echo "mpv=missing"
  command -v pkg-config >/dev/null && {
    echo "webkit=$(pkg-config --modversion webkit2gtk-4.1 2>/dev/null || echo n/a)"
    echo "libsecret=$(pkg-config --modversion libsecret-1 2>/dev/null || echo n/a)"
  }
} >"$WORK/meta/environment.txt"

if [[ -d "$LOG_DIR" ]]; then
  # Copy last ~7 rotating files (AppLog keeps max 7).
  find "$LOG_DIR" -maxdepth 1 -type f -name 'nolive-mobile-*.log' -print0 \
    | sort -z \
    | tail -z -n 10 \
    | xargs -0 -r -I{} cp -a {} "$WORK/app-logs/" || true
  ls -la "$LOG_DIR" >"$WORK/meta/log-dir-listing.txt" 2>/dev/null || true
else
  echo "log dir missing: $LOG_DIR" >"$WORK/meta/log-dir-missing.txt"
fi

# Optional: capture one interactive session (stdout/stderr of the process).
if [[ "$DO_RUN" -eq 1 ]]; then
  BUNDLE=""
  if [[ -x "$BUNDLE_REL/nolive" ]]; then
    BUNDLE="$BUNDLE_REL"
  elif [[ -x "$BUNDLE_DBG/nolive" ]]; then
    BUNDLE="$BUNDLE_DBG"
  else
    echo "no built nolive found under release/debug bundle; run scripts/build_main_app.sh linux first" >&2
    exit 1
  fi
  echo "launching $BUNDLE/nolive (close the window or Ctrl+C to finish capture)..."
  SESSION_LOG="$WORK/session/stdout-stderr.log"
  (
    cd "$BUNDLE"
    # shellcheck disable=SC2086
    ./nolive 2>&1 | tee "$SESSION_LOG"
  ) || true
  # After exit, copy any newly written app logs again.
  if [[ -d "$LOG_DIR" ]]; then
    find "$LOG_DIR" -maxdepth 1 -type f -name 'nolive-mobile-*.log' -print0 \
      | sort -z \
      | tail -z -n 10 \
      | xargs -0 -r -I{} cp -a {} "$WORK/app-logs/" || true
  fi
fi

ARCHIVE="${OUT_DIR%/}/nolive-linux-logs-${STAMP}.tar.gz"
mkdir -p "$OUT_DIR"
tar -C "$WORK" -czf "$ARCHIVE" .
rm -rf "$WORK"

echo "packed: $ARCHIVE"
echo "contents:"
tar -tzf "$ARCHIVE" | head -40
echo "..."
echo "Share this tarball for analysis (cookies/tokens in logs are partially redacted by AppLog)."
