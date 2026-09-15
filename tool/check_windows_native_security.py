#!/usr/bin/env python3
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parent.parent
NATIVE = ROOT / "tool/windows_mvp/native/windows_security_channel.cpp"
HEADER = ROOT / "tool/windows_mvp/native/windows_security_channel.h"
INSTALLER = ROOT / "tool/windows_mvp/install_windows_security_channel.ps1"
SPIKE = ROOT / "tool/windows_mvp/verify_windows_spike.ps1"

errors: list[str] = []


def read(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8")
    except OSError as exc:
        errors.append(f"{path.relative_to(ROOT)}: {exc}")
        return ""


native = read(NATIVE)
header = read(HEADER)
installer = read(INSTALLER)
spike = read(SPIKE)

for token in (
    '#include <userconsentverifierinterop.h>',
    '#include <winrt/Windows.Security.Credentials.UI.h>',
    'personal_os/internal/windows_vault',
    'UserConsentVerifier::CheckAvailabilityAsync()',
    'winrt::get_activation_factory<',
    '::IUserConsentVerifierInterop',
    '&::IUserConsentVerifierInterop::RequestVerificationForWindowAsync',
    'owner_window',
    'protectionLevel',
    'flutter::EncodableValue("unavailable")',
    'flutter::EncodableValue("nonExportableKeys")',
    'flutter::EncodableValue(false)',
    'constexpr std::chrono::seconds kTicketLifetime{60}',
    '::CoCreateGuid(&guid)',
    'security.unlock_cancelled',
    'security.unlock_denied',
    'security.unlock_unavailable',
    'security.provider_unavailable',
    'if (owner_window == nullptr || !allow_device_credential)',
    'result->Error(kProviderUnavailable);',
    'UnregisterWindowsSecurityChannel(messenger);',
    'state->active.store(false, std::memory_order_release)',
):
    if token not in native:
        errors.append(f"{NATIVE.relative_to(ROOT)}: missing {token!r}")

for forbidden in (
    'UserConsentVerifier::RequestVerificationAsync',
    'CryptProtectData',
    'CryptUnprotectData',
    'SQLCipher',
    'sqlite3_',
    'OutputDebugString',
    'std::cout',
    'std::cerr',
):
    if forbidden in native:
        errors.append(
            f"{NATIVE.relative_to(ROOT)}: staged user-presence boundary must not contain {forbidden!r}"
        )

for token in (
    'void RegisterWindowsSecurityChannel(flutter::BinaryMessenger* messenger,',
    'void UnregisterWindowsSecurityChannel(flutter::BinaryMessenger* messenger);',
):
    if token not in header:
        errors.append(f"{HEADER.relative_to(ROOT)}: missing {token!r}")

for token in (
    "'windows_security_channel.h'",
    "'windows_security_channel.cpp'",
    '"windows_security_channel.cpp"',
    '"windowsapp.lib" "ole32.lib"',
    '#include "windows_security_channel.h"',
    'RegisterWindowsSecurityChannel(',
    'UnregisterWindowsSecurityChannel(',
    'flutter_controller_->engine()->messenger(), GetHandle()',
    'WINDOWS_SECURITY_CHANNEL_INSTALLED',
):
    if token not in installer:
        errors.append(f"{INSTALLER.relative_to(ROOT)}: missing {token!r}")

for token in (
    'install_windows_security_channel.ps1',
    '& $securityInstaller',
    'flutter build windows --debug',
    'native_user_presence_compile: PASS',
    'Windows user-presence runtime behavior is not verified',
):
    if token not in spike:
        errors.append(f"{SPIKE.relative_to(ROOT)}: missing {token!r}")

if errors:
    print("windows-native-security audit: FAIL", file=sys.stderr)
    for error in errors:
        print(error, file=sys.stderr)
    raise SystemExit(1)

print("windows-native-security audit: PASS")
