#!/usr/bin/env python3
"""Persistence-layer error mapping contract (ADR-0014).

This module is the Python contract reference for the Dart
``PersistenceError`` + ``PersistenceErrorCode`` +
``PersistenceErrorMapper`` triple described in ADR-0014. It mirrors the
17 stable ``persistence.*`` wire values, the safety rules for
``safe_message`` (must not contain paths, key material, device
fingerprints), and the canonical mapping from internal adapter
exception families to stable codes.

The Python reference exists so the contract can be CI-verified today
(see ``tool/check_contracts.sh``) while the Dart side lands in
``packages/storage_api`` once Flutter tooling is available. Both
implementations MUST stay byte-for-byte equivalent on ``wire_value``
and on the mapping table; divergence is a contract violation.
"""

from __future__ import annotations

import enum
import re
from dataclasses import dataclass, field
from typing import Any, Mapping


WIRE_PREFIX = "persistence."


class PersistenceErrorCode(enum.Enum):
    """Stable, machine-readable failures crossing the persistence layer.

    Wire values follow ``persistence.<snake_case>`` and MUST NOT change
    semantics after release. Adding a new code is allowed; renaming or
    reusing an existing wire value for a different meaning is forbidden
    and requires a superseding ADR.
    """

    VAULT_LOCKED = f"{WIRE_PREFIX}vault_locked"
    VAULT_UNLOCK_FAILED = f"{WIRE_PREFIX}vault_unlock_failed"
    VAULT_REKEY_FAILED = f"{WIRE_PREFIX}vault_rekey_failed"
    VAULT_LIFECYCLE_INVALID = f"{WIRE_PREFIX}vault_lifecycle_invalid"
    EVENT_APPEND_CONFLICT = f"{WIRE_PREFIX}event_append_conflict"
    EVENT_APPEND_REJECTED = f"{WIRE_PREFIX}event_append_rejected"
    D4_PERSISTENCE_FORBIDDEN = f"{WIRE_PREFIX}d4_persistence_forbidden"
    SENSITIVITY_FORBIDDEN = f"{WIRE_PREFIX}sensitivity_forbidden"
    FORBIDDEN_SECRET_FIELD = f"{WIRE_PREFIX}forbidden_secret_field"
    KEY_NOT_FOUND = f"{WIRE_PREFIX}key_not_found"
    KEY_PURPOSE_MISMATCH = f"{WIRE_PREFIX}key_purpose_mismatch"
    KEY_DESTROYED = f"{WIRE_PREFIX}key_destroyed"
    KEY_ROTATION_CONFLICT = f"{WIRE_PREFIX}key_rotation_conflict"
    DEVICE_REVOKED = f"{WIRE_PREFIX}device_revoked"
    PROVIDER_UNAVAILABLE = f"{WIRE_PREFIX}provider_unavailable"
    INVALID_ARGUMENT = f"{WIRE_PREFIX}invalid_argument"
    INTERNAL_ADAPTER_FAILURE = f"{WIRE_PREFIX}internal_adapter_failure"

    @property
    def wire_value(self) -> str:
        return self.value


# ---------------------------------------------------------------------------
# Safety scanner for safe_message content. Mirrors evidence/.../validate_evidence.py
# forbidden_keys but adds persistence-specific patterns (paths, stack frames,
# SQL fragments, key handles) that must never leak to evidence ledger.
# ---------------------------------------------------------------------------

_FORBIDDEN_SUBSTRINGS = frozenset(
    {
        "secret",
        "key_material",
        "raw_key",
        "rawkey",
        "wrappingkey",
        "privatekey",
        "recoverycode",
        "recoverysecret",
        "password",
        "accesstoken",
        "refreshtoken",
        "device_serial",
        "android_id",
        "account_id",
        "user_content",
        "photo_path",
        "raw_log",
        "system_fingerprint",
    }
)

_FORBIDDEN_PATTERNS = (
    re.compile(r"/(?:Users|home|tmp|var|data)/\S", re.IGNORECASE),  # unix paths
    re.compile(r"^[a-zA-Z]:\\", re.IGNORECASE),  # windows paths
    re.compile(r"\.dart(?:\s|$)", re.IGNORECASE),  # stack frames
    re.compile(r"package:personal_os_\S+", re.IGNORECASE),  # dart imports
    re.compile(r"\bSELECT\b.+\bFROM\b", re.IGNORECASE),  # sql fragments
    re.compile(r"\bINSERT\b.+\bVALUES\b", re.IGNORECASE),
    re.compile(r"\bPRAGMA\b", re.IGNORECASE),
    re.compile(r"[0-9a-f]{64}", re.IGNORECASE),  # sha256 / key-looking
)


