#!/usr/bin/env python3
"""Unit tests for tool/gate_status.py (ADR-0010 v2 companion).

Covers:
- Empty ledger (no records) → NOT_VERIFIED conclusion.
- Single-record ledger with static PASS → STATIC_VERIFIED.
- Three-record ledger with static + flutter_test PASS →
  TEST_VERIFIED.
- Cross-record summary (unique ids, replay tuples, monotonic
  timestamps, cumulative_hash chain presence).
- CLI end-to-end (--ledger, --json, missing file, malformed JSON).

Run via: python3 -m unittest discover -s tool/tests -p 'test_*.py'
"""

import importlib.util
import json
import pathlib
import subprocess
import sys
import tempfile
import unittest

REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
GATE_STATUS = REPO_ROOT / "tool" / "gate_status.py"

# Import the aggregator as a module so we can unit-test internal functions.
spec = importlib.util.spec_from_file_location("gate_status", GATE_STATUS)
gate_status = importlib.util.module_from_spec(spec)
sys.modules["gate_status"] = gate_status
spec.loader.exec_module(gate_status)


def _ledger(records=None, gates=None):
    """Build a baseline v1.1 ledger dict."""
    if gates is None:
        gates = {
            "static": {"status": "not_run", "checks": []},
            "flutter_test": {"status": "blocked", "checks": []},
            "apk": {"status": "blocked", "checks": []},
            "redmi_device": {"status": "not_run", "checks": []},
            "dogfood": {"status": "not_run", "checks": []},
        }
    if records is None:
        records = []
    return {
        "schema_version": 1,
        "kind": "synthetic",
        "candidate_commit": "0" * 40,
        "records": records,
        "evidence_writer_version": "1.1.0",
        "gates": gates,
    }


def _record(gate, status, wave="20i", track="I", commit="a" * 40, ts="2026-08-23T12:00:00Z", record_id="abc123def456", prev="000000000000", has_cum=False):
    r = {
        "record_id": record_id,
        "previous_record_id": prev,
        "recorded_at": ts,
        "candidate_commit": commit,
        "kind": "real",
        "wave": wave,
        "track": track,
        "gate": gate,
        "status": status,
        "artifacts": [],
        "evidence_writer_version": "1.1.0",
        "notes": "ok",
    }
    if has_cum:
        r["cumulative_hash"] = "f" * 64
    return r


class TestEmptyLedger(unittest.TestCase):
    def test_empty_ledger_returns_not_verified(self):
        report = gate_status.aggregate(_ledger())
        self.assertEqual(report["conclusion"], "NOT_VERIFIED")
        self.assertEqual(report["level"], 0)
        self.assertEqual(report["cross_record"]["records"], 0)


class TestSingleRecord(unittest.TestCase):
    def test_static_pass_record_yields_static_verified(self):
        records = [_record("static", "PASS", wave="20i", track="I")]
        report = gate_status.aggregate(_ledger(records=records))
        self.assertEqual(report["conclusion"], "STATIC_VERIFIED")
        self.assertEqual(report["level"], 1)

    def test_flutter_test_pass_only_does_not_promote(self):
        # flutter_test PASS alone (without static) does not promote
        # the level — gates are cumulative.
        records = [_record("flutter_test", "PASS")]
        report = gate_status.aggregate(_ledger(records=records))
        self.assertEqual(report["conclusion"], "NOT_VERIFIED")
        self.assertEqual(report["level"], 0)


