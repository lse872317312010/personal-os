"""Unit tests for the ADR-0014 persistence error mapping contract."""

from __future__ import annotations

import json
import subprocess
import sys
import unittest
from pathlib import Path
from typing import Iterable

REPO_ROOT = Path(__file__).resolve().parents[3]
MODULE_PATH = REPO_ROOT / "tool" / "persistence_error"
sys.path.insert(0, str(MODULE_PATH))

import persistence_error as pe  # noqa: E402
from persistence_error import (  # noqa: E402
    ArgumentErrorValue,
    BlobAccessDenied,
    EventAppendConflict,
    PersistenceError,
    PersistenceErrorCode,
    PersistenceErrorMapper,
    SecurityErrorCode,
    SecurityException,
    VaultDriverFailure,
    VaultSchemaViolation,
    scan_safe_message,
)


class WireValueContractTests(unittest.TestCase):
    """ADR-0014 §2 — wire_value table is stable and prefixed."""

    EXPECTED_CODES = {
        "VAULT_LOCKED": "persistence.vault_locked",
        "VAULT_UNLOCK_FAILED": "persistence.vault_unlock_failed",
        "VAULT_REKEY_FAILED": "persistence.vault_rekey_failed",
        "VAULT_LIFECYCLE_INVALID": "persistence.vault_lifecycle_invalid",
        "EVENT_APPEND_CONFLICT": "persistence.event_append_conflict",
        "EVENT_APPEND_REJECTED": "persistence.event_append_rejected",
        "D4_PERSISTENCE_FORBIDDEN": "persistence.d4_persistence_forbidden",
        "SENSITIVITY_FORBIDDEN": "persistence.sensitivity_forbidden",
        "FORBIDDEN_SECRET_FIELD": "persistence.forbidden_secret_field",
        "KEY_NOT_FOUND": "persistence.key_not_found",
        "KEY_PURPOSE_MISMATCH": "persistence.key_purpose_mismatch",
        "KEY_DESTROYED": "persistence.key_destroyed",
        "KEY_ROTATION_CONFLICT": "persistence.key_rotation_conflict",
        "DEVICE_REVOKED": "persistence.device_revoked",
        "PROVIDER_UNAVAILABLE": "persistence.provider_unavailable",
        "INVALID_ARGUMENT": "persistence.invalid_argument",
        "INTERNAL_ADAPTER_FAILURE": "persistence.internal_adapter_failure",
    }

    def test_exactly_seventeen_codes(self) -> None:
        self.assertEqual(len(PersistenceErrorCode), 17)

    def test_every_code_has_expected_wire_value(self) -> None:
        for name, wire in self.EXPECTED_CODES.items():
            with self.subTest(code=name):
                code = PersistenceErrorCode[name]
                self.assertEqual(code.wire_value, wire)
                self.assertEqual(code.value, wire)

    def test_wire_value_starts_with_persistence_prefix(self) -> None:
        for code in PersistenceErrorCode:
            self.assertTrue(
                code.wire_value.startswith("persistence."),
                f"{code.name} wire_value missing prefix: {code.wire_value}",
            )

    def test_wire_values_are_unique(self) -> None:
        wires = [code.wire_value for code in PersistenceErrorCode]
        self.assertEqual(len(wires), len(set(wires)))