def scan_safe_message(message: str | None) -> list[str]:
    """Return list of forbidden substrings or patterns found in *message*.

    Used by the contract tests to enforce ADR-0014 §3: ``safe_message``
    must not contain paths, key material, device fingerprints, or SQL
    fragments. Returns an empty list when *message* is safe.

    Substring matching strips ASCII whitespace, underscores, and dashes
    before comparison so attackers cannot smuggle ``"recovery code"``
    past a check that only knows ``"recoverycode"``. The eventual Dart
    side MUST mirror this normalization.
    """

    issues: list[str] = []
    if message is None:
        return issues
    compact = re.sub(r"[\s_-]+", "", message).lower()
    for needle in _FORBIDDEN_SUBSTRINGS:
        if needle in compact:
            issues.append(f"forbidden substring: {needle!r}")
    for pattern in _FORBIDDEN_PATTERNS:
        match = pattern.search(message)
        if match:
            issues.append(f"forbidden pattern {pattern.pattern!r}: {match.group(0)!r}")
    return issues


# ---------------------------------------------------------------------------
# PersistenceError carrier
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class PersistenceError(Exception):
    """Stable persistence-layer failure signal.

    Attributes:
        code: Stable ``PersistenceErrorCode`` enum value.
        cause: The original internal exception or value, retained for
            debugging. MUST NOT be serialized to evidence ledger; only
            ``code`` and ``safe_message`` are evidence-safe.
        safe_message: Human-readable reason safe for logs and evidence.
            Must pass :func:`scan_safe_message`.
    """

    code: PersistenceErrorCode
    cause: object | None = None
    safe_message: str | None = None

    @property
    def wire_value(self) -> str:
        return self.code.wire_value

    def to_evidence(self) -> Mapping[str, Any]:
        """Evidence-safe projection.

        ``cause`` and ``stack_trace`` are intentionally absent. Any
        serialization that includes them is a contract violation and
        will be flagged by ``validate_evidence.py`` (ADR-0014 §6).
        """

        return {
            "code": self.wire_value,
            "safe_message": self.safe_message,
        }

    def __str__(self) -> str:
        return f"PersistenceError({self.wire_value})"


# ---------------------------------------------------------------------------
# Mirror of internal adapter exception families. These exist purely so the
# mapper can be unit-tested without pulling in the Dart adapters. Each class
# has the same shape as its Dart counterpart.
# ---------------------------------------------------------------------------


class SecurityErrorCode(enum.Enum):
    VAULT_LOCKED = "security.vault_locked"
    UNLOCK_CANCELLED = "security.unlock_cancelled"
    UNLOCK_DENIED = "security.unlock_denied"
    UNLOCK_UNAVAILABLE = "security.unlock_unavailable"
    UNLOCK_EXPIRED = "security.unlock_expired"
    KEY_NOT_FOUND = "security.key_not_found"
    KEY_PURPOSE_MISMATCH = "security.key_purpose_mismatch"
    KEY_DESTROYED = "security.key_destroyed"
    WRAPPED_KEY_INVALID = "security.wrapped_key_invalid"
    ROTATION_CONFLICT = "security.rotation_conflict"
    DEVICE_REVOKED = "security.device_revoked"
    PLAINTEXT_KEY_EXPORT_FORBIDDEN = "security.plaintext_key_export_forbidden"
    PROVIDER_UNAVAILABLE = "security.provider_unavailable"

    @property
    def wire_value(self) -> str:
        return self.value


@dataclass(frozen=True)
class SecurityException(Exception):
    code: SecurityErrorCode
    safe_message: str | None = None

    def __str__(self) -> str:
        return f"SecurityException({self.code.wire_value})"


@dataclass(frozen=True)
class BlobAccessDenied(Exception):
    code: str
    reason: str

    @classmethod
    def d4_persistence_forbidden(cls) -> "BlobAccessDenied":
        return cls(
            code="D4_PERSISTENCE_FORBIDDEN",
            reason="D4 data must never be persisted by BlobStore",
        )

    def __str__(self) -> str:
        return f"BlobAccessDenied({self.code})"


