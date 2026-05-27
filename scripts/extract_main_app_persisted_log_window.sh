#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/extract_main_app_persisted_log_window.sh <logs-root> <start-timestamp> [output-file]

Examples:
  scripts/extract_main_app_persisted_log_window.sh \
    artifacts/device-logs/post-install/app-logs \
    "2026-04-21 20:21:29"

  scripts/extract_main_app_persisted_log_window.sh \
    artifacts/device-logs/post-install/app-logs \
    "2026-04-21 20:21:29" \
    artifacts/device-logs/post-install/app-logs/nolive-mobile-post-install-window.log
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ "$#" -lt 2 || "$#" -gt 3 ]]; then
  usage >&2
  exit 1
fi

logs_root="$1"
start_timestamp_raw="$2"
output_file="${3:-}"

if [[ ! -d "${logs_root}" ]]; then
  echo "log root not found: ${logs_root}" >&2
  exit 1
fi

logs_root="$(cd "${logs_root}" && pwd)"
if [[ -n "${output_file}" ]]; then
  output_file="$(cd "$(dirname "${output_file}")" && pwd)/$(basename "${output_file}")"
fi

start_timestamp="$(printf '%s' "${start_timestamp_raw}" | tr ' ' 'T')"

mapfile -t log_files < <(
  find "${logs_root}" \
    -type f \
    -name 'nolive-mobile-*.log' \
    ! -name '*-post-install-window.log' \
    | LC_ALL=C sort
)

if [[ "${#log_files[@]}" -eq 0 ]]; then
  echo "no persisted app log files found under ${logs_root}" >&2
  exit 1
fi

if [[ -n "${output_file}" ]]; then
  filtered_log_files=()
  for file in "${log_files[@]}"; do
    if [[ "${file}" == "${output_file}" ]]; then
      continue
    fi
    filtered_log_files+=("${file}")
  done
  log_files=("${filtered_log_files[@]}")
fi

if [[ "${#log_files[@]}" -eq 0 ]]; then
  echo "no persisted app log files remained after excluding generated window logs" >&2
  exit 1
fi

tmp_output="$(mktemp)"
cleanup() {
  rm -f "${tmp_output}"
}
trap cleanup EXIT

awk -v start="${start_timestamp}" '
  {
    stamp = $1
    if (stamp ~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T/ && stamp >= start) {
      print
    }
  }
' "${log_files[@]}" | LC_ALL=C sort -s | awk '!seen[$0]++' > "${tmp_output}"

if [[ -n "${output_file}" ]]; then
  mkdir -p "$(dirname "${output_file}")"
  mv "${tmp_output}" "${output_file}"
  trap - EXIT
  echo "wrote persisted app log window to ${output_file}"
  exit 0
fi

cat "${tmp_output}"