class MapperSecurityTests(unittest.TestCase):
    """ADR-0014 §2 — SecurityException → PersistenceError mapping."""

    CASES = (
        (SecurityErrorCode.VAULT_LOCKED, PersistenceErrorCode.VAULT_LOCKED),
        (SecurityErrorCode.UNLOCK_EXPIRED, PersistenceErrorCode.VAULT_LOCKED),
        (SecurityErrorCode.UNLOCK_CANCELLED, PersistenceErrorCode.VAULT_UNLOCK_FAILED),
        (SecurityErrorCode.UNLOCK_DENIED, PersistenceErrorCode.VAULT_UNLOCK_FAILED),
        (SecurityErrorCode.UNLOCK_UNAVAILABLE, PersistenceErrorCode.VAULT_UNLOCK_FAILED),
        (SecurityErrorCode.KEY_NOT_FOUND, PersistenceErrorCode.KEY_NOT_FOUND),
        (SecurityErrorCode.KEY_PURPOSE_MISMATCH,
         PersistenceErrorCode.KEY_PURPOSE_MISMATCH),
        (SecurityErrorCode.KEY_DESTROYED, PersistenceErrorCode.KEY_DESTROYED),
        (SecurityErrorCode.ROTATION_CONFLICT,
         PersistenceErrorCode.KEY_ROTATION_CONFLICT),
        (SecurityErrorCode.DEVICE_REVOKED, PersistenceErrorCode.DEVICE_REVOKED),
        (SecurityErrorCode.PROVIDER_UNAVAILABLE,
         PersistenceErrorCode.PROVIDER_UNAVAILABLE),
        (SecurityErrorCode.PLAINTEXT_KEY_EXPORT_FORBIDDEN,
         PersistenceErrorCode.INTERNAL_ADAPTER_FAILURE),
        (SecurityErrorCode.WRAPPED_KEY_INVALID,
         PersistenceErrorCode.INTERNAL_ADAPTER_FAILURE),
    )

    def test_each_security_code_maps_to_expected_persistence_code(self) -> None:
        for sec_code, expected in self.CASES:
            with self.subTest(security_code=sec_code.name):
                error = SecurityException(code=sec_code, safe_message="ctx")
                mapped = PersistenceErrorMapper.map(error)
                self.assertEqual(mapped.code, expected)
                self.assertEqual(mapped.cause, error)
                self.assertEqual(mapped.safe_message, "ctx")

    def test_safe_message_falls_back_to_none_when_missing(self) -> None:
        error = SecurityException(code=SecurityErrorCode.VAULT_LOCKED)
        mapped = PersistenceErrorMapper.map(error)
        self.assertIsNone(mapped.safe_message)


class MapperBlobTests(unittest.TestCase):
    """ADR-0014 §2 — BlobAccessDenied → PersistenceError mapping."""

    def test_d4_blob_maps_to_d4_persistence_forbidden(self) -> None:
        error = BlobAccessDenied.d4_persistence_forbidden()
        mapped = PersistenceErrorMapper.map(error)
        self.assertEqual(mapped.code, PersistenceErrorCode.D4_PERSISTENCE_FORBIDDEN)
        self.assertEqual(mapped.safe_message, error.reason)

    def test_unknown_blob_code_falls_back_to_internal(self) -> None:
        error = BlobAccessDenied(code="UNKNOWN_BLOB_CODE", reason="r")
        mapped = PersistenceErrorMapper.map(error)
        self.assertEqual(mapped.code, PersistenceErrorCode.INTERNAL_ADAPTER_FAILURE)


class MapperEventAppendTests(unittest.TestCase):
    """ADR-0014 §2 — EventAppendConflict mapping."""

    def test_event_append_conflict_maps_to_event_append_conflict(self) -> None:
        error = EventAppendConflict(message="event_id collision: e1")
        mapped = PersistenceErrorMapper.map(error)
        self.assertEqual(mapped.code, PersistenceErrorCode.EVENT_APPEND_CONFLICT)
        self.assertEqual(mapped.safe_message, "event_id collision: e1")


class MapperSchemaTests(unittest.TestCase):
    """ADR-0014 §2 — VaultSchemaViolation message routing."""

    CASES = (
        ("D4 cannot enter persistent storage",
         PersistenceErrorCode.D4_PERSISTENCE_FORBIDDEN),
        ("d4_persistence_forbidden",
         PersistenceErrorCode.D4_PERSISTENCE_FORBIDDEN),
        ("Forbidden secret field at $.payload.password",
         PersistenceErrorCode.FORBIDDEN_SECRET_FIELD),
        ("Sensitivity D5 cannot be persisted",
         PersistenceErrorCode.SENSITIVITY_FORBIDDEN),
        ("event_id collision: missing_subject",
         PersistenceErrorCode.EVENT_APPEND_REJECTED),
    )

    def test_each_schema_message_maps_to_expected_code(self) -> None:
        for message, expected in self.CASES:
            with self.subTest(message=message):
                error = VaultSchemaViolation(message=message)
                mapped = PersistenceErrorMapper.map(error)
                self.assertEqual(mapped.code, expected)

    def test_unrecognized_schema_message_falls_back_to_internal(self) -> None:
        error = VaultSchemaViolation(message="some unknown future failure")
        mapped = PersistenceErrorMapper.map(error)
        self.assertEqual(mapped.code, PersistenceErrorCode.INTERNAL_ADAPTER_FAILURE)


