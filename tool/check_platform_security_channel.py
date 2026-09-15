#!/usr/bin/env python3
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parent.parent
BASE = ROOT / "apps/personal_os_app/lib/src/composition"
SHARED = BASE / "method_channel_platform_security_bridge.dart"
ANDROID = BASE / "android_platform_security_bridge.dart"
WINDOWS = BASE / "windows_platform_security_bridge.dart"
COMPOSITION = BASE / "app_composition.dart"
TEST = ROOT / "apps/personal_os_app/test/method_channel_platform_security_bridge_test.dart"

errors: list[str] = []


def read(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8")
    except OSError as exc:
        errors.append(f"{path.relative_to(ROOT)}: {exc}")
        return ""


shared = read(SHARED)
android = read(ANDROID)
windows = read(WINDOWS)
composition = read(COMPOSITION)
test = read(TEST)

for token in (
    "class MethodChannelPlatformSecurityBridge implements PlatformSecurityBridge",
    "Future<DeviceSecurityCapabilities> inspectCapabilities()",
    "Future<PlatformAuthenticationTicket> authenticate(",
    "Future<PlatformVaultSession> openVault(",
    "Future<PlatformKeyReference> createKey(",
    "Future<PlatformWrappedKey> wrapKey(",
    "Future<PlatformKeyReference> unwrapKey(",
    "Future<PlatformEpochRotation> rotateAccountEpoch(",
    "Future<PlatformEpochRotation> revokeDeviceAndRotate(",
    "Future<void> authorizeNewData(",
    "Future<void> destroyKey(",
    "on PlatformException catch (error)",
    "on MissingPluginException",
    "PlatformSecurityFailureCode.unavailable",
    "'security.vault_session_invalid'",
):
    if token not in shared:
        errors.append(f"{SHARED.relative_to(ROOT)}: missing {token!r}")

for forbidden in (
    "personal_os/internal/android_vault",
    "personal_os/internal/windows_vault",
):
    if forbidden in shared:
        errors.append(
            f"{SHARED.relative_to(ROOT)}: shared protocol must not bind platform channel {forbidden!r}"
        )

for path, text, class_name, channel in (
    (
        ANDROID,
        android,
        "AndroidPlatformSecurityBridge",
        "personal_os/internal/android_vault",
    ),
    (
        WINDOWS,
        windows,
        "WindowsPlatformSecurityBridge",
        "personal_os/internal/windows_vault",
    ),
):
    for token in (
        f"final class {class_name}",
        "extends MethodChannelPlatformSecurityBridge",
        channel,
    ):
        if token not in text:
            errors.append(f"{path.relative_to(ROOT)}: missing {token!r}")

for token in (
    "TargetPlatform.windows => AppComposition.windowsSecureBoundary()",
    "WindowsPlatformSecurityBridge(channel: securityChannel)",
    "DefaultVaultSession(DeviceSecureUnlockAdapter(bridge))",
    "secureVault: const _UnavailableSecureVaultPort()",
):
    if token not in composition:
        errors.append(f"{COMPOSITION.relative_to(ROOT)}: missing {token!r}")

for token in (
    "shared bridge decodes capabilities and authentication ticket",
    "platform exception text and details are redacted",
    "missing native handler fails closed as unavailable",
    "Windows wrapper selects the isolated windows vault channel",
    "isNot(contains('native secret message'))",
    "PlatformSecurityFailureCode.unavailable",
):
    if token not in test:
        errors.append(f"{TEST.relative_to(ROOT)}: missing {token!r}")

if errors:
    print("platform-security-channel audit: FAIL", file=sys.stderr)
    for error in errors:
        print(error, file=sys.stderr)
    raise SystemExit(1)

print("platform-security-channel audit: PASS")
