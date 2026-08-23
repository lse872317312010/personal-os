#!/usr/bin/env python3
"""Unit tests for evidence/android/tool/validate_evidence.py (ADR-0010 v2).

Covers:
- v1 schema + chain (record_id re-computation, previous_record_id linking,
  artifacts, kind/status enums, RFC3339 timestamps).
- v2 cross-record consistency (anti-duplicate-id, anti-replay, monotonic
  timestamps, optional cumulative_hash chain).
- Android device record schema dispatch path.

Run via: python3 -m unittest discover -s evidence/android/tool/tests \\
    -p 'test_*.py'
"""

import datetime
import hashlib
import importlib.util
import json
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile
import unittest

REPO_ROOT = pathlib.Path(__file__).resolve().parents[4]
VALIDATOR = (
    REPO_ROOT / "evidence" / "android" / "tool" / "validate_evidence.py"
)

# Import the validator as a module so we can unit-test internal functions.
spec = importlib.util.spec_from_file_location("validate_evidence", VALIDATOR)
validate_evidence = importlib.util.module_from_spec(spec)
sys.modules["validate_evidence"] = validate_evidence
spec.loader.exec_module(validate_evidence)


RECORD_ID_LEN = 12
GENESIS_PREV_ID = "0" * RECORD_ID_LEN
GENESIS_CUMULATIVE_HASH = "0" * 64


def _rid(prev, commit, ts, gate, status):
    data = f"{prev}{commit}{ts}{gate}{status}"
    return hashlib.sha256(data.encode("utf-8")).hexdigest()[:RECORD_ID_LEN]


def _cum(prev_cum, rid):
    return hashlib.sha256(
        f"{prev_cum}{rid}".encode("utf-8")
    ).hexdigest()


def _base_record(
    prev_id=GENESIS_PREV_ID,
    commit="a" * 40,
    ts="2026-08-23T12:00:00Z",
    kind="real",
    wave="20g",
    track="I",
    gate="G4",
    status="PASS",
    notes="ok",
    artifacts=None,
    cumulative_hash=None,
):
    rid = _rid(prev_id, commit, ts, gate, status)
    record = {
        "record_id": rid,
        "previous_record_id": prev_id,
        "recorded_at": ts,
        "candidate_commit": commit,
        "kind": kind,
        "wave": wave,
        "track": track,
        "gate": gate,
        "status": status,
        "artifacts": artifacts if artifacts is not None else [],
        "evidence_writer_version": "1.1.0",
        "notes": notes,
    }
    if cumulative_hash is not None:
        record["cumulative_hash"] = cumulative_hash
    return record


def _ledger(records, commit="a" * 40):
    return {
        "schema_version": 1,
        "kind": "synthetic",
        "candidate_commit": commit,
        "records": records,
        "evidence_writer_version": "1.1.0",
    }


def _three_records_with_cum():
    """Build a 3-record ledger that satisfies every v1 + v2 rule."""
    commit_a = "a" * 40
    commit_b = "b" * 40
    commit_c = "c" * 40
    ts1 = "2026-08-23T12:00:00Z"
    ts2 = "2026-08-23T13:00:00Z"
    ts3 = "2026-08-23T14:00:00Z"
    r1 = _base_record(
        prev_id=GENESIS_PREV_ID, commit=commit_a, ts=ts1, gate="G4",
        cumulative_hash=_cum(GENESIS_CUMULATIVE_HASH, _rid(GENESIS_PREV_ID, commit_a, ts1, "G4", "PASS")),
    )
    r2 = _base_record(
        prev_id=r1["record_id"], commit=commit_b, ts=ts2, gate="G3",
        cumulative_hash=_cum(r1["cumulative_hash"], _rid(r1["record_id"], commit_b, ts2, "G3", "PASS")),
    )
    r3 = _base_record(
        prev_id=r2["record_id"], commit=commit_c, ts=ts3, gate="G4",
        # Different commit from r1, so (commit, gate, status) is unique
        # even though gate is G4 again.
        cumulative_hash=_cum(r2["cumulative_hash"], _rid(r2["record_id"], commit_c, ts3, "G4", "PASS")),
    )
    return [r1, r2, r3]


class TestChainHappyPath(unittest.TestCase):
    def test_empty_records_passes(self):
        validate_evidence.validate_chain(_ledger([]))

    def test_three_records_with_cumulative_hash_passes(self):
        validate_evidence.validate_chain(_ledger(_three_records_with_cum()))

    def test_single_record_no_cumulative_passes(self):
        validate_evidence.validate_chain(
            _ledger([_base_record()])
        )


