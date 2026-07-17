#!/usr/bin/env bash
# Persistent Linux log capture for Nolive first-pass testing.
#
# Survives app crashes/flash-exits: collectors run *outside* the app process.
# Captures:
#   - AppLog files (~/.local/share/app.nolive.desktop/logs/)
#   - process stdout/stderr (line-buffered, append across restarts)
#   - launch/exit codes and timestamps
#   - optional auto-restart after crash for soak testing
#
# Usage:
#   scripts/manage_linux_log_capture.sh start [--restart] [--debug] [--note "first test"]
#   scripts/manage_linux_log_capture.sh status
#   scripts/manage_linux_log_capture.sh stop          # stop collectors + pack tarball
#   scripts/manage_linux_log_capture.sh pack          # pack without stopping (if still running)
#   scripts/manage_linux_log_capture.sh tail          # follow merged session log
#
# Session root (default): ~/nolive-linux-capture/
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_ID="${NOLIVE_APP_ID:-app.nolive.desktop}"
SUPPORT_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/${APP_ID}"
APP_LOG_DIR="${SUPPORT_DIR}/logs"
CAPTURE_ROOT="${NOLIVE_CAPTURE_ROOT:-$HOME/nolive-linux-capture}"
BUNDLE_REL="${ROOT_DIR}/apps/main_app/build/linux/x64/release/bundle"
BUNDLE_DBG="${ROOT_DIR}/apps/main_app/build/linux/x64/debug/bundle"
STATE_DIR="${CAPTURE_ROOT}/.state"
CURRENT_LINK="${CAPTURE_ROOT}/current"

usage() {
  cat <<'EOF'
Usage:
  scripts/manage_linux_log_capture.sh start [--restart] [--debug] [--note TEXT]
  scripts/manage_linux_log_capture.sh status
  scripts/manage_linux_log_capture.sh stop
  scripts/manage_linux_log_capture.sh pack
  scripts/manage_linux_log_capture.sh tail

Options (start):
  --restart   Auto-relaunch nolive after crash/exit (soak / multi-crash testing)
  --debug     Prefer debug bundle if present
  --note TEXT Free-text note stored in the session meta

Env:
  NOLIVE_CAPTURE_ROOT   Capture root (default: ~/nolive-linux-capture)
  NOLIVE_APP_ID         App id for support dir (default: app.nolive.desktop)
  DISPLAY               Required for GUI
EOF
}

ts() { date -Iseconds; }

resolve_bundle() {
  local prefer_debug="${1:-0}"
  if [[ "$prefer_debug" -eq 1 && -x "$BUNDLE_DBG/nolive" ]]; then
    echo "$BUNDLE_DBG"
    return
  fi
  if [[ -x "$BUNDLE_REL/nolive" ]]; then
    echo "$BUNDLE_REL"
    return
  fi
  if [[ -x "$BUNDLE_DBG/nolive" ]]; then
    echo "$BUNDLE_DBG"
    return
  fi
  echo ""
}

