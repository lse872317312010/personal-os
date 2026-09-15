#!/usr/bin/env python3
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parent.parent
DOC = ROOT / "architecture/WINDOWS_SECURE_ADAPTER.md"
WINDOWS_BRIDGE = ROOT / "apps/personal_os_app/lib/src/composition/windows_platform_security_bridge.dart"
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


doc = read(DOC)
windows_bridge = read(WINDOWS_BRIDGE)
windows_test = read(WINDOWS_TEST)
composition = read(COMPOSITION)
contracts = read(CONTRACTS)

for token in (
    "Windows 11 / build 22000",
    "IUserConsentVerifierInterop::RequestVerificationForWindowAsync",
    "personal_os/internal/windows_vault",
    "MS_PLATFORM_CRYPTO_PROVIDER",
    "NCryptOpenStorageProvider",
    "NCRYPT_EXPORT_POLICY_PROPERTY",
    "显式设为 `0`",
    "NCryptFinalizeKey",
    "NCRYPT_PAD_OAEP_FLAG",
    "BCRYPT_OAEP_PADDING_INFO",
    "SHA-256",
    "SecureZeroMemory",
    "NCryptFreeObject",
    "CryptProtectData/CryptUnprotectData",
    "PromptStruct",
    "2027 年 2 月",
    "production `AppComposition` **不得**实例化 `WindowsPlatformSecurityBridge`",
    "TPM provider probe 与 software-provider rejection",
    "ticket expiry/replay/process-restart rejection",
    "native SQLCipher wrong-key",
):
    if token not in doc:
        errors.append(f"{DOC.relative_to(ROOT)}: missing {token!r}")

for token in (
    "https://learn.microsoft.com/en-us/windows/win32/api/userconsentverifierinterop/",
    "https://learn.microsoft.com/en-us/windows/win32/api/ncrypt/",
    "https://learn.microsoft.com/en-us/windows/win32/seccng/key-storage-property-identifiers",
    "https://learn.microsoft.com/en-us/windows/win32/api/dpapi/nf-dpapi-cryptprotectdata",
):
    if token not in doc:
        errors.append(f"{DOC.relative_to(ROOT)}: missing Microsoft primary reference {token!r}")

for token in (
    "extends MethodChannelPlatformSecurityBridge",
    "personal_os/internal/windows_vault",
):
    if token not in windows_bridge:
        errors.append(f"{WINDOWS_BRIDGE.relative_to(ROOT)}: missing {token!r}")

for token in (
    "default Windows binding uses the frozen private channel ABI",
    "missing Windows native channel fails closed",
    "PlatformSecurityFailureCode.unavailable",
):
    if token not in windows_test:
        errors.append(f"{WINDOWS_TEST.relative_to(ROOT)}: missing {token!r}")

if "WindowsPlatformSecurityBridge(" in composition:
    errors.append(
        f"{COMPOSITION.relative_to(ROOT)}: Windows bridge entered production composition before native evidence gates"
    )

if "python3 tool/check_windows_secure_adapter_contract.py" not in contracts:
    errors.append(
        f"{CONTRACTS.relative_to(ROOT)}: Windows secure adapter contract is not gated"
    )

if errors:
    print("windows-secure-adapter contract: FAIL", file=sys.stderr)
    for error in errors:
        print(error, file=sys.stderr)
    raise SystemExit(1)

print("windows-secure-adapter contract: PASS")
