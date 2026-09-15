#!/usr/bin/env python3
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parent.parent
WORKFLOW = ROOT / ".github/workflows/flutter-windows-spike.yml"
CONTRACT_WORKFLOW = ROOT / ".github/workflows/repo-contracts.yml"
SCRIPT = ROOT / "tool/windows_mvp/verify_windows_spike.ps1"

errors: list[str] = []


def read(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8")
    except OSError as exc:
        errors.append(f"{path.relative_to(ROOT)}: {exc}")
        return ""


workflow = read(WORKFLOW)
contract_workflow = read(CONTRACT_WORKFLOW)
script = read(SCRIPT)

for token in (
    "on:\n  workflow_dispatch:",
    "permissions:\n  contents: read",
    "runs-on: windows-2022",
    'flutter-version: "3.47.0"',
    "shell: pwsh",
    "run: ./tool/windows_mvp/verify_windows_spike.ps1",
):
    if token not in workflow:
        errors.append(f"{WORKFLOW.relative_to(ROOT)}: missing {token!r}")

for token in (
    "pull_request:",
    "push:",
    "actions/upload-artifact@",
    "contents: write",
):
    if token in workflow:
        errors.append(f"{WORKFLOW.relative_to(ROOT)}: forbidden {token!r}")

for token in (
    '"apps/personal_os_app/test/app_composition_test.dart"',
    '"apps/personal_os_app/test/method_channel_platform_security_bridge_test.dart"',
    '"tool/windows_mvp/**"',
    '"tool/check_platform_composition.py"',
    '"tool/check_platform_security_channel.py"',
    '"tool/check_windows_native_security.py"',
    '"tool/check_windows_portability_spike.py"',
    '".github/workflows/flutter-windows-spike.yml"',
):
    if contract_workflow.count(token) < 2:
        errors.append(
            f"{CONTRACT_WORKFLOW.relative_to(ROOT)}: pull-request and main-push filters must both watch {token!r}"
        )

for token in (
    "Set-StrictMode -Version Latest",
    "$ErrorActionPreference = 'Stop'",
    "flutter config --enable-windows-desktop",
    "flutter test test/app_composition_test.dart",
    "flutter test test/method_channel_platform_security_bridge_test.dart",
    "flutter create --platforms=windows --project-name personal_os_app --org com.personalos .",
    "git diff --exit-code -- pubspec.yaml lib test",
    "install_windows_security_channel.ps1",
    "& $securityInstaller",
    "flutter analyze",
    "flutter build windows --debug",
    "Get-FileHash -Path $exe.FullName -Algorithm SHA256",
    "WINDOWS_SPIKE_PASS",
    "$env:GITHUB_STEP_SUMMARY",
    "runner_os:",
    "security_wire_contract: PASS",
    "native_user_presence_compile: PASS",
    "Windows user-presence runtime behavior is not verified; key protection, SQLCipher Vault open/close, and controlled media remain unavailable.",
):
    if token not in script:
        errors.append(f"{SCRIPT.relative_to(ROOT)}: missing {token!r}")

for token in (
    "Invoke-WebRequest",
    "curl ",
    "actions/upload-artifact",
):
    if token in script:
        errors.append(f"{SCRIPT.relative_to(ROOT)}: forbidden {token!r}")

if errors:
    print("windows-portability-spike audit: FAIL", file=sys.stderr)
    for error in errors:
        print(error, file=sys.stderr)
    raise SystemExit(1)

print("windows-portability-spike audit: PASS")
