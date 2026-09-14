#!/usr/bin/env bash
set -Eeuo pipefail

readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${REPO_ROOT}"

: "${GH_TOKEN:?GH_TOKEN is required}"
: "${GITHUB_SHA:?GITHUB_SHA is required}"
: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"
: "${GITHUB_RUN_ID:?GITHUB_RUN_ID is required}"

readonly TAG="android-latest"
readonly RELEASE_DIR="release"
readonly APK_NAME="personal-os-latest-debug.apk"
readonly PROVENANCE_NAME="personal-os-latest-debug.provenance.json"
readonly SHA_NAME="personal-os-latest-debug.apk.sha256"

for asset in "${APK_NAME}" "${PROVENANCE_NAME}" "${SHA_NAME}"; do
  [[ -s "${RELEASE_DIR}/${asset}" ]] || {
    echo "Missing verified release asset: ${RELEASE_DIR}/${asset}" >&2
    exit 1
  }
done
(
  cd "${RELEASE_DIR}"
  sha256sum --check "${SHA_NAME}"
)

# The rolling release is intentionally pre-existing. Failing closed here keeps
# an accidental release deletion from silently creating a new publication path.
gh release view "${TAG}" >/dev/null

# Upload first while the rolling tag still points at the previously verified
# commit. If upload fails, the tag does not move. The published triplet may be
# temporarily inconsistent, but the install contract rejects any APK whose
# SHA/provenance do not agree; the next successful run clobbers all three.
gh release upload "${TAG}" "${RELEASE_DIR}"/* --clobber

readonly REMOTE_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "${REMOTE_DIR}"
}
trap cleanup EXIT

gh release download "${TAG}" \
  --dir "${REMOTE_DIR}" \
  --pattern "${APK_NAME}" \
  --pattern "${PROVENANCE_NAME}" \
  --pattern "${SHA_NAME}"

(
  cd "${REMOTE_DIR}"
  sha256sum --check "${SHA_NAME}"
)

readonly REMOTE_APK_SHA256="$(sha256sum "${REMOTE_DIR}/${APK_NAME}" | awk '{print $1}')"
PERSONAL_OS_REMOTE_APK_SHA256="${REMOTE_APK_SHA256}" \
PERSONAL_OS_EXPECTED_COMMIT="${GITHUB_SHA}" \
PERSONAL_OS_PROVENANCE_PATH="${REMOTE_DIR}/${PROVENANCE_NAME}" \
python3 - <<'PY'
import json
import os
from pathlib import Path

provenance = json.loads(
    Path(os.environ["PERSONAL_OS_PROVENANCE_PATH"]).read_text(encoding="utf-8")
)
if provenance.get("apk_sha256") != os.environ["PERSONAL_OS_REMOTE_APK_SHA256"]:
    raise SystemExit("remote release provenance does not match remote APK")
if provenance.get("github_sha") != os.environ["PERSONAL_OS_EXPECTED_COMMIT"]:
    raise SystemExit("remote release provenance does not match the candidate commit")
if provenance.get("model_provider") != "openai":
    raise SystemExit("remote release provenance has unexpected model provider")
if provenance.get("model_id") != "gpt-5.4-mini":
    raise SystemExit("remote release provenance has unexpected model id")
PY

# Only a fully re-downloaded and re-verified asset triplet may advance the
# rolling tag. This preserves exact-commit provenance on publication failures.
git tag --force "${TAG}" "${GITHUB_SHA}"
git push --force origin "refs/tags/${TAG}"

notes=$(printf '%s\n\n%s\n%s\n\n%s' \
  'Automatically tested debug APK from main.' \
  "Commit: ${GITHUB_SHA}" \
  "Workflow: https://github.com/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}" \
  'This is a debug build for dogfooding, not a production-signed release.')

gh release edit "${TAG}" \
  --title 'Personal OS latest Android debug' \
  --notes "${notes}" \
  --prerelease

printf 'rolling Android release advanced to %s\n' "${GITHUB_SHA}"
