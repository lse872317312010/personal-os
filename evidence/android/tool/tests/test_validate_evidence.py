"""Unit tests for the evidence validator ADR-0014 §6 forbidden-fields rule."""

from __future__ import annotations

import json
import os
import sys
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[4]
EVIDENCE_TOOL = REPO_ROOT / "evidence" / "android" / "tool"
sys.path.insert(0, str(EVIDENCE_TOOL))

import validate_evidence  # noqa: E402

FIXTURES = EVIDENCE_TOOL / "tests" / "fixtures"
VALID_RECORD = REPO_ROOT / "evidence" / "android" / "records" / "synthetic.example.json"


def _load(path: Path) -> dict:
    with path.open(encoding="utf-8") as source:
        return json.load(source)


class PositiveRecordTests(unittest.TestCase):
    """ADR-0014 §1 — error.code + safe_message is the safe shape."""

    def test_synthetic_example_record_validates(self) -> None:
        validate_evidence.main(str(VALID_RECORD))

    def test_error_field_with_code_and_safe_message_passes(self) -> None:
        record = _load(VALID_RECORD)
        record["error"] = {
            "code": "persistence.d4_persistence_forbidden",
            "safe_message": "D4 rejected at boundary",
        }
        validate_evidence.main(_write_temp(record))

    def test_error_field_with_null_safe_message_passes(self) -> None:
        record = _load(VALID_RECORD)
        record["error"] = {"code": "persistence.internal_adapter_failure",
                           "safe_message": None}
        validate_evidence.main(_write_temp(record))

    def test_record_without_error_still_passes(self) -> None:
        record = _load(VALID_RECORD)
        record.pop("error", None)
        validate_evidence.main(_write_temp(record))


class ForbiddenFieldsWalkerTests(unittest.TestCase):
    """ADR-0014 §6 — recursive walker rejects cause / stack_trace."""

    def test_cause_at_root_flagged(self) -> None:
        issues = validate_evidence._walk_forbidden_error_fields(
            {"cause": "leak"})
        self.assertEqual(len(issues), 1)
        self.assertIn("forbidden error-debugging field", issues[0])

    def test_cause_inside_error_object_flagged(self) -> None:
        value = {"error": {"code": "persistence.vault_locked",
                           "cause": "leak"}}
        issues = validate_evidence._walk_forbidden_error_fields(value)
        self.assertEqual(len(issues), 1)
        self.assertIn("$.error.cause", issues[0])

    def test_stack_trace_inside_error_object_flagged(self) -> None:
        value = {"error": {"code": "persistence.vault_unlock_failed",
                           "stack_trace": "#0 main"}}
        issues = validate_evidence._walk_forbidden_error_fields(value)
        self.assertEqual(len(issues), 1)
        self.assertIn("stack_trace", issues[0])

    def test_camelcase_stack_trace_variant_flagged(self) -> None:
        value = {"error": {"code": "persistence.vault_locked",
                           "stackTrace": "#0 main"}}
        issues = validate_evidence._walk_forbidden_error_fields(value)
        self.assertEqual(len(issues), 1)

    def test_inner_exception_variant_flagged(self) -> None:
        issues = validate_evidence._walk_forbidden_error_fields(
            {"inner_exception": "leak"})
        self.assertEqual(len(issues), 1)

    def test_camelcase_inner_exception_variant_flagged(self) -> None:
        issues = validate_evidence._walk_forbidden_error_fields(
            {"innerException": "leak"})
        self.assertEqual(len(issues), 1)

    def test_raw_exception_variant_flagged(self) -> None:
        issues = validate_evidence._walk_forbidden_error_fields(
            {"raw_exception": "leak"})
        self.assertEqual(len(issues), 1)

    def test_cause_nested_in_capabilities_flagged(self) -> None:
        value = {"capabilities": {"protectionLevel": "unavailable",
                                  "cause": "nested"}}
        issues = validate_evidence._walk_forbidden_error_fields(value)
        self.assertEqual(len(issues), 1)
        self.assertIn("$.capabilities.cause", issues[0])

    def test_cause_nested_in_scenario_list_flagged(self) -> None:
        value = {"scenarios": [{"id": "x", "cause": "nested"},
                                {"id": "y"}]}
        issues = validate_evidence._walk_forbidden_error_fields(value)
        self.assertEqual(len(issues), 1)
        self.assertIn("$.scenarios[0].cause", issues[0])

    def test_clean_value_passes(self) -> None:
        issues = validate_evidence._walk_forbidden_error_fields({
            "error": {"code": "persistence.vault_locked",
                      "safe_message": "vault locked"},
            "scenarios": [{"id": "x", "result": "pass"}],
        })
        self.assertEqual(issues, [])

    def test_multiple_violations_all_reported(self) -> None:
        value = {
            "cause": "root",
            "error": {"code": "x", "cause": "err", "stack_trace": "st"},
            "scenarios": [{"id": "x", "cause": "nested"}],
        }
        issues = validate_evidence._walk_forbidden_error_fields(value)
        self.assertEqual(len(issues), 4)