is_pid_alive() {
  local pid="${1:-}"
  [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null
}

read_state() {
  local key="$1"
  local f="${STATE_DIR}/${key}"
  [[ -f "$f" ]] && cat "$f" || true
}

write_state() {
  local key="$1"
  local val="$2"
  mkdir -p "$STATE_DIR"
  printf '%s\n' "$val" >"${STATE_DIR}/${key}"
}

session_dir() {
  if [[ -L "$CURRENT_LINK" || -d "$CURRENT_LINK" ]]; then
    readlink -f "$CURRENT_LINK" 2>/dev/null || echo "$CURRENT_LINK"
  else
    echo ""
  fi
}

log_event() {
  local session="$1"
  shift
  mkdir -p "$session"
  printf '%s %s\n' "$(ts)" "$*" | tee -a "$session/events.log" >/dev/null
}

start_log_sync() {
  local session="$1"
  local sync_log="$session/process/log-sync.log"
  mkdir -p "$session/app-logs" "$session/process"
  # Continuous mirror of AppLog directory (survives app death).
  nohup bash -c "
    set +e
    while true; do
      if [[ -d '${APP_LOG_DIR}' ]]; then
        mkdir -p '${session}/app-logs'
        # Prefer rsync; fall back to cp.
        if command -v rsync >/dev/null 2>&1; then
          rsync -a --include='nolive-mobile-*.log' --exclude='*' '${APP_LOG_DIR}/' '${session}/app-logs/' 2>>'${sync_log}'
        else
          find '${APP_LOG_DIR}' -maxdepth 1 -type f -name 'nolive-mobile-*.log' -exec cp -a {} '${session}/app-logs/' \\; 2>>'${sync_log}'
        fi
      fi
      sleep 2
    done
  " >>"$sync_log" 2>&1 &
  write_state sync_pid "$!"
  echo "$!" >"$session/process/sync.pid"
}

start_app_supervisor() {
  local session="$1"
  local bundle="$2"
  local restart="$3"
  local out="$session/process/stdout-stderr.log"
  local launches="$session/process/launches.log"
  local exits="$session/process/exit-codes.log"
  mkdir -p "$session/process"

  # Supervisor is outside the app: crash does not kill capture.
  nohup bash -c "
    set +e
    export DISPLAY='${DISPLAY:-:0}'
    export WAYLAND_DISPLAY='${WAYLAND_DISPLAY:-}'
    export XDG_RUNTIME_DIR='${XDG_RUNTIME_DIR:-}'
    # Line-buffered if stdbuf available.
    RUN_PREFIX=''
    if command -v stdbuf >/dev/null 2>&1; then
      RUN_PREFIX='stdbuf -oL -eL'
    fi
    attempt=0
    while true; do
      attempt=\$((attempt + 1))
      echo \"\$(date -Iseconds) launch attempt=\$attempt bundle='${bundle}'\" >>'${launches}'
      echo \"\$(date -Iseconds) EVENT launch attempt=\$attempt\" >>'${session}/events.log'
      cd '${bundle}' || exit 1
      # shellcheck disable=SC2086
      \$RUN_PREFIX ./nolive >>'${out}' 2>&1 &
      app_pid=\$!
      echo \"\$app_pid\" >'${session}/process/app.pid'
      echo \"\$app_pid\" >'${STATE_DIR}/app_pid'
      wait \"\$app_pid\"
      code=\$?
      echo \"\$(date -Iseconds) exit attempt=\$attempt code=\$code\" >>'${exits}'
      echo \"\$(date -Iseconds) EVENT exit code=\$code attempt=\$attempt\" >>'${session}/events.log'
      # Final sync after exit/crash.
      if [[ -d '${APP_LOG_DIR}' ]]; then
        mkdir -p '${session}/app-logs'
        if command -v rsync >/dev/null 2>&1; then
          rsync -a --include='nolive-mobile-*.log' --exclude='*' '${APP_LOG_DIR}/' '${session}/app-logs/' 2>/dev/null
        else
          find '${APP_LOG_DIR}' -maxdepth 1 -type f -name 'nolive-mobile-*.log' -exec cp -a {} '${session}/app-logs/' \\; 2>/dev/null
        fi
      fi
      if [[ '${restart}' != '1' ]]; then
        echo \"\$(date -Iseconds) EVENT supervisor stop (no --restart)\" >>'${session}/events.log'
        break
      fi
      # Back off and hard-stop after repeated native crashes (e.g. 139=SIGSEGV)
      # so a bad post-sync boot loop cannot spin forever.
      consecutive_crash=0
      if [[ \"\$code\" -ge 128 ]]; then
        consecutive_crash=\$((\${consecutive_crash:-0} + 1))
      else
        consecutive_crash=0
      fi
      # Persist consecutive counter in a side file (subshell-safe).
      cfile='${session}/process/consecutive-native-crashes'
      if [[ \"\$code\" -ge 128 ]]; then
        c=\$(cat \"\$cfile\" 2>/dev/null || echo 0)
        c=\$((c + 1))
        echo \"\$c\" >\"\$cfile\"
      else
        echo 0 >\"\$cfile\"
        c=0
      fi
      if [[ \"\$c\" -ge 5 ]]; then
        echo \"\$(date -Iseconds) EVENT supervisor stop after \$c consecutive native crashes (last code=\$code)\" >>'${session}/events.log'
        break
      fi
      backoff=\$((2 + c * 2))
      if [[ \"\$backoff\" -gt 30 ]]; then backoff=30; fi
      echo \"\$(date -Iseconds) EVENT auto-restart in \${backoff}s (native_streak=\$c)\" >>'${session}/events.log'
      sleep \"\$backoff\"
    done
  " >>"$session/process/supervisor.log" 2>&1 &
  write_state supervisor_pid "$!"
  echo "$!" >"$session/process/supervisor.pid"
}

cmd_start() {
  local restart=0 prefer_debug=0 note=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --restart) restart=1; shift ;;
      --debug) prefer_debug=1; shift ;;
      --note) note="${2:-}"; shift 2 ;;
      *)
        echo "unknown start option: $1" >&2
        usage
        exit 2
        ;;
    esac
  done

  if [[ -z "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]]; then
    echo "WARN: DISPLAY/WAYLAND_DISPLAY empty; GUI may fail" >&2
  fi

  local existing_sup
  existing_sup="$(read_state supervisor_pid)"
  if is_pid_alive "$existing_sup"; then
    echo "capture already running (supervisor_pid=$existing_sup)"
    echo "session=$(session_dir)"
    echo "use: scripts/manage_linux_log_capture.sh status | stop"
    exit 1
  fi

  local bundle
  bundle="$(resolve_bundle "$prefer_debug")"
  if [[ -z "$bundle" ]]; then
    echo "no built nolive found. Build first:" >&2
    echo "  scripts/build_main_app.sh linux" >&2
    exit 1
  fi

  mkdir -p "$CAPTURE_ROOT" "$STATE_DIR"
  local stamp session
  stamp="$(date +%Y%m%d-%H%M%S)"
  session="${CAPTURE_ROOT}/session-${stamp}"
  mkdir -p "$session"/{meta,app-logs,process}
  ln -sfn "$session" "$CURRENT_LINK"

  {
    echo "stamp=$stamp"
    echo "started=$(ts)"
    echo "note=${note}"
    echo "restart=${restart}"
    echo "bundle=${bundle}"
    echo "display=${DISPLAY:-}"
    echo "wayland=${WAYLAND_DISPLAY:-}"
    echo "app_log_dir=${APP_LOG_DIR}"
    echo "host=$(hostname 2>/dev/null || true)"
    echo "user=${USER:-}"
    uname -a
    command -v mpv >/dev/null && mpv --version 2>&1 | head -1 || echo "mpv=missing"
  } >"$session/meta/environment.txt"

  # Optional core dumps for hard crashes (session-local).
  mkdir -p "$session/process/cores"
  # shellcheck disable=SC2034
  echo "$session/process/cores/core.%e.%p.%t" >"$session/meta/core-pattern-hint.txt"

  write_state session "$session"
  write_state restart "$restart"
  start_log_sync "$session"
  start_app_supervisor "$session" "$bundle" "$restart"

  log_event "$session" "EVENT capture started restart=$restart bundle=$bundle note=${note}"
  cat <<EOF
capture STARTED
  session : $session
  current : $CURRENT_LINK
  app     : launched under supervisor (stdout/stderr → process/stdout-stderr.log)
  applog  : mirrored every 2s from $APP_LOG_DIR
  restart : $restart  (1 = auto relaunch after crash)

Commands:
  scripts/manage_linux_log_capture.sh status
  scripts/manage_linux_log_capture.sh tail
  scripts/manage_linux_log_capture.sh stop    # stop + pack tarball for analysis
EOF
}

cmd_status() {
  local session sup app sync
  session="$(session_dir)"
  sup="$(read_state supervisor_pid)"
  app="$(read_state app_pid)"
  sync="$(read_state sync_pid)"
  echo "capture_root=$CAPTURE_ROOT"
  echo "session=${session:-none}"
  echo "supervisor_pid=${sup:-} alive=$(is_pid_alive "${sup:-}" && echo yes || echo no)"
  echo "sync_pid=${sync:-} alive=$(is_pid_alive "${sync:-}" && echo yes || echo no)"
  echo "app_pid=${app:-} alive=$(is_pid_alive "${app:-}" && echo yes || echo no)"
  if [[ -n "$session" && -d "$session" ]]; then
    echo "events_tail:"
    tail -n 8 "$session/events.log" 2>/dev/null || true
    echo "stdout_tail:"
    tail -n 5 "$session/process/stdout-stderr.log" 2>/dev/null || true
    echo "app_logs:"
    ls -lh "$session/app-logs" 2>/dev/null || true
  fi
}

cmd_tail() {
  local session
  session="$(session_dir)"
  if [[ -z "$session" ]]; then
    echo "no active session" >&2
    exit 1
  fi
  # Follow process log + newest app log if present.
  local files=("$session/process/stdout-stderr.log" "$session/events.log")
  local newest
  newest="$(ls -t "$session/app-logs"/nolive-mobile-*.log 2>/dev/null | head -1 || true)"
  [[ -n "$newest" ]] && files+=("$newest")
  echo "following: ${files[*]}"
  tail -n 50 -F "${files[@]}"
}

pack_session() {
  local session="$1"
  local out_dir="${2:-$CAPTURE_ROOT}"
  mkdir -p "$out_dir"
  # Final mirror before pack.
  if [[ -d "$APP_LOG_DIR" ]]; then
    mkdir -p "$session/app-logs"
    if command -v rsync >/dev/null 2>&1; then
      rsync -a --include='nolive-mobile-*.log' --exclude='*' "$APP_LOG_DIR/" "$session/app-logs/" 2>/dev/null || true
    else
      find "$APP_LOG_DIR" -maxdepth 1 -type f -name 'nolive-mobile-*.log' -exec cp -a {} "$session/app-logs/" \; 2>/dev/null || true
    fi
  fi
  local stamp name archive
  stamp="$(basename "$session" | sed 's/^session-//')"
  name="nolive-linux-capture-${stamp}.tar.gz"
  archive="${out_dir%/}/${name}"
  tar -C "$(dirname "$session")" -czf "$archive" "$(basename "$session")"
  echo "$archive"
}

cmd_pack() {
  local session
  session="$(session_dir)"
  if [[ -z "$session" || ! -d "$session" ]]; then
    echo "no session to pack" >&2
    exit 1
  fi
  local archive
  archive="$(pack_session "$session")"
  echo "packed: $archive"
  tar -tzf "$archive" | head -30
}

cmd_stop() {
  local session sup app sync
  session="$(session_dir)"
  sup="$(read_state supervisor_pid)"
  app="$(read_state app_pid)"
  sync="$(read_state sync_pid)"

  if [[ -n "$session" ]]; then
    log_event "$session" "EVENT capture stopping"
  fi

  # Stop app first, then supervisor, then sync.
  if is_pid_alive "${app:-}"; then
    kill "$app" 2>/dev/null || true
    sleep 1
    kill -9 "$app" 2>/dev/null || true
  fi
  # Also kill any stray nolive from this session pattern.
  pkill -x nolive 2>/dev/null || true

  if is_pid_alive "${sup:-}"; then
    kill "$sup" 2>/dev/null || true
    sleep 0.5
    kill -9 "$sup" 2>/dev/null || true
  fi
  if is_pid_alive "${sync:-}"; then
    kill "$sync" 2>/dev/null || true
    sleep 0.2
    kill -9 "$sync" 2>/dev/null || true
  fi

  rm -f "${STATE_DIR}/supervisor_pid" "${STATE_DIR}/app_pid" "${STATE_DIR}/sync_pid" 2>/dev/null || true

  if [[ -n "$session" && -d "$session" ]]; then
    log_event "$session" "EVENT capture stopped"
    local archive
    archive="$(pack_session "$session")"
    echo "capture STOPPED"
    echo "  session : $session"
    echo "  packed  : $archive"
    echo "Share the tarball for crash/playback analysis."
  else
    echo "capture STOPPED (no session dir)"
  fi
}

main() {
  local cmd="${1:-}"
  shift || true
  case "$cmd" in
    start) cmd_start "$@" ;;
    stop) cmd_stop "$@" ;;
    status) cmd_status "$@" ;;
    pack) cmd_pack "$@" ;;
    tail) cmd_tail "$@" ;;
    -h|--help|help|"") usage ;;
    *)
      echo "unknown command: $cmd" >&2
      usage
      exit 2
      ;;
  esac
}

main "$@"