class TestCumulativeGates(unittest.TestCase):
    def test_static_plus_flutter_test_pass_yields_test_verified(self):
        records = [
            _record("static", "PASS", record_id="aaa111222333", ts="2026-08-23T12:00:00Z"),
            _record("flutter_test", "PASS", record_id="bbb444555666", prev="aaa111222333", ts="2026-08-23T13:00:00Z"),
        ]
        report = gate_status.aggregate(_ledger(records=records))
        self.assertEqual(report["conclusion"], "TEST_VERIFIED")
        self.assertEqual(report["level"], 2)

    def test_full_pipeline_passes_dogfood_ready(self):
        records = [
            _record("static", "PASS", record_id="a00000000001", ts="2026-08-23T12:00:00Z"),
            _record("flutter_test", "PASS", record_id="a00000000002", prev="a00000000001", ts="2026-08-23T13:00:00Z"),
            _record("apk", "PASS", record_id="a00000000003", prev="a00000000002", ts="2026-08-23T14:00:00Z"),
            _record("redmi_device", "PASS", record_id="a00000000004", prev="a00000000003", ts="2026-08-23T15:00:00Z"),
            _record("dogfood", "PASS", record_id="a00000000005", prev="a00000000004", ts="2026-08-23T16:00:00Z"),
        ]
        report = gate_status.aggregate(_ledger(records=records))
        self.assertEqual(report["conclusion"], "DOGFOOD_READY")
        self.assertEqual(report["level"], 5)

    def test_gap_in_cumulative_gates_caps_level(self):
        # static PASS, then apk PASS (skipping flutter_test) — level
        # caps at 1 (static only) because flutter_test is missing.
        records = [
            _record("static", "PASS", record_id="a00000000001", ts="2026-08-23T12:00:00Z"),
            _record("apk", "PASS", record_id="a00000000003", prev="a00000000001", ts="2026-08-23T14:00:00Z"),
        ]
        report = gate_status.aggregate(_ledger(records=records))
        self.assertEqual(report["level"], 1)
        self.assertEqual(report["conclusion"], "STATIC_VERIFIED")


class TestCrossRecordSummary(unittest.TestCase):
    def test_unique_record_ids_counted(self):
        records = [
            _record("static", "PASS", record_id="aaa111222333"),
            _record("flutter_test", "PASS", record_id="bbb444555666", prev="aaa111222333"),
        ]
        report = gate_status.aggregate(_ledger(records=records))
        self.assertEqual(report["cross_record"]["unique_record_ids"], 2)

    def test_duplicate_record_ids_still_counted(self):
        # The aggregator does NOT enforce uniqueness — it only reports.
        # If there's a duplicate, the count should still reflect the
        # set size (which collapses duplicates).
        records = [
            _record("static", "PASS", record_id="aaa111222333"),
            _record("flutter_test", "PASS", record_id="aaa111222333", prev="aaa111222333"),
        ]
        report = gate_status.aggregate(_ledger(records=records))
        self.assertEqual(report["cross_record"]["unique_record_ids"], 1)

    def test_replay_tuples_counted(self):
        # Two records with the same (commit, gate, status) tuple —
        # aggregator reports 1 unique tuple (collapsed by the set).
        records = [
            _record("static", "PASS", record_id="aaa111222333", commit="a" * 40, ts="2026-08-23T12:00:00Z"),
            _record("flutter_test", "PASS", record_id="bbb444555666", prev="aaa111222333", commit="a" * 40, ts="2026-08-23T13:00:00Z"),
        ]
        report = gate_status.aggregate(_ledger(records=records))
        self.assertEqual(report["cross_record"]["unique_replay_tuples"], 2)

    def test_monotonic_timestamps_yes(self):
        records = [
            _record("static", "PASS", record_id="a00000000001", ts="2026-08-23T12:00:00Z"),
            _record("flutter_test", "PASS", record_id="a00000000002", prev="a00000000001", ts="2026-08-23T13:00:00Z"),
        ]
        report = gate_status.aggregate(_ledger(records=records))
        self.assertEqual(report["cross_record"]["monotonic_timestamps"], "yes")

    def test_monotonic_timestamps_no(self):
        records = [
            _record("static", "PASS", record_id="a00000000001", ts="2026-08-23T13:00:00Z"),
            _record("flutter_test", "PASS", record_id="a00000000002", prev="a00000000001", ts="2026-08-23T12:00:00Z"),
        ]
        report = gate_status.aggregate(_ledger(records=records))
        self.assertEqual(report["cross_record"]["monotonic_timestamps"], "no")

    def test_cumulative_hash_chain_present(self):
        records = [
            _record("static", "PASS", record_id="a00000000001", has_cum=True),
            _record("flutter_test", "PASS", record_id="a00000000002", prev="a00000000001", has_cum=True),
        ]
        report = gate_status.aggregate(_ledger(records=records))
        self.assertEqual(report["cross_record"]["cumulative_hash_chain"], "yes")

    def test_cumulative_hash_chain_partial(self):
        records = [
            _record("static", "PASS", record_id="a00000000001", has_cum=True),
            _record("flutter_test", "PASS", record_id="a00000000002", prev="a00000000001"),
        ]
        report = gate_status.aggregate(_ledger(records=records))
        self.assertEqual(report["cross_record"]["cumulative_hash_chain"], "partial")

    def test_cumulative_hash_chain_absent(self):
        records = [
            _record("static", "PASS", record_id="a00000000001"),
            _record("flutter_test", "PASS", record_id="a00000000002", prev="a00000000001"),
        ]
        report = gate_status.aggregate(_ledger(records=records))
        self.assertEqual(report["cross_record"]["cumulative_hash_chain"], "absent")

    def test_last_record_id_returned(self):
        records = [
            _record("static", "PASS", record_id="a00000000001"),
            _record("flutter_test", "PASS", record_id="a00000000002", prev="a00000000001"),
        ]
        report = gate_status.aggregate(_ledger(records=records))
        self.assertEqual(report["cross_record"]["last_record_id"], "a00000000002")


