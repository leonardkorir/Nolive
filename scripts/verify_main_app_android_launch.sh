#!/usr/bin/env bash
set -euo pipefail

DEVICE_ID="${ANDROID_DEVICE_ID:-}"
APP_ID="${ANDROID_APP_ID:-app.nolive.mobile}"
ACTIVITY_NAME="${ANDROID_ACTIVITY_NAME:-.MainActivity}"

if ! command -v adb >/dev/null 2>&1; then
  echo "adb not found; please install Android platform-tools first" >&2
  exit 1
fi

if [[ -z "$DEVICE_ID" ]]; then
  DEVICE_ID="$(adb devices | awk 'NR>1 && $2=="device" {print $1; exit}')"
fi

if [[ -z "$DEVICE_ID" ]]; then
  echo "no Android device detected; connect a phone or start an emulator" >&2
  exit 1
fi

adb_cmd=(adb -s "$DEVICE_ID")

if ! "${adb_cmd[@]}" shell pm list packages "$APP_ID" | tr -d '\r' | grep -Fq "package:$APP_ID"; then
  echo "Android app is not installed on device $DEVICE_ID: $APP_ID" >&2
  echo "run scripts/install_main_app_android.sh first" >&2
  exit 1
fi

if [[ "$ACTIVITY_NAME" == .* ]]; then
  component="$APP_ID/$ACTIVITY_NAME"
else
  component="$ACTIVITY_NAME"
fi

resolved_component="$(${adb_cmd[@]} shell cmd package resolve-activity --brief "$APP_ID" | tr -d '\r' | tail -n 1)"
if [[ -n "$resolved_component" ]]; then
  echo "Resolved launcher activity: $resolved_component"
fi

echo "Launching $component on device $DEVICE_ID..."
start_output="$(${adb_cmd[@]} shell am start -W -n "$component" | tr -d '\r')"
echo "$start_output"

if ! grep -Fq 'Status: ok' <<<"$start_output"; then
  echo "Android launch failed for $component" >&2
  exit 1
fi

pid="$(${adb_cmd[@]} shell pidof "$APP_ID" | tr -d '\r\n')"
if [[ -z "$pid" ]]; then
  echo "Android app launched but no process was found for $APP_ID" >&2
  exit 1
fi

activity_match="$(${adb_cmd[@]} shell dumpsys activity activities | tr -d '\r' | grep -m1 "$component" || true)"
if [[ -z "$activity_match" ]]; then
  echo "Android app process exists ($pid) but resumed activity could not be confirmed for $component" >&2
  exit 1
fi

echo "Verified resumed activity: $activity_match"
echo "Android release launch verification passed for $APP_ID on $DEVICE_ID (pid $pid)."
