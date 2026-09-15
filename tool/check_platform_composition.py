#!/usr/bin/env python3
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parent.parent
COMPOSITION = ROOT / "apps/personal_os_app/lib/src/composition/app_composition.dart"
TEST = ROOT / "apps/personal_os_app/test/app_composition_test.dart"
LOCK_SCREEN = ROOT / "apps/personal_os_app/lib/src/screens/vault_lock_screen.dart"

errors: list[str] = []


def read(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8")
    except OSError as exc:
        errors.append(f"{path.relative_to(ROOT)}: {exc}")
        return ""


composition = read(COMPOSITION)
test = read(TEST)
lock_screen = read(LOCK_SCREEN)

required_composition = (
    "factory AppComposition.forCurrentPlatform() =>\n      AppComposition.forTargetPlatform(defaultTargetPlatform);",
    "factory AppComposition.forTargetPlatform(TargetPlatform platform)",
    "TargetPlatform.android => AppComposition.secureVault()",
    "TargetPlatform.windows => AppComposition.windowsSecureBoundary()",
    "_ => AppComposition.unsupportedSecurePlatform()",
    "factory AppComposition.windowsSecureBoundary(",
    "WindowsPlatformSecurityBridge(channel: securityChannel)",
    "DefaultVaultSession(DeviceSecureUnlockAdapter(bridge))",
    "secureVault: const _UnavailableSecureVaultPort()",
    "factory AppComposition.unsupportedSecurePlatform()",
    "const eventStore = _UnavailableEventStore();",
    "final class _UnavailableEventStore implements EventStore",
    "PersistenceException.writeFailed()",
    "PersistenceException.readFailed()",
    "DefaultVaultSession(const _UnavailableSecureUnlockPort())",
    "modelGateway: const _UnavailableAppearanceAnalysisGateway()",
    "SecurityErrorCode.unlockUnavailable",
    "SecurityErrorCode.providerUnavailable",
    "configured: false",
    "supportedBoundaries: const <AppearanceProcessingBoundary>{}",
)
for token in required_composition:
    if token not in composition:
        errors.append(f"{COMPOSITION.relative_to(ROOT)}: missing {token!r}")

current_platform_start = composition.find("factory AppComposition.forCurrentPlatform()")
secure_vault_start = composition.find("factory AppComposition.secureVault(")
if current_platform_start >= 0 and secure_vault_start > current_platform_start:
    production_dispatch = composition[current_platform_start:secure_vault_start]
    if "AppComposition.inMemoryDemo()" in production_dispatch:
        errors.append(
            f"{COMPOSITION.relative_to(ROOT)}: production platform dispatch must not fall back to synthetic demo"
        )
    if "InMemoryEventStore()" in production_dispatch:
        errors.append(
            f"{COMPOSITION.relative_to(ROOT)}: production dispatch must not expose a writable in-memory store"
        )
    windows_start = production_dispatch.find("factory AppComposition.windowsSecureBoundary(")
    unsupported_start = production_dispatch.find("factory AppComposition.unsupportedSecurePlatform()")
    if windows_start >= 0 and unsupported_start > windows_start:
        windows_boundary = production_dispatch[windows_start:unsupported_start]
        if "NativeSqlCipherEventStore" in windows_boundary:
            errors.append(
                f"{COMPOSITION.relative_to(ROOT)}: staged Windows boundary must not claim Android/native SQLCipher storage"
            )
        if "MethodChannelControlledSourcePort" in windows_boundary:
            errors.append(
                f"{COMPOSITION.relative_to(ROOT)}: staged Windows boundary must not expose controlled media before native review"
            )

required_test = (
    "unsupported production platforms fail closed without synthetic access",
    "platform != TargetPlatform.android",
    "platform != TargetPlatform.windows",
    "AppExperienceMode.secureVault",
    "controller.sourceAvailable, isFalse",
    "controller.modelConfigured, isFalse",
    "controller.onDeviceProcessingAvailable, isFalse",
    "composition.eventStore.appendAll(const [])",
    "PersistenceErrorCode.writeFailed",
    "composition.eventStore.readById('unsupported-platform-event')",
    "PersistenceErrorCode.readFailed",
    "controller.errorCode, 'security.unlock_unavailable'",
    "Windows authentication cannot bypass unavailable encrypted storage",
    "AppComposition.windowsSecureBoundary(",
    "securityChannel: windowsTestChannel",
    "calls.map((call) => call.method), <String>['authenticate']",
    "controller.errorCode, 'security.provider_unavailable'",
    "Windows production shell stays behind the vault gate",
    "find.byKey(const Key('unlock-vault'))",
    "find.byKey(const Key('unlock-error'))",
    "find.text('当前平台的安全服务尚未配置。'), findsOneWidget",
    "find.text('今天，从一个小改变开始'), findsNothing",
    "current production composition is never synthetic by default",
    "AppComposition.forCurrentPlatform()",
    "synthetic demo remains explicit opt-in",
    "AppComposition.inMemoryDemo()",
)
for token in required_test:
    if token not in test:
        errors.append(f"{TEST.relative_to(ROOT)}: missing {token!r}")

if "'security.provider_unavailable' => '当前平台的安全服务尚未配置。'" not in lock_screen:
    errors.append(
        f"{LOCK_SCREEN.relative_to(ROOT)}: provider-unavailable UX must remain stable and redacted"
    )

if errors:
    print("platform-composition audit: FAIL", file=sys.stderr)
    for error in errors:
        print(error, file=sys.stderr)
    raise SystemExit(1)

print("platform-composition audit: PASS")