@dataclass(frozen=True)
class EventAppendConflict(Exception):
    message: str

    def __str__(self) -> str:
        return f"EventAppendConflict: {self.message}"


@dataclass(frozen=True)
class VaultSchemaViolation(Exception):
    message: str

    def __str__(self) -> str:
        return f"VaultSchemaViolation: {self.message}"


@dataclass(frozen=True)
class VaultDriverFailure(Exception):
    code: str

    def __str__(self) -> str:
        return f"VaultDriverFailure({self.code})"


@dataclass(frozen=True)
class ArgumentErrorValue(Exception):
    """Mirrors Dart ArgumentError.value; carries message only."""

    message: str

    def __str__(self) -> str:
        return f"ArgumentError: {self.message}"


# ---------------------------------------------------------------------------
# Internal exception → PersistenceErrorCode mapping tables
# ---------------------------------------------------------------------------

_SECURITY_CODE_MAP: Mapping[SecurityErrorCode, PersistenceErrorCode] = {
    SecurityErrorCode.VAULT_LOCKED: PersistenceErrorCode.VAULT_LOCKED,
    SecurityErrorCode.UNLOCK_EXPIRED: PersistenceErrorCode.VAULT_LOCKED,
    SecurityErrorCode.UNLOCK_CANCELLED: PersistenceErrorCode.VAULT_UNLOCK_FAILED,
    SecurityErrorCode.UNLOCK_DENIED: PersistenceErrorCode.VAULT_UNLOCK_FAILED,
    SecurityErrorCode.UNLOCK_UNAVAILABLE: PersistenceErrorCode.VAULT_UNLOCK_FAILED,
    SecurityErrorCode.KEY_NOT_FOUND: PersistenceErrorCode.KEY_NOT_FOUND,
    SecurityErrorCode.KEY_PURPOSE_MISMATCH: PersistenceErrorCode.KEY_PURPOSE_MISMATCH,
    SecurityErrorCode.KEY_DESTROYED: PersistenceErrorCode.KEY_DESTROYED,
    SecurityErrorCode.ROTATION_CONFLICT: PersistenceErrorCode.KEY_ROTATION_CONFLICT,
    SecurityErrorCode.DEVICE_REVOKED: PersistenceErrorCode.DEVICE_REVOKED,
    SecurityErrorCode.PROVIDER_UNAVAILABLE: PersistenceErrorCode.PROVIDER_UNAVAILABLE,
    # PLAINTEXT_KEY_EXPORT_FORBIDDEN is a hard programming violation; v1 falls
    # back to internal_adapter_failure until a dedicated code is added.
    SecurityErrorCode.PLAINTEXT_KEY_EXPORT_FORBIDDEN: (
        PersistenceErrorCode.INTERNAL_ADAPTER_FAILURE
    ),
    # WRAPPED_KEY_INVALID is a key-envelope integrity failure; v1 falls back
    # to internal_adapter_failure. Candidate for a dedicated code in v2.
    SecurityErrorCode.WRAPPED_KEY_INVALID: (
        PersistenceErrorCode.INTERNAL_ADAPTER_FAILURE
    ),
}

_DRIVER_CODE_MAP: Mapping[str, PersistenceErrorCode] = {
    "vault_unlock_failed": PersistenceErrorCode.VAULT_UNLOCK_FAILED,
    "vault_rekey_failed": PersistenceErrorCode.VAULT_REKEY_FAILED,
    "invalid_lifecycle_transition": PersistenceErrorCode.VAULT_LIFECYCLE_INVALID,
}

_BLOB_CODE_MAP: Mapping[str, PersistenceErrorCode] = {
    "D4_PERSISTENCE_FORBIDDEN": PersistenceErrorCode.D4_PERSISTENCE_FORBIDDEN,
}

_SCHEMA_MESSAGE_PATTERNS: tuple[tuple[re.Pattern[str], PersistenceErrorCode], ...] = (
    (re.compile(r"D4 cannot enter persistent storage", re.IGNORECASE),
     PersistenceErrorCode.D4_PERSISTENCE_FORBIDDEN),
    (re.compile(r"d4_persistence_forbidden", re.IGNORECASE),
     PersistenceErrorCode.D4_PERSISTENCE_FORBIDDEN),
    (re.compile(r"Forbidden secret field", re.IGNORECASE),
     PersistenceErrorCode.FORBIDDEN_SECRET_FIELD),
    (re.compile(r"Sensitivity \S+ cannot be persisted", re.IGNORECASE),
     PersistenceErrorCode.SENSITIVITY_FORBIDDEN),
    (re.compile(r"missing_subject", re.IGNORECASE),
     PersistenceErrorCode.EVENT_APPEND_REJECTED),
)