class TestChainV1Schema(unittest.TestCase):
    def test_schema_version_not_1_fails(self):
        with self.assertRaises(ValueError):
            validate_evidence.validate_chain({
                "schema_version": 2, "kind": "synthetic",
                "candidate_commit": "a" * 40, "records": [],
            })

    def test_invalid_kind_fails(self):
        with self.assertRaises(ValueError):
            validate_evidence.validate_chain({
                "schema_version": 1, "kind": "experiment",
                "candidate_commit": "a" * 40, "records": [],
            })

    def test_invalid_candidate_commit_length_fails(self):
        with self.assertRaises(ValueError):
            validate_evidence.validate_chain({
                "schema_version": 1, "kind": "synthetic",
                "candidate_commit": "abc", "records": [],
            })

    def test_missing_required_record_field_fails(self):
        r = _base_record()
        del r["notes"]
        with self.assertRaises(ValueError):
            validate_evidence.validate_chain(_ledger([r]))

    def test_unknown_record_field_fails(self):
        r = _base_record()
        r["mystery_field"] = "nope"
        with self.assertRaises(ValueError):
            validate_evidence.validate_chain(_ledger([r]))

    def test_invalid_record_id_format_fails(self):
        r = _base_record()
        r["record_id"] = "XYZ"  # not hex
        with self.assertRaises(ValueError):
            validate_evidence.validate_chain(_ledger([r]))

    def test_invalid_kind_value_fails(self):
        r = _base_record()
        r["kind"] = "imaginary"
        with self.assertRaises(ValueError):
            validate_evidence.validate_chain(_ledger([r]))

    def test_invalid_status_value_fails(self):
        r = _base_record()
        r["status"] = "MAYBE"
        with self.assertRaises(ValueError):
            validate_evidence.validate_chain(_ledger([r]))

    def test_invalid_artifact_sha256_fails(self):
        r = _base_record(artifacts=[
            {"name": "foo.dart", "sha256": "not-a-hex"}
        ])
        with self.assertRaises(ValueError):
            validate_evidence.validate_chain(_ledger([r]))

    def test_artifact_extra_field_fails(self):
        r = _base_record(artifacts=[
            {"name": "foo.dart", "sha256": "", "extra": "no"}
        ])
        with self.assertRaises(ValueError):
            validate_evidence.validate_chain(_ledger([r]))

    def test_malformed_recorded_at_fails(self):
        r = _base_record(ts="not-a-timestamp")
        with self.assertRaises(ValueError):
            validate_evidence.validate_chain(_ledger([r]))


class TestChainV1Linking(unittest.TestCase):
    def test_previous_record_id_mismatch_fails(self):
        r1 = _base_record()
        r2 = _base_record(
            prev_id="deadbeefdead",  # not r1's record_id
            ts="2026-08-23T13:00:00Z",
        )
        with self.assertRaises(ValueError) as ctx:
            validate_evidence.validate_chain(_ledger([r1, r2]))
        self.assertIn("chain broken", str(ctx.exception))

    def test_record_id_recompute_mismatch_fails(self):
        r1 = _base_record()
        # Tamper with record_id (but keep prev_id intact).
        r1["record_id"] = "000000000000"
        with self.assertRaises(ValueError) as ctx:
            validate_evidence.validate_chain(_ledger([r1]))
        self.assertIn("tampered", str(ctx.exception).lower())


class TestCrossRecordV2AntiDuplicateId(unittest.TestCase):
    def test_duplicate_record_id_fails(self):
        # Bypass the v1 record_id-recompute check (which would otherwise
        # fire first because record_id is deterministic from content)
        # by invoking the v2 cross-record check directly. Two records
        # carry the same record_id — the v2 anti-duplicate-id rule must
        # reject them.
        r1 = _base_record(commit="a" * 40)
        r2 = _base_record(
            prev_id=r1["record_id"],
            commit="b" * 40,
            ts="2026-08-23T13:00:00Z",
            gate="G3",  # different gate → no replay
        )
        r2["record_id"] = r1["record_id"]  # force duplicate
        with self.assertRaises(ValueError) as ctx:
            validate_evidence._validate_cross_record_consistency([r1, r2])
        self.assertIn("duplicate record_id", str(ctx.exception))


