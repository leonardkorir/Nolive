#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REMOTE_DIR="/sdcard/Download/nolive-logs"
REMOTE_SCRIPT_DIR="/data/local/tmp"
PACKAGE_NAME="${PACKAGE_NAME:-app.nolive.mobile}"
REMOTE_APP_LOG_DIR="/sdcard/Android/data/${PACKAGE_NAME}/files/logs"
LOCAL_PULL_ROOT="${LOCAL_PULL_ROOT:-${ROOT_DIR}/artifacts/device-logs/live-capture}"
ANDROID_DEVICE_ID="${ANDROID_DEVICE_ID:-}"
REMOTE_LOGCAT_HEARTBEAT_FILE="${REMOTE_DIR}/current-logcat.heartbeat"
REMOTE_PERF_HEARTBEAT_FILE="${REMOTE_DIR}/current-perf.heartbeat"
REMOTE_LOGCAT_STATE_FILE="${REMOTE_DIR}/current-logcat.state"
REMOTE_PERF_STATE_FILE="${REMOTE_DIR}/current-perf.state"

usage() {
  cat <<'EOF'
Usage:
  scripts/manage_main_app_android_capture.sh start [--clean]
  scripts/manage_main_app_android_capture.sh stop
  scripts/manage_main_app_android_capture.sh status
  scripts/manage_main_app_android_capture.sh pull [local-dir]
  scripts/manage_main_app_android_capture.sh pull-app-logs [local-dir]

Environment:
  ANDROID_DEVICE_ID   Explicit adb device id when multiple devices are connected.
  PACKAGE_NAME        Android package name to capture. Default: app.nolive.mobile
  LOCAL_PULL_ROOT     Default local output root for pull commands.
EOF
}

require_adb() {
  if ! command -v adb >/dev/null 2>&1; then
    echo "adb not found; please install Android platform-tools first" >&2
    exit 1
  fi
}

select_device() {
  if [[ -n "${ANDROID_DEVICE_ID}" ]]; then
    adb_cmd=(adb -s "${ANDROID_DEVICE_ID}")
    return
  fi

  local device_count
  device_count="$(adb devices | awk 'NR>1 && $2=="device" {count++} END {print count+0}')"
  if [[ "${device_count}" -eq 0 ]]; then
    echo "no Android device detected; connect a phone or set ANDROID_DEVICE_ID" >&2
    exit 1
  fi
  if [[ "${device_count}" -gt 1 ]]; then
    echo "multiple Android devices detected; set ANDROID_DEVICE_ID explicitly" >&2
    adb devices
    exit 1
  fi

  ANDROID_DEVICE_ID="$(adb devices | awk 'NR>1 && $2=="device" {print $1; exit}')"
  adb_cmd=(adb -s "${ANDROID_DEVICE_ID}")
}

adb_shell() {
  "${adb_cmd[@]}" shell "$@"
}

strip_cr() {
  tr -d '\r'
}

remote_read_first_line() {
  local path="$1"
  adb_shell "sed -n '1p' '${path}' 2>/dev/null || true" | strip_cr
}

remote_read_trimmed() {
  local path="$1"
  adb_shell "cat '${path}' 2>/dev/null || true" |
    strip_cr |
    awk 'NF {print; exit}'
}

remote_file_exists() {
  local path="$1"
  adb_shell "[ -e '${path}' ]" >/dev/null 2>&1
}

remote_pid_running() {
  local pid="$1"
  [[ -n "${pid}" ]] || return 1
  adb_shell "ps -A | grep ' ${pid} ' >/dev/null 2>&1"
}

resolve_package_uid() {
  local output
  output="$(adb_shell "cmd package list packages -U '${PACKAGE_NAME}'" | strip_cr)"
  sed -n 's/.* uid:\([0-9][0-9]*\)$/\1/p' <<<"${output}"
}

