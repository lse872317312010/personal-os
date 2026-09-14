#!/usr/bin/env bash
set -Eeuo pipefail

readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${REPO_ROOT}"

readonly OUTPUT_DIR="${1:-release}"
readonly APK_SOURCE="apps/personal_os_app/build/app/outputs/flutter-apk/app-debug.apk"
readonly PROVENANCE_SOURCE="apps/personal_os_app/build/app/outputs/flutter-apk/app-debug.provenance.json"
readonly APK_NAME="personal-os-latest-debug.apk"
readonly PROVENANCE_NAME="personal-os-latest-debug.provenance.json"
readonly SHA_NAME="personal-os-latest-debug.apk.sha256"

[[ -s "${APK_SOURCE}" ]] || { echo "Missing debug APK: ${APK_SOURCE}" >&2; exit 1; }
[[ -s "${PROVENANCE_SOURCE}" ]] || { echo "Missing provenance: ${PROVENANCE_SOURCE}" >&2; exit 1; }

mkdir -p "${OUTPUT_DIR}"
cp "${APK_SOURCE}" "${OUTPUT_DIR}/${APK_NAME}"
cp "${PROVENANCE_SOURCE}" "${OUTPUT_DIR}/${PROVENANCE_NAME}"

readonly APK_SHA256="$(sha256sum "${OUTPUT_DIR}/${APK_NAME}" | awk '{print $1}')"
printf '%s  %s\n' "${APK_SHA256}" "${APK_NAME}" > "${OUTPUT_DIR}/${SHA_NAME}"
(
  cd "${OUTPUT_DIR}"
  sha256sum --check "${SHA_NAME}"
)

readonly EXPECTED_COMMIT="${GITHUB_SHA:-$(git rev-parse HEAD)}"
PERSONAL_OS_APK_SHA256="${APK_SHA256}" \
PERSONAL_OS_EXPECTED_COMMIT="${EXPECTED_COMMIT}" \
PERSONAL_OS_PROVENANCE_PATH="${OUTPUT_DIR}/${PROVENANCE_NAME}" \
python3 - <<'PY'
import json
import os
from pathlib import Path

provenance = json.loads(
    Path(os.environ["PERSONAL_OS_PROVENANCE_PATH"]).read_text(encoding="utf-8")
)
expected_sha = os.environ["PERSONAL_OS_APK_SHA256"]
expected_commit = os.environ["PERSONAL_OS_EXPECTED_COMMIT"]

if provenance.get("apk_sha256") != expected_sha:
    raise SystemExit("provenance apk_sha256 does not match the packaged APK")
if provenance.get("github_sha") != expected_commit:
    raise SystemExit("provenance github_sha does not match the build commit")
if not provenance.get("app_version"):
    raise SystemExit("provenance app_version is empty")
if provenance.get("model_provider") != "openai":
    raise SystemExit("dogfood APK does not declare the OpenAI provider")
if provenance.get("model_id") != "gpt-5.4-mini":
    raise SystemExit("dogfood APK does not declare the pinned model")
PY

printf 'release assets verified: %s (%s)\n' "${APK_NAME}" "${APK_SHA256}"
