#!/usr/bin/env bash
set -Eeuo pipefail

tool_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$tool_dir/.." && pwd)
app_dir="$repo_root/apps/personal_os_app"
test_file="$repo_root/tests/integration_test/dogfood_flow_test.dart"

command -v flutter >/dev/null 2>&1 || {
  echo "Flutter SDK is required and must be on PATH." >&2
  exit 1
}

[[ -f "$test_file" ]] || {
  echo "Dogfood test file not found: $test_file" >&2
  exit 1
}

cd "$app_dir"
flutter pub get
flutter test --reporter expanded "$test_file"

