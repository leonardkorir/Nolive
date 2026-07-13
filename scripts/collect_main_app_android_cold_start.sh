#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEVICE_ID="${ANDROID_DEVICE_ID:-}"
APP_ID="${ANDROID_APP_ID:-app.nolive.mobile}"
ACTIVITY_NAME="${ANDROID_ACTIVITY_NAME:-.MainActivity}"
SAMPLES="${SAMPLES:-3}"
LOCAL_ROOT="${LOCAL_ROOT:-${ROOT_DIR}/artifacts/device-logs/live-capture}"

usage() {
  cat <<'EOF'
Usage:
  scripts/collect_main_app_android_cold_start.sh [output-dir]

Environment:
  ANDROID_DEVICE_ID      Explicit adb device id when multiple devices are connected.
  ANDROID_APP_ID         Android package name. Default: app.nolive.mobile
  ANDROID_ACTIVITY_NAME  Activity name. Default: .MainActivity
  SAMPLES                Number of cold starts. Default: 3
  LOCAL_ROOT             Default output root. Default: artifacts/device-logs/live-capture
EOF
}

require_adb() {
  if ! command -v adb >/dev/null 2>&1; then
    echo "adb not found; please install Android platform-tools first" >&2
    exit 1
  fi
}

select_device() {
  if [[ -n "${DEVICE_ID}" ]]; then
    adb_cmd=(adb -s "${DEVICE_ID}")
    return
  fi

  local device_count
  device_count="$(adb devices | awk 'NR>1 && $2=="device" {count++} END {print count+0}')"
  if [[ "${device_count}" -eq 0 ]]; then
    echo "no Android device detected; connect a phone or start an emulator" >&2
    exit 1
  fi
  if [[ "${device_count}" -gt 1 ]]; then
    echo "multiple Android devices detected; set ANDROID_DEVICE_ID explicitly" >&2
    adb devices
    exit 1
  fi

  DEVICE_ID="$(adb devices | awk 'NR>1 && $2=="device" {print $1; exit}')"
  adb_cmd=(adb -s "${DEVICE_ID}")
}

strip_cr() {
  tr -d '\r'
}

resolve_component() {
  local component resolved_component
  if [[ "${ACTIVITY_NAME}" == .* ]]; then
    component="${APP_ID}/${ACTIVITY_NAME}"
  else
    component="${ACTIVITY_NAME}"
  fi
  resolved_component="$("${adb_cmd[@]}" shell cmd package resolve-activity --brief "${APP_ID}" | strip_cr | tail -n 1)"
  if [[ -n "${resolved_component}" ]]; then
    component="${resolved_component}"
  fi
  echo "${component}"
}

extract_field() {
  local name="$1" file="$2"
  sed -n "s/^${name}: //p" "${file}" | awk 'NF {print $1; exit}'
}

median_of_file() {
  local file="$1"
  awk -F, 'NR > 1 && $3 ~ /^[0-9]+$/ {print $3}' "${file}" |
    sort -n |
    awk '{values[NR]=$1} END {if (NR == 0) exit 1; mid=int((NR+1)/2); if (NR % 2) print values[mid]; else printf "%.0f\n", (values[mid]+values[mid+1])/2}'
}

main() {
  case "${1:-}" in
    -h|--help|help)
      usage
      return
      ;;
  esac

  require_adb
  select_device

  if ! "${adb_cmd[@]}" shell pm list packages "${APP_ID}" | strip_cr | grep -Fq "package:${APP_ID}"; then
    echo "Android app is not installed on device ${DEVICE_ID}: ${APP_ID}" >&2
    exit 1
  fi

  local out_dir component summary run raw status total wait launch_state pid median
  out_dir="${1:-${LOCAL_ROOT}/cold-start-$(date '+%Y-%m-%d-%H%M%S')}"
  mkdir -p "${out_dir}"
  component="$(resolve_component)"
  summary="${out_dir}/cold-start-summary.csv"

  {
    echo "device=${DEVICE_ID}"
    echo "package=${APP_ID}"
    echo "component=${component}"
    echo "samples=${SAMPLES}"
    echo "host_started=$(date '+%F %T %Z')"
  } >"${out_dir}/metadata.txt"
  echo "run,status,total_time_ms,wait_time_ms,launch_state,pid,raw_file" >"${summary}"

  for ((run = 1; run <= SAMPLES; run += 1)); do
    raw="${out_dir}/cold-start-run-${run}.txt"
    "${adb_cmd[@]}" shell am force-stop "${APP_ID}" >/dev/null
    sleep 1
    "${adb_cmd[@]}" shell am start -W -n "${component}" | strip_cr >"${raw}"
    status="$(extract_field Status "${raw}")"
    total="$(extract_field TotalTime "${raw}")"
    wait="$(extract_field WaitTime "${raw}")"
    launch_state="$(extract_field LaunchState "${raw}")"
    pid="$("${adb_cmd[@]}" shell pidof "${APP_ID}" | strip_cr | tr -d '\n')"
    echo "${run},${status:-unknown},${total:-},${wait:-},${launch_state:-unknown},${pid:-},$(basename "${raw}")" >>"${summary}"
    if [[ "${status}" != "ok" || -z "${pid}" ]]; then
      echo "cold start run ${run} failed; see ${raw}" >&2
      exit 1
    fi
  done

  median="$(median_of_file "${summary}")"
  echo "median_total_time_ms=${median}" >>"${out_dir}/metadata.txt"
  echo "cold start samples written to ${out_dir}"
  echo "median_total_time_ms=${median}"
}

main "$@"
