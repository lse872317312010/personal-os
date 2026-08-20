#!/usr/bin/env bash
set -euo pipefail

tool_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$tool_dir/../.." && pwd)
apk="$repo_root/apps/personal_os_app/build/app/outputs/flutter-apk/app-debug.apk"
package_name="com.personalos.app"

command -v adb >/dev/null 2>&1 || {
  echo "Android platform-tools (adb) are required." >&2
  exit 1
}

[[ -f "$apk" ]] || {
  echo "Debug APK not found. Run tool/android_mvp/build_debug.sh first." >&2
  exit 1
}

# ANDROID_SERIAL may select a device without embedding its identifier in logs.
adb get-state >/dev/null
adb install -r --no-streaming "$apk" >/dev/null
adb shell am force-stop "$package_name"
adb shell monkey -p "$package_name" -c android.intent.category.LAUNCHER 1 >/dev/null

echo "Personal OS installed and launched. No device identifier or logcat was collected."