class TestCrossRecordV2AntiReplay(unittest.TestCase):
    def test_replay_same_commit_gate_status_fails(self):
        # Two records with identical (commit, gate, status) — even though
        # timestamps differ — must be rejected as a replay.
        commit = "a" * 40
        r1 = _base_record(prev_id=GENESIS_PREV_ID, commit=commit, ts="2026-08-23T12:00:00Z", gate="G4")
        r2 = _base_record(
            prev_id=r1["record_id"], commit=commit,
            ts="2026-08-23T13:00:00Z", gate="G4",
        )
        with self.assertRaises(ValueError) as ctx:
            validate_evidence.validate_chain(_ledger([r1, r2]))
        self.assertIn("replay detected", str(ctx.exception))

    def test_same_commit_different_gate_passes(self):
        # Same commit but different gate is allowed (a single commit
        # can earn multiple distinct gates).
        commit = "a" * 40
        r1 = _base_record(prev_id=GENESIS_PREV_ID, commit=commit, ts="2026-08-23T12:00:00Z", gate="G4")
        r2 = _base_record(
            prev_id=r1["record_id"], commit=commit,
            ts="2026-08-23T13:00:00Z", gate="G3",
        )
        validate_evidence.validate_chain(_ledger([r1, r2]))

    def test_same_commit_same_gate_different_status_passes(self):
        # Same commit, same gate, but different status (PASS then FAIL)
        # is allowed — represents a regression at the same commit.
        commit = "a" * 40
        r1 = _base_record(prev_id=GENESIS_PREV_ID, commit=commit, ts="2026-08-23T12:00:00Z", gate="G4", status="PASS")
        r2 = _base_record(
            prev_id=r1["record_id"], commit=commit,
            ts="2026-08-23T13:00:00Z", gate="G4", status="FAIL",
        )
        validate_evidence.validate_chain(_ledger([r1, r2]))


class TestCrossRecordV2MonotonicTimestamps(unittest.TestCase):
    def test_decreasing_timestamp_fails(self):
        r1 = _base_record(prev_id=GENESIS_PREV_ID, ts="2026-08-23T13:00:00Z", gate="G4")
        r2 = _base_record(
            prev_id=r1["record_id"], commit="b" * 40,
            ts="2026-08-23T12:00:00Z", gate="G3",  # earlier than r1
        )
        with self.assertRaises(ValueError) as ctx:
            validate_evidence.validate_chain(_ledger([r1, r2]))
        self.assertIn("non-decreasing", str(ctx.exception))

    def test_equal_timestamps_pass(self):
        # Ties are allowed.
        r1 = _base_record(prev_id=GENESIS_PREV_ID, commit="a" * 40, ts="2026-08-23T12:00:00Z", gate="G4")
        r2 = _base_record(
            prev_id=r1["record_id"], commit="b" * 40,
            ts="2026-08-23T12:00:00Z", gate="G3",
        )
        validate_evidence.validate_chain(_ledger([r1, r2]))


class TestCrossRecordV2CumulativeHash(unittest.TestCase):
    def test_genesis_cumulative_hash_mismatch_fails(self):
        r1 = _base_record(prev_id=GENESIS_PREV_ID)
        r1["cumulative_hash"] = "f" * 64  # wrong
        with self.assertRaises(ValueError) as ctx:
            validate_evidence.validate_chain(_ledger([r1]))
        self.assertIn("genesis", str(ctx.exception).lower())

    def test_cumulative_hash_chain_mismatch_fails(self):
        r1 = _base_record(prev_id=GENESIS_PREV_ID)
        r1["cumulative_hash"] = _cum(
            GENESIS_CUMULATIVE_HASH, r1["record_id"]
        )
        r2 = _base_record(
            prev_id=r1["record_id"], commit="b" * 40,
            ts="2026-08-23T13:00:00Z", gate="G3",
        )
        r2["cumulative_hash"] = "f" * 64  # wrong
        with self.assertRaises(ValueError) as ctx:
            validate_evidence.validate_chain(_ledger([r1, r2]))
        self.assertIn("cumulative_hash", str(ctx.exception))

    def test_partial_cumulative_hash_declaration_fails(self):
        # r1 has it, r2 doesn't — must fail.
        r1 = _base_record(prev_id=GENESIS_PREV_ID)
        r1["cumulative_hash"] = _cum(GENESIS_CUMULATIVE_HASH, r1["record_id"])
        r2 = _base_record(
            prev_id=r1["record_id"], commit="b" * 40,
            ts="2026-08-23T13:00:00Z", gate="G3",
        )
        # r2 lacks cumulative_hash
        with self.assertRaises(ValueError) as ctx:
            validate_evidence.validate_chain(_ledger([r1, r2]))
        self.assertIn("once declared on any record", str(ctx.exception))

    def test_invalid_cumulative_hash_format_fails(self):
        r1 = _base_record(prev_id=GENESIS_PREV_ID)
        r1["cumulative_hash"] = "xyz"  # not 64-hex
        with self.assertRaises(ValueError) as ctx:
            validate_evidence.validate_chain(_ledger([r1]))
        self.assertIn("cumulative_hash", str(ctx.exception))

    def test_three_records_with_correct_cumulative_chain_passes(self):
        validate_evidence.validate_chain(
            _ledger(_three_records_with_cum())
        )

    def test_cumulative_chain_breaks_if_record_id_tampered(self):
        # Cross-record cascade test: r1's record_id is tampered AFTER
        # the cumulative_hash chain has been computed. The v2 cross-
        # record check (which doesn't recompute record_id) must detect
        # that r1.cumulative_hash no longer matches SHA256(GENESIS +
        # r1.record_id) and fail.
        r1 = _base_record(prev_id=GENESIS_PREV_ID)
        # Stale cumulative_hash computed against the ORIGINAL r1.record_id.
        r1["cumulative_hash"] = _cum(GENESIS_CUMULATIVE_HASH, r1["record_id"])
        r2 = _base_record(
            prev_id=r1["record_id"], commit="b" * 40,
            ts="2026-08-23T13:00:00Z", gate="G3",
        )
        r2["cumulative_hash"] = _cum(r1["cumulative_hash"], r2["record_id"])
        # Tamper r1.record_id in place. r1.cumulative_hash is now stale
        # (computed against the original record_id, not the tampered
        # one). The v2 cross-record check must detect the mismatch.
        r1["record_id"] = "aabbccddeeff"
        with self.assertRaises(ValueError) as ctx:
            validate_evidence._validate_cross_record_consistency([r1, r2])
        # Either r1.cumulative_hash fails genesis (because r1.record_id
        # changed) OR r2.cumulative_hash fails chain. Either way,
        # the test exercises the cross-record hash cascade.
        self.assertIn("cumulative_hash", str(ctx.exception))


