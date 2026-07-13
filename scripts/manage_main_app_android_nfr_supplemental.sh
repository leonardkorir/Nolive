#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE_NAME="${PACKAGE_NAME:-app.nolive.mobile}"
ANDROID_DEVICE_ID="${ANDROID_DEVICE_ID:-}"
LOCAL_ROOT="${LOCAL_ROOT:-${ROOT_DIR}/artifacts/device-logs/live-capture}"
INTERVAL_SECONDS="${INTERVAL_SECONDS:-15}"
CURRENT_LINK="${LOCAL_ROOT}/supplemental-current"

usage() {
  cat <<'EOF'
Usage:
  scripts/manage_main_app_android_nfr_supplemental.sh start
  scripts/manage_main_app_android_nfr_supplemental.sh stop [dir]
  scripts/manage_main_app_android_nfr_supplemental.sh status [dir]

Environment:
  ANDROID_DEVICE_ID   Explicit adb device id when multiple devices are connected.
  PACKAGE_NAME        Android package name to sample. Default: app.nolive.mobile
  LOCAL_ROOT          Output root. Default: artifacts/device-logs/live-capture
  INTERVAL_SECONDS    Sampling interval. Default: 15
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

record_apk_size() {
  local apk="$1" label="$2" metadata="$3"
  if [[ ! -f "${apk}" ]]; then
    return
  fi
  local bytes mib
  bytes="$(stat -c %s "${apk}")"
  mib="$(awk -v bytes="${bytes}" 'BEGIN {printf "%.2f", bytes / 1024 / 1024}')"
  echo "apk=${label} path=${apk#${ROOT_DIR}/} bytes=${bytes} mib=${mib}" >>"${metadata}"
}

start_capture() {
  mkdir -p "${LOCAL_ROOT}"
  local stamp out_dir metadata samples supervisor
  stamp="$(date '+%Y-%m-%d-%H%M%S')"
  out_dir="${LOCAL_ROOT}/supplemental-${stamp}"
  metadata="${out_dir}/metadata.txt"
  samples="${out_dir}/samples.log"
  supervisor="${out_dir}/supervisor.log"
  mkdir -p "${out_dir}"

  {
    echo "device=${ANDROID_DEVICE_ID}"
    echo "package=${PACKAGE_NAME}"
    echo "host_started=$(date '+%F %T %Z')"
    echo "device_epoch_started=$(adb_shell date '+%s' | strip_cr)"
    echo "interval_seconds=${INTERVAL_SECONDS}"
  } >"${metadata}"

  if adb_shell "dumpsys gfxinfo '${PACKAGE_NAME}' reset >/dev/null 2>&1"; then
    echo "gfxinfo_reset=true" >>"${metadata}"
  else
    echo "gfxinfo_reset=false" >>"${metadata}"
  fi

  record_apk_size \
    "${ROOT_DIR}/apps/main_app/build/app/outputs/flutter-apk/app-debug.apk" \
    "debug" \
    "${metadata}"
  record_apk_size \
    "${ROOT_DIR}/apps/main_app/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk" \
    "release-arm64" \
    "${metadata}"
  adb_shell "pm path '${PACKAGE_NAME}' 2>/dev/null || true" | strip_cr >>"${metadata}"

  local runner="${out_dir}/sample-loop.sh"
  cat >"${runner}" <<'EOF'
#!/usr/bin/env bash
set -u

adb_shell() {
  if [[ -n "${ANDROID_DEVICE_ID}" ]]; then
    adb -s "${ANDROID_DEVICE_ID}" shell "$@"
  else
    adb shell "$@"
  fi
}

strip_cr() {
  tr -d '\r'
}

cleanup() {
  echo "stopped host=$(date '+%F %T %Z')" >>"${SUPERVISOR_LOG}"
  exit 0
}

trap cleanup TERM INT
echo "started host=$(date '+%F %T %Z') pid=$$" >>"${SUPERVISOR_LOG}"
while true; do
  {
    echo "===== SAMPLE host=$(date '+%F %T %Z') device_epoch=$(adb_shell date '+%s' | strip_cr) ====="
    local_pid="$(adb_shell "pidof '${PACKAGE_NAME}' 2>/dev/null || true" | strip_cr)"
    echo "pid=${local_pid:-none}"
    if [[ -n "${local_pid}" ]]; then
      adb_shell "ps -A -T | grep ' ${local_pid} ' || true" | strip_cr
      adb_shell "dumpsys meminfo '${PACKAGE_NAME}' | grep -E 'TOTAL PSS|TOTAL RSS|TOTAL SWAP|Native Heap|Dalvik Heap|EGL mtrack|GL mtrack|Gfx dev|Graphics:|Unknown' || true" | strip_cr
      adb_shell "dumpsys gfxinfo '${PACKAGE_NAME}' || true" | strip_cr
    else
      echo "app not running"
    fi
    echo
  } >>"${SAMPLES_LOG}" 2>>"${SUPERVISOR_LOG}"
  sleep "${INTERVAL_SECONDS}"
done
EOF
  chmod +x "${runner}"
  ANDROID_DEVICE_ID="${ANDROID_DEVICE_ID}" \
    PACKAGE_NAME="${PACKAGE_NAME}" \
    INTERVAL_SECONDS="${INTERVAL_SECONDS}" \
    SAMPLES_LOG="${samples}" \
    SUPERVISOR_LOG="${supervisor}" \
    setsid nohup "${runner}" >/dev/null 2>&1 &
  local pid=$!
  echo "${pid}" >"${out_dir}/pid"
  ln -sfn "${out_dir}" "${CURRENT_LINK}"
  echo "started ${out_dir}"
  echo "pid=${pid}"
}

resolve_dir() {
  local requested="${1:-}"
  if [[ -n "${requested}" ]]; then
    echo "${requested}"
    return
  fi
  if [[ -L "${CURRENT_LINK}" || -d "${CURRENT_LINK}" ]]; then
    readlink -f "${CURRENT_LINK}"
    return
  fi
  echo "no supplemental capture directory specified and no current link exists" >&2
  exit 1
}

read_pid() {
  local dir="$1"
  if [[ ! -f "${dir}/pid" ]]; then
    echo "missing pid file: ${dir}/pid" >&2
    exit 1
  fi
  sed -n '1p' "${dir}/pid"
}

status_capture() {
  local dir pid
  dir="$(resolve_dir "${1:-}")"
  pid="$(read_pid "${dir}")"
  if kill -0 "${pid}" >/dev/null 2>&1; then
    echo "running pid=${pid} dir=${dir}"
  else
    echo "stopped pid=${pid} dir=${dir}"
  fi
}

stop_capture() {
  local dir pid
  dir="$(resolve_dir "${1:-}")"
  pid="$(read_pid "${dir}")"
  if kill -0 "${pid}" >/dev/null 2>&1; then
    kill "${pid}"
    sleep 1
  fi
  status_capture "${dir}"
}

main() {
  local command="${1:-}"
  case "${command}" in
    start)
      require_adb
      select_device
      start_capture
      ;;
    stop)
      stop_capture "${2:-}"
      ;;
    status)
      status_capture "${2:-}"
      ;;
    -h|--help|help|'')
      usage
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
}

main "$@"
