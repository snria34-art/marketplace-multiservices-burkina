#!/usr/bin/env bash
set -eu
apk="build/app/outputs/flutter-apk/app-debug.apk"
package="com.marketplaceburkina.marketplace_multiservices_burkina"
boot_ready=0
for attempt in $(seq 1 120); do
  device_state="$(adb -s emulator-5554 get-state 2>/dev/null || true)"
  if [ "$device_state" = "device" ]; then
    boot_completed="$(adb -s emulator-5554 shell getprop sys.boot_completed 2>/dev/null | tr -d '\r' || true)"
    if [ "$boot_completed" = "1" ]; then boot_ready=1; break; fi
  elif [ "$((attempt % 12))" -eq 0 ]; then
    adb reconnect offline || true
  fi
  sleep 5
done
if [ "$boot_ready" -ne 1 ]; then
  echo "Android smoke test: emulator did not become fully booted and online." >&2
  adb devices -l >&2 || true
  exit 1
fi
installed=0
for attempt in 1 2 3; do
  if adb -s emulator-5554 install -r --no-streaming "$apk"; then installed=1; break; fi
  if [ "$attempt" -lt 3 ]; then
    echo "APK installation attempt $attempt failed; reconnecting ADB and retrying." >&2
    adb kill-server || true
    adb start-server
    adb -s emulator-5554 wait-for-device
    sleep 10
  fi
done
if [ "$installed" -ne 1 ]; then
  echo "Android smoke test: APK installation failed after 3 attempts." >&2
  adb devices -l >&2 || true
  exit 1
fi
adb -s emulator-5554 shell am force-stop "$package"
adb -s emulator-5554 shell monkey -p "$package" 1
app_pid="$(adb -s emulator-5554 shell pidof "$package" | tr -d '\r')"
test -n "$app_pid" || { echo "Android smoke test: app process did not start." >&2; exit 1; }
sleep 25
adb -s emulator-5554 logcat --pid="$app_pid" -d -t 5000 > /tmp/marketplace-android-logcat.txt
grep -E 'FATAL EXCEPTION|Fatal signal|Process: com\.marketplaceburkina\.marketplace_multiservices_burkina.*has died' /tmp/marketplace-android-logcat.txt > /tmp/marketplace-crash-matches.txt || test "$?" -eq 1
if test -s /tmp/marketplace-crash-matches.txt; then
  echo "Android smoke test detected a crash in the Marketplace app process (PID $app_pid):" >&2
  cat /tmp/marketplace-crash-matches.txt >&2
  exit 1
fi
adb -s emulator-5554 shell pidof "$package" >/dev/null || { echo "Android smoke test: Marketplace app process exited during startup." >&2; exit 1; }