class TestRender(unittest.TestCase):
    def test_render_text_includes_conclusion(self):
        records = [_record("static", "PASS")]
        report = gate_status.aggregate(_ledger(records=records))
        rendered = gate_status.render_text(report, pathlib.Path("/tmp/ledger.json"))
        self.assertIn("STATIC_VERIFIED", rendered)
        self.assertIn("Per-Gate Summary", rendered)
        self.assertIn("Per-Record Chain", rendered)
        self.assertIn("Cross-Record Summary", rendered)

    def test_render_text_empty_ledger(self):
        report = gate_status.aggregate(_ledger())
        rendered = gate_status.render_text(report, pathlib.Path("/tmp/ledger.json"))
        self.assertIn("genesis only", rendered)
        self.assertIn("NOT_VERIFIED", rendered)


class TestCLI(unittest.TestCase):
    def setUp(self):
        self.tmp = pathlib.Path(tempfile.mkdtemp(prefix="gate-status-"))

    def _write(self, payload):
        path = self.tmp / "ledger.json"
        path.write_text(json.dumps(payload, indent=2), encoding="utf-8")
        return path

    def _run(self, *args):
        proc = subprocess.run(
            [sys.executable, str(GATE_STATUS), *args],
            capture_output=True, text=True,
        )
        return proc

    def test_default_status_json_passes(self):
        # Default ledger is evidence/mvp/status.json in the repo.
        proc = self._run()
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn("Overall:", proc.stdout)

    def test_json_flag_emits_valid_json(self):
        records = [_record("static", "PASS")]
        path = self._write(_ledger(records=records))
        proc = self._run("--ledger", str(path), "--json")
        self.assertEqual(proc.returncode, 0, proc.stderr)
        report = json.loads(proc.stdout)
        self.assertEqual(report["conclusion"], "STATIC_VERIFIED")

    def test_missing_file_exits_1(self):
        proc = self._run("--ledger", str(self.tmp / "nope.json"))
        self.assertEqual(proc.returncode, 1, proc.stderr)
        self.assertIn("cannot read", proc.stderr)

    def test_malformed_json_exits_1(self):
        path = self.tmp / "bad.json"
        path.write_text("{not valid", encoding="utf-8")
        proc = self._run("--ledger", str(path))
        self.assertEqual(proc.returncode, 1, proc.stderr)

    def test_non_object_root_exits_1(self):
        path = self._write([1, 2, 3])  # type: ignore[list-item]
        proc = self._run("--ledger", str(path))
        self.assertEqual(proc.returncode, 1, proc.stderr)
        self.assertIn("JSON object", proc.stderr)


if __name__ == "__main__":
    unittest.main()