write_remote_helper_scripts() {
  local tmp_dir log_script perf_script
  tmp_dir="$(mktemp -d)"

  log_script="${tmp_dir}/nolive-log-supervisor.sh"
  perf_script="${tmp_dir}/nolive-perf-sampler.sh"

  cat >"${log_script}" <<'EOF'
#!/system/bin/sh
OUT_LOG="$1"
SUPERVISOR_LOG="$2"
HEARTBEAT_FILE="$3"
STATE_FILE="$4"

heartbeat() {
  /system/bin/date '+%s' > "${HEARTBEAT_FILE}"
}

write_state() {
  printf '%s %s\n' "$(/system/bin/date '+%F %T')" "$1" > "${STATE_FILE}"
}

log_event() {
  echo "$(/system/bin/date '+%F %T') $1" >> "${SUPERVISOR_LOG}"
}

CLEANUP_DONE=0
cleanup() {
  RC="${1:-$?}"
  if [ "${CLEANUP_DONE}" = "1" ]; then
    return
  fi
  CLEANUP_DONE=1
  heartbeat
  write_state "supervisor-exit rc=${RC}"
  log_event "logcat supervisor exiting rc=${RC}"
  exit "${RC}"
}

trap cleanup EXIT
trap 'cleanup 143' HUP INT TERM

log_event "logcat supervisor started pid=$$"
write_state "started pid=$$"
heartbeat
while true; do
  write_state "launching"
  heartbeat
  /system/bin/logcat -b main -b system -b crash -v threadtime -f "${OUT_LOG}" -r 10240 -n 16 &
  CHILD_PID=$!
  write_state "running child=${CHILD_PID}"
  while kill -0 "${CHILD_PID}" >/dev/null 2>&1; do
    heartbeat
    /system/bin/sleep 15
  done
  wait "${CHILD_PID}"
  RC=$?
  heartbeat
  write_state "child-exit rc=${RC}"
  log_event "logcat exited rc=${RC}"
  /system/bin/sleep 1
done
EOF

  cat >"${perf_script}" <<'EOF'
#!/system/bin/sh
PACKAGE_NAME="$1"
OUT_LOG="$2"
HEARTBEAT_FILE="$3"
STATE_FILE="$4"

heartbeat() {
  /system/bin/date '+%s' > "${HEARTBEAT_FILE}"
}

write_state() {
  printf '%s %s\n' "$(/system/bin/date '+%F %T')" "$1" > "${STATE_FILE}"
}

CLEANUP_DONE=0
cleanup() {
  RC="${1:-$?}"
  if [ "${CLEANUP_DONE}" = "1" ]; then
    return
  fi
  CLEANUP_DONE=1
  heartbeat
  write_state "sampler-exit rc=${RC}"
  exit "${RC}"
}

trap cleanup EXIT
trap 'cleanup 143' HUP INT TERM

while true; do
  heartbeat
  echo "=== PERF $(/system/bin/date '+%F %T') ==="
  PID=$(/system/bin/pidof "${PACKAGE_NAME}" 2>/dev/null || true)
  write_state "sampling pid=${PID:-none}"
  echo "pid=${PID}"
  if [ -n "${PID}" ]; then
    /system/bin/top -b -n 1 | /system/bin/grep "${PACKAGE_NAME}" || true
    /system/bin/dumpsys meminfo "${PACKAGE_NAME}" | /system/bin/grep -E 'TOTAL PSS|TOTAL RSS|TOTAL SWAP|Native Heap|Dalvik Heap|EGL mtrack|GL mtrack|Gfx dev|Graphics:|Unknown' || true
  else
    echo "app not running"
  fi
  echo
  heartbeat
  /system/bin/sleep 60
done >> "${OUT_LOG}" 2>&1
EOF

  "${adb_cmd[@]}" push "${log_script}" "${REMOTE_SCRIPT_DIR}/nolive-log-supervisor.sh" >/dev/null
  "${adb_cmd[@]}" push "${perf_script}" "${REMOTE_SCRIPT_DIR}/nolive-perf-sampler.sh" >/dev/null
  adb_shell "chmod 755 '${REMOTE_SCRIPT_DIR}/nolive-log-supervisor.sh' '${REMOTE_SCRIPT_DIR}/nolive-perf-sampler.sh'"

  rm -rf "${tmp_dir}"
}

start_remote_process() {
  local command="$1"
  adb_shell "if command -v nohup >/dev/null 2>&1; then nohup ${command} >/dev/null 2>&1 </dev/null & echo \$!; else setsid ${command} >/dev/null 2>&1 </dev/null & echo \$!; fi" |
    strip_cr |
    awk 'NF {print $1; exit}'
}

wait_for_remote_heartbeat() {
  local path="$1" tries="${2:-8}"
  local value=""
  local attempt
  for ((attempt = 0; attempt < tries; attempt += 1)); do
    value="$(remote_read_first_line "${path}")"
    if [[ -n "${value}" ]]; then
      printf '%s\n' "${value}"
      return 0
    fi
    /bin/sleep 1
  done
  return 1
}

