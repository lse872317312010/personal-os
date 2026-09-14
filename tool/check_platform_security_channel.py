#!/usr/bin/env python3
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parent.parent
GENERIC = ROOT / "apps/personal_os_app/lib/src/composition/method_channel_platform_security_bridge.dart"
ANDROID = ROOT / "apps/personal_os_app/lib/src/composition/android_platform_security_bridge.dart"
WINDOWS = ROOT / "apps/personal_os_app/lib/src/composition/windows_platform_security_bridge.dart"
TEST = ROOT / "apps/personal_os_app/test/method_channel_platform_security_bridge_test.dart"
WINDOWS_TEST = ROOT / "apps/personal_os_app/test/windows_platform_security_bridge_test.dart"
COMPOSITION = ROOT / "apps/personal_os_app/lib/src/composition/app_composition.dart"
CONTRACTS = ROOT / "tool/check_contracts.sh"

errors: list[str] = []


def read(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8")
    except OSError as exc:
        errors.append(f"{path.relative_to(ROOT)}: {exc}")
        return ""


generic = read(GENERIC)
android = read(ANDROID)
windows = read(WINDOWS)
test = read(TEST)
windows_test = read(WINDOWS_TEST)
composition = read(COMPOSITION)
contracts = read(CONTRACTS)

for token in (
    "class MethodChannelPlatformSecurityBridge implements PlatformSecurityBridge",
    "MethodChannelPlatformSecurityBridge({required MethodChannel channel})",
    "Future<DeviceSecurityCapabilities> inspectCapabilities()",
    "Future<PlatformAuthenticationTicket> authenticate(",
    "Future<PlatformWrappedKey> wrapKey(",
    "Future<PlatformKeyReference> unwrapKey(",
    "'security.vault_session_invalid' =>",
    "PlatformSecurityFailureCode.vaultSessionInvalid",
    "on PlatformException catch (error)",
    "on MissingPluginException",
    "PlatformSecurityFailureCode.unavailable",
):
    if token not in generic:
        errors.append(f"{GENERIC.relative_to(ROOT)}: missing {token!r}")

for forbidden in (
    "personal_os/internal/android_vault",
    "personal_os/internal/windows_vault",
):
    if forbidden in generic:
        errors.append(
            f"{GENERIC.relative_to(ROOT)}: shared codec must not bind platform channel {forbidden!r}"
        )

for token in (
    "extends MethodChannelPlatformSecurityBridge",
    "personal_os/internal/android_vault",
    "method_channel_platform_security_bridge.dart",
):
    if token not in android:
        errors.append(f"{ANDROID.relative_to(ROOT)}: missing {token!r}")

for token in (
    "extends MethodChannelPlatformSecurityBridge",
    "personal_os/internal/windows_vault",
    "method_channel_platform_security_bridge.dart",
):
    if token not in windows:
        errors.append(f"{WINDOWS.relative_to(ROOT)}: missing {token!r}")

for binding, source in (("Android", android), ("Windows", windows)):
    for forbidden in (
        "Future<DeviceSecurityCapabilities> inspectCapabilities()",
        "PlatformSecurityFailureCode _failureCode",
        "Future<PlatformWrappedKey> wrapKey(",
    ):
        if forbidden in source:
            errors.append(
                f"{binding} binding duplicates shared codec {forbidden!r}"
            )

for token in (
    "decodes capabilities and forwards bounded authentication input",
    "encodes opaque key references and copies wrapped ciphertext",
    "maps allowlisted native errors and redacts native details",
    "security.vault_session_invalid",
    "unknown native errors and malformed payloads fail closed",
    "Android binding delegates through the shared codec",
):
    if token not in test:
        errors.append(f"{TEST.relative_to(ROOT)}: missing {token!r}")

for token in (
    "default Windows binding uses the frozen private channel ABI",
    "personal_os/internal/windows_vault",
    "missing Windows native channel fails closed",
    "PlatformSecurityFailureCode.unavailable",
):
    if token not in windows_test:
        errors.append(f"{WINDOWS_TEST.relative_to(ROOT)}: missing {token!r}")

if "WindowsPlatformSecurityBridge(" in composition:
    errors.append(
        f"{COMPOSITION.relative_to(ROOT)}: Windows native bridge must not enter production composition before native secure-vault evidence"
    )

if "python3 tool/check_platform_security_channel.py" not in contracts:
    errors.append(
        f"{CONTRACTS.relative_to(ROOT)}: shared platform security audit is not gated"
    )

if errors:
    print("platform-security-channel audit: FAIL", file=sys.stderr)
    for error in errors:
        print(error, file=sys.stderr)
    raise SystemExit(1)

print("platform-security-channel audit: PASS")
