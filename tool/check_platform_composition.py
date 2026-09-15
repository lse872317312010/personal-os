#!/usr/bin/env python3
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parent.parent
COMPOSITION = ROOT / "apps/personal_os_app/lib/src/composition/app_composition.dart"
TEST = ROOT / "apps/personal_os_app/test/app_composition_test.dart"

errors: list[str] = []


def read(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8")
    except OSError as exc:
        errors.append(f"{path.relative_to(ROOT)}: {exc}")
        return ""


composition = read(COMPOSITION)
test = read(TEST)

required_composition = (
    "factory AppComposition.forCurrentPlatform() =>\n      AppComposition.forTargetPlatform(defaultTargetPlatform);",
    "factory AppComposition.forTargetPlatform(TargetPlatform platform)",
    "? AppComposition.secureVault()\n          : AppComposition.unsupportedSecurePlatform();",
    "factory AppComposition.unsupportedSecurePlatform()",
    "const eventStore = _UnavailableEventStore();",
    "final class _UnavailableEventStore implements EventStore",
    "PersistenceException.writeFailed()",
    "PersistenceException.readFailed()",
    "DefaultVaultSession(const _UnavailableSecureUnlockPort())",
    "secureVault: const _UnavailableSecureVaultPort()",
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
            f"{COMPOSITION.relative_to(ROOT)}: unsupported production dispatch must not expose a writable in-memory store"
        )

required_test = (
    "non-Android production platforms fail closed without synthetic access",
    "platform != TargetPlatform.android",
    "AppExperienceMode.secureVault",
    "controller.sourceAvailable, isFalse",
    "controller.modelConfigured, isFalse",
    "controller.onDeviceProcessingAvailable, isFalse",
    "composition.eventStore.appendAll(const [])",
    "PersistenceErrorCode.writeFailed",
    "composition.eventStore.readById('unsupported-platform-event')",
    "PersistenceErrorCode.readFailed",
    "controller.errorCode, 'security.unlock_unavailable'",
    "unsupported production shell stays behind the vault gate",
    "find.byKey(const Key('unlock-vault'))",
    "find.byKey(const Key('unlock-error'))",
    "find.text('当前无法使用系统解锁。'), findsOneWidget",
    "find.text('今天，从一个小改变开始'), findsNothing",
    "current production composition is never synthetic by default",
    "AppComposition.forCurrentPlatform()",
    "synthetic demo remains explicit opt-in",
    "AppComposition.inMemoryDemo()",
)
for token in required_test:
    if token not in test:
        errors.append(f"{TEST.relative_to(ROOT)}: missing {token!r}")

if errors:
    print("platform-composition audit: FAIL", file=sys.stderr)
    for error in errors:
        print(error, file=sys.stderr)
    raise SystemExit(1)

print("platform-composition audit: PASS")