def _map_schema_message(message: str) -> PersistenceErrorCode:
    for pattern, code in _SCHEMA_MESSAGE_PATTERNS:
        if pattern.search(message):
            return code
    return PersistenceErrorCode.INTERNAL_ADAPTER_FAILURE


def _map_driver_code(code: str) -> PersistenceErrorCode:
    return _DRIVER_CODE_MAP.get(code, PersistenceErrorCode.INTERNAL_ADAPTER_FAILURE)


def _map_blob_code(code: str) -> PersistenceErrorCode:
    return _BLOB_CODE_MAP.get(code, PersistenceErrorCode.INTERNAL_ADAPTER_FAILURE)


def _map_security_code(code: SecurityErrorCode) -> PersistenceErrorCode:
    return _SECURITY_CODE_MAP.get(code, PersistenceErrorCode.INTERNAL_ADAPTER_FAILURE)


# ---------------------------------------------------------------------------
# PersistenceErrorMapper
# ---------------------------------------------------------------------------


class PersistenceErrorMapper:
    """Central mapper from internal adapter exceptions to PersistenceError.

    Callers at the boundary (runtime_coordinator, recovery, sync_worker,
    UI controller) MUST route persistence-layer failures through this
    mapper rather than catching internal types directly (ADR-0014 §5).
    The mapper is pure, side-effect-free, and dependency-free so it can
    run identically in ``inMemoryDemo`` and ``sqliteEncrypted`` modes.
    """

    @staticmethod
    def map(error: object, *, safe_message: str | None = None) -> PersistenceError:
        if isinstance(error, PersistenceError):
            # Re-wrap only if caller supplied an explicit safe_message.
            if safe_message is None or safe_message == error.safe_message:
                return error
            return PersistenceError(
                code=error.code,
                cause=error.cause,
                safe_message=safe_message,
            )

        if isinstance(error, SecurityException):
            return PersistenceError(
                code=_map_security_code(error.code),
                cause=error,
                safe_message=safe_message or error.safe_message,
            )

        if isinstance(error, BlobAccessDenied):
            return PersistenceError(
                code=_map_blob_code(error.code),
                cause=error,
                safe_message=safe_message or error.reason,
            )

        if isinstance(error, EventAppendConflict):
            return PersistenceError(
                code=PersistenceErrorCode.EVENT_APPEND_CONFLICT,
                cause=error,
                safe_message=safe_message or error.message,
            )

        if isinstance(error, VaultSchemaViolation):
            return PersistenceError(
                code=_map_schema_message(error.message),
                cause=error,
                safe_message=safe_message or error.message,
            )

        if isinstance(error, VaultDriverFailure):
            return PersistenceError(
                code=_map_driver_code(error.code),
                cause=error,
                safe_message=safe_message or error.code,
            )

        if isinstance(error, ArgumentErrorValue):
            return PersistenceError(
                code=PersistenceErrorCode.INVALID_ARGUMENT,
                cause=error,
                safe_message=safe_message or error.message,
            )

        if isinstance(error, ValueError):
            # Python's ValueError is the closest analog to Dart ArgumentError
            # for invalid inputs (e.g. negative limit).
            return PersistenceError(
                code=PersistenceErrorCode.INVALID_ARGUMENT,
                cause=error,
                safe_message=safe_message or str(error),
            )

        return PersistenceError(
            code=PersistenceErrorCode.INTERNAL_ADAPTER_FAILURE,
            cause=error,
            safe_message=safe_message,
        )


# ---------------------------------------------------------------------------
# CLI: print the stable wire-value table for ADR / documentation audits.
# ---------------------------------------------------------------------------


def main() -> int:
    import json
    import sys

    table = [
        {
            "code_name": code.name,
            "wire_value": code.wire_value,
        }
        for code in PersistenceErrorCode
    ]
    json.dump(table, sys.stdout, indent=2)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":  # pragma: no cover
    raise SystemExit(main())
