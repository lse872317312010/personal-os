#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app_dir="$repo_root/apps/personal_os_app"

if ! command -v flutter >/dev/null 2>&1; then
  echo "error: Flutter is required but was not found on PATH." >&2
  exit 1
fi

if [[ ! -f "$app_dir/pubspec.yaml" ]]; then
  echo "error: Flutter app pubspec not found at $app_dir/pubspec.yaml." >&2
  exit 1
fi

cd "$app_dir"

flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test

build_dir="$app_dir"
bootstrap_dir=""

has_android_host=true
for required_path in \
  android/gradlew \
  android/app/src/main/AndroidManifest.xml; do
  if [[ ! -e "$app_dir/$required_path" ]]; then
    has_android_host=false
  fi
done

if [[ ! -e "$app_dir/android/settings.gradle" && \
      ! -e "$app_dir/android/settings.gradle.kts" ]]; then
  has_android_host=false
fi

if [[ ! -e "$app_dir/android/app/build.gradle" && \
      ! -e "$app_dir/android/app/build.gradle.kts" ]]; then
  has_android_host=false
fi

if [[ "$has_android_host" != true ]]; then
  echo "Android host is incomplete; bootstrapping an isolated CI build copy."
  bootstrap_dir="$(mktemp -d "$repo_root/apps/.personal_os_app_ci.XXXXXX")"
  cleanup() {
    if [[ -n "$bootstrap_dir" && -d "$bootstrap_dir" ]]; then
      rm -rf -- "$bootstrap_dir"
    fi
  }
  trap cleanup EXIT

  cp -a "$app_dir/." "$bootstrap_dir/"
  build_dir="$bootstrap_dir"
  cd "$build_dir"
  flutter create \
    --platforms=android \
    --org=com.personalos \
    --project-name=personal_os_app \
    .
  flutter pub get
fi

cd "$build_dir"
flutter build apk --debug

produced_apk="$build_dir/build/app/outputs/flutter-apk/app-debug.apk"
if [[ ! -f "$produced_apk" ]]; then
  echo "error: expected debug APK was not produced at $produced_apk." >&2
  exit 1
fi

artifact_apk="$app_dir/build/app/outputs/flutter-apk/app-debug.apk"
if [[ "$produced_apk" != "$artifact_apk" ]]; then
  mkdir -p "$(dirname "$artifact_apk")"
  cp "$produced_apk" "$artifact_apk"
fi
