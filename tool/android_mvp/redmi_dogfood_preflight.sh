#!/usr/bin/env bash
set -Eeuo pipefail

tool_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$tool_dir/../.." && pwd)
apk="${1:-$repo_root/apps/personal_os_app/build/app/outputs/flutter-apk/app-debug.apk}"
output="${2:-$repo_root/redmi-dogfood-preflight.json}"
package_name="com.personalos.app"

command -v adb >/dev/null 2>&1 || {
  echo "Android platform-tools (adb) are required." >&2
  exit 1
}
[[ -f "$apk" ]] || {
  echo "APK not found: $apk" >&2
  exit 1
}

adb get-state >/dev/null
model=$(adb shell getprop ro.product.model | tr -d '\r')
android_version=$(adb shell getprop ro.build.version.release | tr -d '\r')
build_number=$(adb shell getprop ro.build.display.id | tr -d '\r')
apk_sha256=$(sha256sum "$apk" | awk '{print $1}')
commit_sha=$(git -C "$repo_root" rev-parse HEAD)

adb install -r --no-streaming "$apk" >/dev/null
adb shell am force-stop "$package_name"
adb shell monkey -p "$package_name" -c android.intent.category.LAUNCHER 1 >/dev/null

python3 - "$output" "$commit_sha" "$apk_sha256" "$model" "$android_version" "$build_number" <<'PY'
import json
import sys
from pathlib import Path

output, commit, apk_sha, model, android, build = sys.argv[1:]
data = {
    "schema_version": 1,
    "commit_sha": commit,
    "apk_sha256": apk_sha,
    "device": {
        "model": model,
        "android_version": android,
        "build_number": build,
    },
    "install_launch": {
        "result": "PASS",
        "observed_at_utc": "",
        "notes": "Preflight only; app scenario results must be filled manually.",
    },
    "scenarios": [],
}
Path(output).write_text(
    json.dumps(data, ensure_ascii=False, indent=2) + "\n",
    encoding="utf-8",
)
PY

echo "Installed and launched $package_name. Preflight written to $output."
echo "No serial number, logcat, screenshot, or user content was collected."

