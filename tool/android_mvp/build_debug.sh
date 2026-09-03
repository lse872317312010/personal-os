#!/usr/bin/env bash
set -euo pipefail

tool_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$tool_dir/../.." && pwd)
app_dir="$repo_root/apps/personal_os_app"

command -v flutter >/dev/null 2>&1 || {
  echo "Flutter SDK is required and must be on PATH." >&2
  exit 1
}

bash "$repo_root/tool/verify_dogfood_assets.sh"
"$tool_dir/bootstrap_gradle_wrapper.sh"
cd "$app_dir"
flutter pub get
flutter analyze
flutter test
flutter test --reporter expanded "$repo_root/tests/integration_test/dogfood_flow_test.dart"
(
  cd android
  ./gradlew testDebugUnitTest
)
build_number="${PERSONAL_OS_BUILD_NUMBER:-${GITHUB_RUN_NUMBER:-}}"
build_args=(apk --debug)
if [[ -n "$build_number" ]]; then
  if [[ ! "$build_number" =~ ^[1-9][0-9]*$ ]]; then
    echo "Build number must be a positive integer." >&2
    exit 1
  fi
  build_args+=("--build-number=$build_number")
  export PERSONAL_OS_BUILD_NUMBER="$build_number"
fi
flutter build "${build_args[@]}"

apk_path="$app_dir/build/app/outputs/flutter-apk/app-debug.apk"
manifest_path="$app_dir/build/app/outputs/flutter-apk/app-debug.provenance.json"
python3 "$tool_dir/write_provenance.py" \
  --app-dir "$app_dir" \
  --apk "$apk_path" \
  --output "$manifest_path"

echo "Debug APK: $apk_path"
echo "Provenance manifest: $manifest_path"
