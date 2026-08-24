import copy
import hashlib
import json
import tempfile
import unittest
from pathlib import Path

from tool import evidence_ledger


COMMIT_A = "a" * 40
COMMIT_B = "b" * 40


def make_record(previous, commit=COMMIT_A, gate="static", status="PASS",
                kind="real", error=None):
    record = {
        "previous_record_id": previous,
        "recorded_at": "2026-08-24T00:00:00Z",
        "candidate_commit": commit,
        "kind": kind,
        "wave": "replacement",
        "track": "I",
        "gate": gate,
        "status": status,
        "artifacts": [{"name": "check.log", "sha256": "c" * 64}],
        "notes": "verified by CI",
        "evidence_writer_version": "2.0.0",
        "error": error,
    }
    record["record_hash"] = evidence_ledger.compute_record_hash(record)
    record["record_id"] = evidence_ledger.compute_record_id(
        previous, record["record_hash"])
    return record


def make_ledger(records):
    return {
        "schema_version": 2,
        "kind": "real",
        "candidate_commit": COMMIT_A,
        "records": records,
        # Deliberately claims PASS; aggregator must not trust this legacy tree.
        "gates": {"static": {"status": "pass"}},
    }


class LedgerIntegrityTests(unittest.TestCase):
    def test_full_record_fields_are_hashed(self):
        original = make_record(evidence_ledger.GENESIS)
        for field in ("recorded_at", "candidate_commit", "kind", "wave",
                      "track", "gate", "status", "artifacts", "notes",
                      "evidence_writer_version"):
            changed = copy.deepcopy(original)
            if field == "artifacts":
                changed[field][0]["name"] = "changed.log"
            elif field == "candidate_commit":
                changed[field] = COMMIT_B
            elif field == "status":
                changed[field] = "FAIL"
            else:
                changed[field] = str(changed[field]) + "-changed"
            with self.subTest(field=field):
                with self.assertRaises(evidence_ledger.LedgerError):
                    evidence_ledger.validate_ledger(make_ledger([changed]))

    def test_reordering_breaks_previous_record_binding(self):
        first = make_record(evidence_ledger.GENESIS)
        second = make_record(first["record_id"], gate="flutter_test")
        with self.assertRaises(evidence_ledger.LedgerError):
            evidence_ledger.validate_ledger(make_ledger([second, first]))

    def test_candidate_commit_is_part_of_record_hash(self):
        record = make_record(evidence_ledger.GENESIS)
        record["candidate_commit"] = COMMIT_B
        with self.assertRaises(evidence_ledger.LedgerError):
            evidence_ledger.validate_ledger(make_ledger([record]))


class SafeErrorTests(unittest.TestCase):
    def test_allowlisted_error_passes(self):
        record = make_record(
            evidence_ledger.GENESIS,
            status="BLOCKED",
            error={"code": "persistence.vault_locked", "safe_message": None},
        )
        evidence_ledger.validate_ledger(make_ledger([record]))

    def test_nested_debug_fields_fail(self):
        for key in ("cause", "stack_trace", "stackTrace", "innerException"):
            with self.subTest(key=key):
                with self.assertRaises(evidence_ledger.LedgerError):
                    evidence_ledger.validate_safe_error({
                        "code": "persistence.vault_locked",
                        "safe_message": "safe",
                        key: "secret",
                    })


class TruthfulAggregationTests(unittest.TestCase):
    def test_no_selector_never_promotes_a_candidate(self):
        result = evidence_ledger.aggregate(
            make_ledger([make_record(evidence_ledger.GENESIS)]), None)
        self.assertEqual(result["overall"], "NOT_VERIFIED")
        self.assertEqual(result["records_considered"], 0)

    def test_wrong_candidate_is_not_verified(self):
        ledger = make_ledger([make_record(evidence_ledger.GENESIS)])
        result = evidence_ledger.aggregate(ledger, COMMIT_B)
        self.assertEqual(result["overall"], "NOT_VERIFIED")
        self.assertEqual(result["records_considered"], 0)

    def test_selected_real_candidate_is_verified(self):
        ledger = make_ledger([make_record(evidence_ledger.GENESIS)])
        result = evidence_ledger.aggregate(ledger, COMMIT_A)
        self.assertEqual(result["overall"], "STATIC_VERIFIED")
        self.assertTrue(result["passed"]["static"])

    def test_synthetic_pass_does_not_promote(self):
        ledger = make_ledger([
            make_record(evidence_ledger.GENESIS, kind="synthetic")
        ])
        result = evidence_ledger.aggregate(ledger, COMMIT_A)
        self.assertEqual(result["overall"], "NOT_VERIFIED")

    def test_legacy_gate_status_is_ignored(self):
        ledger = make_ledger([])
        result = evidence_ledger.aggregate(ledger, COMMIT_A)
        self.assertEqual(result["overall"], "NOT_VERIFIED")
        self.assertTrue(result["legacy_gates_ignored"])

    def test_root_synthetic_kind_cannot_promote_real_records(self):
        ledger = make_ledger([make_record(evidence_ledger.GENESIS)])
        ledger["kind"] = "synthetic"
        result = evidence_ledger.aggregate(ledger, COMMIT_A)
        self.assertEqual(result["overall"], "NOT_VERIFIED")

    def test_selector_must_match_ledger_candidate(self):
        ledger = make_ledger([make_record(evidence_ledger.GENESIS, commit=COMMIT_B)])
        result = evidence_ledger.aggregate(ledger, COMMIT_B)
        self.assertEqual(result["overall"], "NOT_VERIFIED")
        self.assertEqual(result["records_considered"], 0)

    def test_aggregate_validates_before_counting_records(self):
        ledger = make_ledger([make_record(evidence_ledger.GENESIS)])
        ledger["records"][0]["notes"] = "tampered"
        with self.assertRaises(evidence_ledger.LedgerError):
            evidence_ledger.aggregate(ledger, COMMIT_A)


if __name__ == "__main__":
    unittest.main()