class TestAndroidRecordDispatch(unittest.TestCase):
    def test_android_synthetic_record_validates(self):
        record_path = (
            REPO_ROOT / "evidence" / "android" / "records"
            / "synthetic.example.json"
        )
        with open(record_path, encoding="utf-8") as f:
            value = json.load(f)
        # Should not raise.
        validate_evidence.validate_android_record(value)

    def test_unknown_file_shape_fails(self):
        # main() dispatches by schema shape: {schema_version, records}
        # → validate_chain; {schemaVersion, scenarios} → android. A
        # file with neither shape must raise "unrecognized".
        tmp = pathlib.Path(tempfile.mkdtemp(prefix="ev-shape-"))
        path = tmp / "weird.json"
        path.write_text(json.dumps({"weird": True}), encoding="utf-8")
        with self.assertRaises(ValueError) as ctx:
            validate_evidence.main(str(path))
        self.assertIn("unrecognized", str(ctx.exception).lower())


class TestCLI(unittest.TestCase):
    """End-to-end CLI tests against on-disk JSON fixtures."""

    def setUp(self):
        self.tmp = pathlib.Path(tempfile.mkdtemp(prefix="ev-test-"))

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def _write(self, payload):
        path = self.tmp / "ledger.json"
        path.write_text(json.dumps(payload, indent=2), encoding="utf-8")
        return path

    def _run(self, *args):
        proc = subprocess.run(
            [sys.executable, str(VALIDATOR), *args],
            capture_output=True, text=True,
        )
        return proc

    def test_synthetic_example_fixture_passes(self):
        path = (
            REPO_ROOT / "evidence" / "mvp" / "synthetic.example.json"
        )
        proc = self._run(str(path))
        self.assertEqual(proc.returncode, 0, proc.stderr)

    def test_empty_status_fixture_passes(self):
        path = REPO_ROOT / "evidence" / "mvp" / "status.json"
        proc = self._run(str(path))
        self.assertEqual(proc.returncode, 0, proc.stderr)

    def test_android_synthetic_fixture_passes(self):
        path = (
            REPO_ROOT / "evidence" / "android" / "records"
            / "synthetic.example.json"
        )
        proc = self._run(str(path))
        self.assertEqual(proc.returncode, 0, proc.stderr)

    def test_three_records_with_cumulative_passes_cli(self):
        path = self._write(_ledger(_three_records_with_cum()))
        proc = self._run(str(path))
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn("cumulative_hash=yes", proc.stderr)

    def test_replay_fails_cli(self):
        commit = "a" * 40
        r1 = _base_record(prev_id=GENESIS_PREV_ID, commit=commit, ts="2026-08-23T12:00:00Z", gate="G4")
        r2 = _base_record(prev_id=r1["record_id"], commit=commit, ts="2026-08-23T13:00:00Z", gate="G4")
        path = self._write(_ledger([r1, r2]))
        proc = self._run(str(path))
        self.assertEqual(proc.returncode, 1, proc.stderr)
        self.assertIn("replay", proc.stderr)

    def test_missing_argument_exits_2(self):
        proc = self._run()
        self.assertEqual(proc.returncode, 2)

    def test_nonexistent_file_exits_1(self):
        proc = self._run(str(self.tmp / "nope.json"))
        self.assertEqual(proc.returncode, 1)


if __name__ == "__main__":
    unittest.main()