class NegativeFixtureTests(unittest.TestCase):
    """ADR-0014 §6 — fixture files exercise the validator end-to-end."""

    def test_fixture_with_cause_is_rejected(self) -> None:
        with self.assertRaises(ValueError) as ctx:
            validate_evidence.main(
                str(FIXTURES / "with_cause.json"))
        self.assertIn("forbidden error-debugging field", str(ctx.exception))
        self.assertIn("cause", str(ctx.exception))

    def test_fixture_with_stack_trace_is_rejected(self) -> None:
        with self.assertRaises(ValueError) as ctx:
            validate_evidence.main(
                str(FIXTURES / "with_stack_trace.json"))
        self.assertIn("forbidden error-debugging field", str(ctx.exception))
        self.assertIn("stack_trace", str(ctx.exception))

    def test_fixture_with_nested_cause_is_rejected(self) -> None:
        with self.assertRaises(ValueError) as ctx:
            validate_evidence.main(
                str(FIXTURES / "with_nested_cause.json"))
        self.assertIn("forbidden error-debugging field", str(ctx.exception))
        self.assertIn("$.capabilities.cause", str(ctx.exception))


class ErrorFieldShapeTests(unittest.TestCase):
    """ADR-0014 §1 — validate_error_field enforces shape constraints."""

    def test_error_must_be_object(self) -> None:
        with self.assertRaises(ValueError):
            validate_evidence.validate_error_field("not a dict")

    def test_error_rejects_unlisted_field(self) -> None:
        with self.assertRaises(ValueError):
            validate_evidence.validate_error_field(
                {"code": "persistence.vault_locked", "extra": "x"})

    def test_error_code_must_be_non_empty_string(self) -> None:
        with self.assertRaises(ValueError):
            validate_evidence.validate_error_field({"code": ""})
        with self.assertRaises(ValueError):
            validate_evidence.validate_error_field({"code": 123})

    def test_error_safe_message_must_be_string_or_null(self) -> None:
        with self.assertRaises(ValueError):
            validate_evidence.validate_error_field({
                "code": "persistence.vault_locked",
                "safe_message": 123,
            })

    def test_error_with_only_code_passes(self) -> None:
        validate_evidence.validate_error_field(
            {"code": "persistence.vault_locked"})


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

_TEMP_PATHS: list[Path] = []


def _write_temp(record: dict) -> str:
    import tempfile

    fd, path = tempfile.mkstemp(prefix="evidence_test_", suffix=".json")
    with os.fdopen(fd, "w", encoding="utf-8") as handle:
        json.dump(record, handle)
    _TEMP_PATHS.append(Path(path))
    return path


def tearDownModule() -> None:  # noqa: N802
    for path in _TEMP_PATHS:
        try:
            path.unlink(missing_ok=True)
        except OSError:
            pass


if __name__ == "__main__":
    unittest.main()