print_process_status() {
  local label="$1" pid="$2" heartbeat_file="$3" state_file="$4" warn_after_seconds="$5" stale_after_seconds="$6" device_epoch="$7"
  local running heartbeat_epoch state_line age_text="unknown"

  running=false
  if remote_pid_running "${pid}"; then
    running=true
  fi

  heartbeat_epoch="$(remote_read_first_line "${heartbeat_file}")"
  state_line="$(remote_read_trimmed "${state_file}")"
  if [[ -n "${heartbeat_epoch}" && "${heartbeat_epoch}" =~ ^[0-9]+$ && "${device_epoch}" =~ ^[0-9]+$ ]]; then
    age_text="$((device_epoch - heartbeat_epoch))s"
  fi

  if [[ "${running}" == true ]]; then
    if [[ -n "${heartbeat_epoch}" && "${heartbeat_epoch}" =~ ^[0-9]+$ && "${device_epoch}" =~ ^[0-9]+$ ]] &&
      (( device_epoch - heartbeat_epoch > stale_after_seconds )); then
      echo "${label}: stale heartbeat (pid=${pid}, age=${age_text})"
    elif [[ -n "${heartbeat_epoch}" && "${heartbeat_epoch}" =~ ^[0-9]+$ && "${device_epoch}" =~ ^[0-9]+$ ]] &&
      (( device_epoch - heartbeat_epoch > warn_after_seconds )); then
      echo "${label}: delayed heartbeat (pid=${pid}, age=${age_text})"
    else
      echo "${label}: running (pid=${pid}${heartbeat_epoch:+, heartbeat_age=${age_text}})"
    fi
  else
    echo "${label}: stopped${pid:+ (pid=${pid})}${heartbeat_epoch:+, last_heartbeat_age=${age_text}}"
  fi

  if [[ -n "${state_line}" ]]; then
    echo "${label} state: ${state_line}"
  fi
}

stop_capture() {
  local logcat_pid perf_pid
  logcat_pid="$(remote_read_first_line "${REMOTE_DIR}/current-logcat.pid")"
  perf_pid="$(remote_read_first_line "${REMOTE_DIR}/current-perf.pid")"

  if remote_pid_running "${logcat_pid}"; then
    adb_shell "kill '${logcat_pid}'" >/dev/null 2>&1 || true
    /bin/sleep 1
    remote_pid_running "${logcat_pid}" && adb_shell "kill -9 '${logcat_pid}'" >/dev/null 2>&1 || true
  fi

  if remote_pid_running "${perf_pid}"; then
    adb_shell "kill '${perf_pid}'" >/dev/null 2>&1 || true
    /bin/sleep 1
    remote_pid_running "${perf_pid}" && adb_shell "kill -9 '${perf_pid}'" >/dev/null 2>&1 || true
  fi

  adb_shell "rm -f '${REMOTE_DIR}/current-logcat.pid' '${REMOTE_DIR}/current-perf.pid' '${REMOTE_DIR}/current-session.txt' '${REMOTE_DIR}/supervisor.pid' '${REMOTE_LOGCAT_HEARTBEAT_FILE}' '${REMOTE_PERF_HEARTBEAT_FILE}' '${REMOTE_LOGCAT_STATE_FILE}' '${REMOTE_PERF_STATE_FILE}'" >/dev/null 2>&1 || true
}

