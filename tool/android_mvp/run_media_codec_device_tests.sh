#!/usr/bin/env bash
set -euo pipefail

tool_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$tool_dir/../.." && pwd)
app_dir="$repo_root/apps/personal_os_app"
test_class="com.personalos.app.model.AndroidExternalMediaTranscoderDeviceTest"

command -v adb >/dev/null 2>&1 || {
  echo "adb is required and must be on PATH." >&2
  exit 1
}

connected_devices=$(adb devices | awk 'NR > 1 && $2 == "device" { count += 1 } END { print count + 0 }')
if [[ "$connected_devices" -eq 0 ]]; then
  echo "No authorized Android device or emulator is connected." >&2
  exit 1
fi
if [[ "$connected_devices" -gt 1 ]]; then
  echo "Multiple Android devices are connected; leave exactly one attached for this focused run." >&2
  exit 1
fi

"$tool_dir/bootstrap_gradle_wrapper.sh"
cd "$app_dir/android"
./gradlew connectedDebugAndroidTest \
  -Pandroid.testInstrumentationRunnerArguments.class="$test_class"

echo "Device codec test completed: $test_class"
