#!/usr/bin/env python3
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parent.parent
WORKFLOW = ROOT / ".github/workflows/flutter-android.yml"
PREPARE = ROOT / "tool/android_mvp/prepare_release_assets.sh"
PUBLISH = ROOT / "tool/android_mvp/publish_rolling_release.sh"

errors: list[str] = []


def read(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8")
    except OSError as exc:
        errors.append(f"{path.relative_to(ROOT)}: {exc}")
        return ""


workflow = read(WORKFLOW)
prepare = read(PREPARE)
publish = read(PUBLISH)

for token in (
    "verify-build:",
    "if: github.event_name != 'push' || github.ref != 'refs/heads/main'",
    "verify-publish-main:",
    "if: github.event_name == 'push' && github.ref == 'refs/heads/main'",
    "permissions:\n  contents: read",
    "run: bash tool/android_mvp/prepare_release_assets.sh",
    "run: bash tool/android_mvp/publish_rolling_release.sh",
    "GH_TOKEN: ${{ github.token }}",
):
    if token not in workflow:
        errors.append(f"{WORKFLOW.relative_to(ROOT)}: missing {token!r}")

for token in (
    "actions/upload-artifact@",
    "actions/download-artifact@",
):
    if token in workflow:
        errors.append(f"{WORKFLOW.relative_to(ROOT)}: forbidden {token!r}")

if workflow.count("contents: write") != 1:
    errors.append(
        f"{WORKFLOW.relative_to(ROOT)}: expected exactly one job-scoped contents: write"
    )
if workflow.count("run: bash tool/android_mvp/prepare_release_assets.sh") != 2:
    errors.append(
        f"{WORKFLOW.relative_to(ROOT)}: both build paths must use the same release preparation script"
    )
if workflow.count("run: bash tool/android_mvp/publish_rolling_release.sh") != 1:
    errors.append(
        f"{WORKFLOW.relative_to(ROOT)}: only the main-push job may publish the rolling release"
    )

for token in (
    'APK_SOURCE="apps/personal_os_app/build/app/outputs/flutter-apk/app-debug.apk"',
    'PROVENANCE_SOURCE="apps/personal_os_app/build/app/outputs/flutter-apk/app-debug.provenance.json"',
    'APK_NAME="personal-os-latest-debug.apk"',
    'PROVENANCE_NAME="personal-os-latest-debug.provenance.json"',
    'SHA_NAME="personal-os-latest-debug.apk.sha256"',
    'sha256sum --check "${SHA_NAME}"',
    'EXPECTED_COMMIT="${GITHUB_SHA:-$(git rev-parse HEAD)}"',
    'provenance.get("github_sha") != expected_commit',
    'provenance.get("model_provider") != "openai"',
    'provenance.get("model_id") != "gpt-5.4-mini"',
):
    if token not in prepare:
        errors.append(f"{PREPARE.relative_to(ROOT)}: missing {token!r}")

for token in (
    ': "${GH_TOKEN:?GH_TOKEN is required}"',
    ': "${GITHUB_SHA:?GITHUB_SHA is required}"',
    'TAG="android-latest"',
    'gh release view "${TAG}" >/dev/null',
    'gh release upload "${TAG}" "${RELEASE_DIR}"/* --clobber',
    'gh release download "${TAG}"',
    'sha256sum --check "${SHA_NAME}"',
    'provenance.get("github_sha") != os.environ["EXPECTED_COMMIT"]',
    'git tag --force "${TAG}" "${GITHUB_SHA}"',
    'git push --force origin "refs/tags/${TAG}"',
    'gh release edit "${TAG}"',
):
    if token not in publish:
        errors.append(f"{PUBLISH.relative_to(ROOT)}: missing {token!r}")

try:
    upload_index = publish.index('gh release upload "${TAG}"')
    download_index = publish.index('gh release download "${TAG}"')
    remote_commit_check_index = publish.index(
        'provenance.get("github_sha") != os.environ["EXPECTED_COMMIT"]'
    )
    tag_index = publish.index('git tag --force "${TAG}" "${GITHUB_SHA}"')
    notes_index = publish.index('gh release edit "${TAG}"')
    if not upload_index < download_index < remote_commit_check_index < tag_index < notes_index:
        errors.append(
            f"{PUBLISH.relative_to(ROOT)}: release must upload, re-download, verify, then move tag and edit notes"
        )
except ValueError:
    pass

if 'gh release create' in publish:
    errors.append(
        f"{PUBLISH.relative_to(ROOT)}: rolling publication must fail closed if android-latest is missing"
    )

if errors:
    print("android-release-delivery audit: FAIL", file=sys.stderr)
    for error in errors:
        print(error, file=sys.stderr)
    raise SystemExit(1)

print("android-release-delivery audit: PASS")