start_capture() {
  local clean_start="${1:-0}"
  local uid timestamp remote_log remote_perf remote_session remote_supervisor
  local logcat_pid perf_pid device_now

  uid="$(resolve_package_uid)"
  if [[ -z "${uid}" ]]; then
    echo "failed to resolve uid for package ${PACKAGE_NAME}; is the app installed?" >&2
    exit 1
  fi

  timestamp="$(date '+%Y-%m-%d-%H%M%S')"
  remote_log="${REMOTE_DIR}/nolive-mobile-${timestamp}.log"
  remote_perf="${REMOTE_DIR}/nolive-perf-${timestamp}.log"
  remote_session="${REMOTE_DIR}/session-${timestamp}.txt"
  remote_supervisor="${REMOTE_DIR}/supervisor-${timestamp}.log"

  adb_shell "mkdir -p '${REMOTE_DIR}' '${REMOTE_APP_LOG_DIR}' '${REMOTE_SCRIPT_DIR}'"
  write_remote_helper_scripts
  stop_capture
  if [[ "${clean_start}" == "1" ]]; then
    adb_shell "rm -f '${REMOTE_DIR}'/nolive-mobile-*.log '${REMOTE_DIR}'/nolive-perf-*.log '${REMOTE_DIR}'/supervisor-*.log '${REMOTE_DIR}'/session-*.txt '${REMOTE_APP_LOG_DIR}'/*" >/dev/null 2>&1 || true
    adb_shell "/system/bin/logcat -b main -b system -b crash -c" >/dev/null 2>&1 || true
  fi

  logcat_pid="$(start_remote_process "'${REMOTE_SCRIPT_DIR}/nolive-log-supervisor.sh' '${remote_log}' '${remote_supervisor}' '${REMOTE_LOGCAT_HEARTBEAT_FILE}' '${REMOTE_LOGCAT_STATE_FILE}'")"
  perf_pid="$(start_remote_process "'${REMOTE_SCRIPT_DIR}/nolive-perf-sampler.sh' '${PACKAGE_NAME}' '${remote_perf}' '${REMOTE_PERF_HEARTBEAT_FILE}' '${REMOTE_PERF_STATE_FILE}'")"
  device_now="$(adb_shell "date '+%F %T %Z'" | strip_cr | awk 'NF {print $0; exit}')"

  if [[ -z "${logcat_pid}" || -z "${perf_pid}" ]]; then
    echo "failed to start device-side capture" >&2
    exit 1
  fi

  /bin/sleep 2
  if ! remote_pid_running "${logcat_pid}"; then
    echo "logcat supervisor failed to stay alive (pid=${logcat_pid})" >&2
    exit 1
  fi
  if ! remote_pid_running "${perf_pid}"; then
    echo "perf sampler failed to stay alive (pid=${perf_pid})" >&2
    exit 1
  fi
  if ! wait_for_remote_heartbeat "${REMOTE_LOGCAT_HEARTBEAT_FILE}" >/dev/null; then
    echo "logcat supervisor did not publish a heartbeat" >&2
    exit 1
  fi
  if ! wait_for_remote_heartbeat "${REMOTE_PERF_HEARTBEAT_FILE}" >/dev/null; then
    echo "perf sampler did not publish a heartbeat" >&2
    exit 1
  fi

  adb_shell "cat > '${remote_session}' <<'EOF'
package=${PACKAGE_NAME}
uid=${uid}
session_started=${device_now}
logcat_file=${remote_log}
perf_file=${remote_perf}
supervisor_log=${remote_supervisor}
app_log_dir=${REMOTE_APP_LOG_DIR}
logcat_pid=${logcat_pid}
perf_pid=${perf_pid}
logcat_heartbeat=${REMOTE_LOGCAT_HEARTBEAT_FILE}
perf_heartbeat=${REMOTE_PERF_HEARTBEAT_FILE}
logcat_state=${REMOTE_LOGCAT_STATE_FILE}
perf_state=${REMOTE_PERF_STATE_FILE}
EOF"
  adb_shell "printf '%s\n' '${logcat_pid}' > '${REMOTE_DIR}/current-logcat.pid'"
  adb_shell "printf '%s\n' '${perf_pid}' > '${REMOTE_DIR}/current-perf.pid'"
  adb_shell "printf '%s\n' '${remote_session}' > '${REMOTE_DIR}/current-session.txt'"
  adb_shell "printf '%s\n' '${logcat_pid}' > '${REMOTE_DIR}/supervisor.pid'"

  echo "capture started on ${ANDROID_DEVICE_ID}"
  if [[ "${clean_start}" == "1" ]]; then
    echo "start mode: clean device logs and logcat buffers"
  fi
  echo "session: ${remote_session}"
  echo "logcat: ${remote_log} (pid=${logcat_pid})"
  echo "perf: ${remote_perf} (pid=${perf_pid})"
  echo "app logs: ${REMOTE_APP_LOG_DIR}"
}

