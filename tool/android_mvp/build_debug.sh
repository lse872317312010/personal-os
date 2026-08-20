#!/usr/bin/env bash
set -euo pipefail

tool_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$tool_dir/../.." && pwd)
app_dir="$repo_root/apps/personal_os_app"

command -v flutter >/dev/null 2>&1 || {
  echo "Flutter SDK is required and must be on PATH." >&2
  exit 1
}

"$tool_dir/bootstrap_gradle_wrapper.sh"
cd "$app_dir"
flutter pub get
flutter analyze
flutter test
flutter build apk --debug

echo "Debug APK: $app_dir/build/app/outputs/flutter-apk/app-debug.apk"