class MapperDriverTests(unittest.TestCase):
    """ADR-0014 §2 — VaultDriverFailure code routing."""

    CASES = (
        ("vault_unlock_failed", PersistenceErrorCode.VAULT_UNLOCK_FAILED),
        ("vault_rekey_failed", PersistenceErrorCode.VAULT_REKEY_FAILED),
        ("invalid_lifecycle_transition",
         PersistenceErrorCode.VAULT_LIFECYCLE_INVALID),
    )

    def test_each_driver_code_maps_to_expected_persistence_code(self) -> None:
        for code, expected in self.CASES:
            with self.subTest(driver_code=code):
                error = VaultDriverFailure(code=code)
                mapped = PersistenceErrorMapper.map(error)
                self.assertEqual(mapped.code, expected)
                self.assertEqual(mapped.safe_message, code)

    def test_unknown_driver_code_falls_back_to_internal(self) -> None:
        mapped = PersistenceErrorMapper.map(VaultDriverFailure(code="unknown"))
        self.assertEqual(mapped.code, PersistenceErrorCode.INTERNAL_ADAPTER_FAILURE)


class MapperArgumentTests(unittest.TestCase):
    """ADR-0014 §2 — ArgumentError / ValueError routing."""

    def test_argument_error_value_maps_to_invalid_argument(self) -> None:
        error = ArgumentErrorValue(message="limit must be >= 0")
        mapped = PersistenceErrorMapper.map(error)
        self.assertEqual(mapped.code, PersistenceErrorCode.INVALID_ARGUMENT)
        self.assertEqual(mapped.safe_message, "limit must be >= 0")

    def test_value_error_maps_to_invalid_argument(self) -> None:
        mapped = PersistenceErrorMapper.map(ValueError("bad input"))
        self.assertEqual(mapped.code, PersistenceErrorCode.INVALID_ARGUMENT)


class MapperFallbackTests(unittest.TestCase):
    """ADR-0014 §7 — unknown failures collapse to internal_adapter_failure."""

    def test_arbitrary_exception_falls_back_to_internal(self) -> None:
        mapped = PersistenceErrorMapper.map(RuntimeError("boom"))
        self.assertEqual(mapped.code, PersistenceErrorCode.INTERNAL_ADAPTER_FAILURE)
        self.assertEqual(mapped.cause.args, ("boom",))

    def test_persistence_error_round_trips(self) -> None:
        original = PersistenceError(
            code=PersistenceErrorCode.VAULT_LOCKED,
            cause=None,
            safe_message="locked",
        )
        mapped = PersistenceErrorMapper.map(original)
        self.assertIs(mapped, original)

    def test_persistence_error_with_explicit_safe_message_overrides(self) -> None:
        original = PersistenceError(
            code=PersistenceErrorCode.VAULT_LOCKED,
            cause=None,
            safe_message="old",
        )
        mapped = PersistenceErrorMapper.map(original, safe_message="new")
        self.assertEqual(mapped.safe_message, "new")
        self.assertEqual(mapped.cause, original.cause)
        self.assertEqual(mapped.code, original.code)


class EvidenceProjectionTests(unittest.TestCase):
    """ADR-0014 §6 — to_evidence projection excludes cause / stack_trace."""

    def test_to_evidence_includes_code_and_safe_message_only(self) -> None:
        error = PersistenceError(
            code=PersistenceErrorCode.D4_PERSISTENCE_FORBIDDEN,
            cause=BlobAccessDenied.d4_persistence_forbidden(),
            safe_message="D4 data must never be persisted by BlobStore",
        )
        evidence = error.to_evidence()
        self.assertEqual(
            evidence["code"], "persistence.d4_persistence_forbidden")
        self.assertEqual(
            evidence["safe_message"],
            "D4 data must never be persisted by BlobStore")
        self.assertNotIn("cause", evidence)
        self.assertNotIn("stack_trace", evidence)

    def test_to_evidence_with_none_safe_message_is_safe(self) -> None:
        error = PersistenceError(
            code=PersistenceErrorCode.INTERNAL_ADAPTER_FAILURE,
            cause=None,
            safe_message=None,
        )
        evidence = error.to_evidence()
        self.assertIsNone(evidence["safe_message"])
        self.assertNotIn("cause", evidence)