status_capture() {
  local session_path logcat_pid perf_pid latest_files device_epoch

  session_path="$(remote_read_first_line "${REMOTE_DIR}/current-session.txt")"
  logcat_pid="$(remote_read_first_line "${REMOTE_DIR}/current-logcat.pid")"
  perf_pid="$(remote_read_first_line "${REMOTE_DIR}/current-perf.pid")"
  device_epoch="$(adb_shell "date '+%s'" | strip_cr | awk 'NF {print $1; exit}')"

  echo "device: ${ANDROID_DEVICE_ID}"
  if [[ -n "${session_path}" ]]; then
    echo "session: ${session_path}"
    adb_shell "sed -n '1,20p' '${session_path}'" | strip_cr
  else
    echo "session: none"
  fi

  print_process_status \
    "logcat supervisor" \
    "${logcat_pid}" \
    "${REMOTE_LOGCAT_HEARTBEAT_FILE}" \
    "${REMOTE_LOGCAT_STATE_FILE}" \
    45 \
    120 \
    "${device_epoch}"
  print_process_status \
    "perf sampler" \
    "${perf_pid}" \
    "${REMOTE_PERF_HEARTBEAT_FILE}" \
    "${REMOTE_PERF_STATE_FILE}" \
    180 \
    360 \
    "${device_epoch}"

  latest_files="$(adb_shell "ls -lt '${REMOTE_DIR}' | head -n 12" | strip_cr)"
  if [[ -n "${latest_files}" ]]; then
    echo
    echo "${latest_files}"
  fi
}

pull_capture() {
  local destination session_path logcat_file perf_file supervisor_log

  session_path="$(remote_read_first_line "${REMOTE_DIR}/current-session.txt")"
  if [[ -z "${session_path}" ]]; then
    echo "no active session found in ${REMOTE_DIR}/current-session.txt" >&2
    exit 1
  fi

  logcat_file="$(adb_shell "sed -n 's/^logcat_file=//p' '${session_path}'" | strip_cr | awk 'NF {print $1; exit}')"
  perf_file="$(adb_shell "sed -n 's/^perf_file=//p' '${session_path}'" | strip_cr | awk 'NF {print $1; exit}')"
  supervisor_log="$(adb_shell "sed -n 's/^supervisor_log=//p' '${session_path}'" | strip_cr | awk 'NF {print $1; exit}')"

  destination="${1:-${LOCAL_PULL_ROOT}/$(basename "${session_path}" .txt)}"
  mkdir -p "${destination}"

  "${adb_cmd[@]}" pull "${session_path}" "${destination}/" >/dev/null
  [[ -n "${logcat_file}" ]] && "${adb_cmd[@]}" pull "${logcat_file}" "${destination}/" >/dev/null
  [[ -n "${perf_file}" ]] && "${adb_cmd[@]}" pull "${perf_file}" "${destination}/" >/dev/null
  if [[ -n "${supervisor_log}" ]] && remote_file_exists "${supervisor_log}"; then
    "${adb_cmd[@]}" pull "${supervisor_log}" "${destination}/" >/dev/null
  fi
  if remote_file_exists "${REMOTE_APP_LOG_DIR}"; then
    "${adb_cmd[@]}" pull "${REMOTE_APP_LOG_DIR}/." "${destination}/app-logs" >/dev/null
  fi

  echo "pulled active capture to ${destination}"
}

pull_app_logs() {
  local destination

  destination="${1:-${LOCAL_PULL_ROOT}/app-logs-$(date '+%Y-%m-%d-%H%M%S')}"
  mkdir -p "${destination}"

  if ! remote_file_exists "${REMOTE_APP_LOG_DIR}"; then
    echo "app log directory not found: ${REMOTE_APP_LOG_DIR}" >&2
    exit 1
  fi

  "${adb_cmd[@]}" pull "${REMOTE_APP_LOG_DIR}/." "${destination}/app-logs" >/dev/null
  echo "pulled app logs to ${destination}"
}

main() {
  local command="${1:-}"
  local subcommand_arg="${2:-}"
  require_adb
  select_device

  case "${command}" in
    start)
      if [[ -n "${subcommand_arg}" && "${subcommand_arg}" != "--clean" ]]; then
        usage >&2
        exit 1
      fi
      start_capture "$([[ "${subcommand_arg}" == "--clean" ]] && echo 1 || echo 0)"
      ;;
    stop)
      stop_capture
      echo "capture stopped on ${ANDROID_DEVICE_ID}"
      ;;
    status)
      status_capture
      ;;
    pull)
      pull_capture "${2:-}"
      ;;
    pull-app-logs)
      pull_app_logs "${2:-}"
      ;;
    *)
      usage
      exit 1
      ;;
  esac
}

main "$@"
