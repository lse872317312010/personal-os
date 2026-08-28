#!/usr/bin/env bash
set -euo pipefail

tool_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$tool_dir/../.." && pwd)
android_dir="$repo_root/apps/personal_os_app/android"

if [[ -f "$android_dir/gradle/wrapper/gradle-wrapper.jar" && -x "$android_dir/gradlew" ]]; then
  exit 0
fi

command -v flutter >/dev/null 2>&1 || {
  echo "Flutter SDK is required and must be on PATH." >&2
  exit 1
}

scratch_dir=$(mktemp -d)
cleanup() { rm -rf -- "$scratch_dir"; }
trap cleanup EXIT

flutter create \
  --platforms=android \
  --org com.personalos \
  --project-name personal_os_app \
  "$scratch_dir/wrapper_source" >/dev/null

install -m 0755 "$scratch_dir/wrapper_source/android/gradlew" "$android_dir/gradlew"
install -m 0644 "$scratch_dir/wrapper_source/android/gradlew.bat" "$android_dir/gradlew.bat"
install -m 0644 \
  "$scratch_dir/wrapper_source/android/gradle/wrapper/gradle-wrapper.properties" \
  "$android_dir/gradle/wrapper/gradle-wrapper.properties"
install -m 0644 \
  "$scratch_dir/wrapper_source/android/gradle/wrapper/gradle-wrapper.jar" \
  "$android_dir/gradle/wrapper/gradle-wrapper.jar"

echo "Gradle wrapper bootstrapped from the installed Flutter SDK template."