class SafeMessageScannerTests(unittest.TestCase):
    """ADR-0014 §3 — safe_message must not leak paths / key material."""

    def test_clean_message_passes(self) -> None:
        self.assertEqual(scan_safe_message("vault locked"), [])

    def test_none_message_passes(self) -> None:
        self.assertEqual(scan_safe_message(None), [])

    def test_unix_path_is_flagged(self) -> None:
        issues = scan_safe_message("path /home/user/secret.bin not found")
        self.assertTrue(issues)

    def test_windows_path_is_flagged(self) -> None:
        issues = scan_safe_message("C:\\Users\\me\\vault.db locked")
        self.assertTrue(issues)

    def test_sha256_hex_is_flagged(self) -> None:
        issues = scan_safe_message(
            "abc123def4567890abc123def4567890abc123def4567890abc123def4567890")
        self.assertTrue(issues)

    def test_sql_fragment_is_flagged(self) -> None:
        issues = scan_safe_message(
            "SELECT * FROM event_log WHERE event_id = ?")
        self.assertTrue(issues)

    def test_dart_package_import_is_flagged(self) -> None:
        issues = scan_safe_message(
            "package:personal_os_storage_api/storage_api.dart")
        self.assertTrue(issues)

    def test_forbidden_substring_password_is_flagged(self) -> None:
        issues = scan_safe_message("user password rejected")
        self.assertTrue(issues)

    def test_forbidden_substring_recovery_code_is_flagged(self) -> None:
        issues = scan_safe_message("recovery code rotation required")
        self.assertTrue(issues)


class CrossAdapterParityTests(unittest.TestCase):
    """ADR-0014 §7 — same input must map to same wire_value across adapters."""

    def test_d4_violation_via_blob_and_via_schema_produce_same_wire(self) -> None:
        blob = PersistenceErrorMapper.map(
            BlobAccessDenied.d4_persistence_forbidden())
        schema = PersistenceErrorMapper.map(
            VaultSchemaViolation(
                message="D4 cannot enter persistent storage"))
        self.assertEqual(blob.wire_value, schema.wire_value)
        self.assertEqual(
            blob.wire_value, "persistence.d4_persistence_forbidden")

    def test_vault_locked_via_security_exception_in_both_paths(self) -> None:
        locked = PersistenceErrorMapper.map(
            SecurityException(code=SecurityErrorCode.VAULT_LOCKED))
        expired = PersistenceErrorMapper.map(
            SecurityException(code=SecurityErrorCode.UNLOCK_EXPIRED))
        self.assertEqual(locked.wire_value, expired.wire_value)
        self.assertEqual(locked.wire_value, "persistence.vault_locked")


class CLIOutputTests(unittest.TestCase):
    """ADR-0014 §7 — CLI prints a stable JSON wire-value table."""

    def test_cli_outputs_valid_json_with_17_entries(self) -> None:
        result = subprocess.run(
            [sys.executable, str(MODULE_PATH / "persistence_error.py")],
            capture_output=True,
            text=True,
            check=True,
        )
        table = json.loads(result.stdout)
        self.assertEqual(len(table), 17)
        names = {entry["code_name"] for entry in table}
        wires = {entry["wire_value"] for entry in table}
        self.assertEqual(len(names), 17)
        self.assertEqual(len(wires), 17)
        for entry in table:
            self.assertTrue(entry["wire_value"].startswith("persistence."))


class DataclassShapeTests(unittest.TestCase):
    """ADR-0014 §1 — PersistenceError exposes code/cause/safe_message."""

    def test_persistence_error_fields(self) -> None:
        error = PersistenceError(
            code=PersistenceErrorCode.VAULT_LOCKED,
            cause=None,
            safe_message="ctx",
        )
        self.assertEqual(error.code, PersistenceErrorCode.VAULT_LOCKED)
        self.assertIsNone(error.cause)
        self.assertEqual(error.safe_message, "ctx")

    def test_persistence_error_str_does_not_leak_cause(self) -> None:
        leaky = BlobAccessDenied(
            code="LEAK",
            reason="/home/user/secret.bin",
        )
        error = PersistenceError(
            code=PersistenceErrorCode.INTERNAL_ADAPTER_FAILURE,
            cause=leaky,
            safe_message="blocked",
        )
        rendered = str(error)
        self.assertIn("persistence.internal_adapter_failure", rendered)
        self.assertNotIn("/home/user/secret.bin", rendered)


if __name__ == "__main__":
    unittest.main()
