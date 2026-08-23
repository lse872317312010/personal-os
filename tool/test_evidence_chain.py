#!/usr/bin/env python3
"""Unit tests for ADR-0010 Evidence Ledger Chain logic.

Run with:
    python3 tool/test_evidence_chain.py

Exit 0 if all tests pass, non-zero otherwise. Tests cover:
- record_id derivation determinism and stability
- genesis previous_record_id sentinel
- chain append via the writer's _append_record path
- chain validation detects tampering and re-ordering
- backward-compat: gate-based mutation still works alongside records
"""

from __future__ import annotations

import importlib.util
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


def _load_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec is not None and spec.loader is not None
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


REPO_ROOT = Path(__file__).resolve().parent.parent
WRITER_PATH = REPO_ROOT / "tool" / "evidence_writer.py"
VALIDATOR_PATH = REPO_ROOT / "evidence" / "android" / "tool" / "validate_evidence.py"


def _ok(label: str) -> None:
    print(f"PASS  {label}")


def _fail(label: str, detail: str = "") -> None:
    print(f"FAIL  {label}: {detail}", file=sys.stderr)
    raise SystemExit(1)


def test_record_id_deterministic(writer) -> None:
    rid1 = writer._compute_record_id(
        "0" * 12, "a" * 40, "2026-08-23T00:00:00Z", "G4", "PASS"
    )
    rid2 = writer._compute_record_id(
        "0" * 12, "a" * 40, "2026-08-23T00:00:00Z", "G4", "PASS"
    )
    if rid1 != rid2:
        _fail("record_id determinism", f"{rid1} != {rid2}")
    if len(rid1) != 12:
        _fail("record_id length", f"got {len(rid1)}")
    _ok("record_id derivation is deterministic and 12-hex")


def test_record_id_changes_on_input(writer) -> None:
    base = writer._compute_record_id("0" * 12, "a" * 40, "T", "G4", "PASS")
    if writer._compute_record_id("1" * 12, "a" * 40, "T", "G4", "PASS") == base:
        _fail("record_id sensitivity", "previous_record_id did not change hash")
    if writer._compute_record_id("0" * 12, "b" * 40, "T", "G4", "PASS") == base:
        _fail("record_id sensitivity", "candidate_commit did not change hash")
    if writer._compute_record_id("0" * 12, "a" * 40, "T2", "G4", "PASS") == base:
        _fail("record_id sensitivity", "recorded_at did not change hash")
    if writer._compute_record_id("0" * 12, "a" * 40, "T", "G5", "PASS") == base:
        _fail("record_id sensitivity", "gate did not change hash")
    if writer._compute_record_id("0" * 12, "a" * 40, "T", "G4", "FAIL") == base:
        _fail("record_id sensitivity", "status did not change hash")
    _ok("record_id is sensitive to all 5 hashed inputs")


def test_genesis_sentinel(writer) -> None:
    if writer.GENESIS_PREV_ID != "0" * 12:
        _fail("genesis sentinel", f"got {writer.GENESIS_PREV_ID}")
    if writer._get_previous_record_id([]) != "0" * 12:
        _fail("empty records genesis", "did not return sentinel")
    _ok("genesis previous_record_id is 12 zeros")


def test_append_chain_and_validate(writer, validator) -> None:
    with tempfile.TemporaryDirectory() as tmp:
        tmp_path = Path(tmp) / "status.json"
        # Seed minimal ledger
        seed = {
            "schema_version": 1,
            "kind": "synthetic",
            "candidate_commit": "0" * 40,
            "records": [],
            "evidence_writer_version": writer.EVIDENCE_WRITER_VERSION,
            "gates": {name: {"status": "not_run", "checks": []}
                      for name in writer.GATES},
        }
        tmp_path.write_text(json.dumps(seed, indent=2))
        # Append two records via the writer's main()
        for gate, status in [("G4", "PASS"), ("G5", "PASS")]:
            rc = writer.main([
                "--status", str(tmp_path),
                "--append-record",
                "--candidate-commit", "0" * 40,
                "--record-kind", "synthetic",
                "--wave", "19a",
                "--track", "I",
                "--record-gate", gate,
                "--record-status", status,
                "--notes", f"smoke {gate}",
            ])
            if rc != 0:
                _fail(f"append {gate}", f"main returned {rc}")
        # Validate chain
        rc = subprocess.run(
            [sys.executable, str(VALIDATOR_PATH), str(tmp_path)],
        ).returncode
        if rc != 0:
            _fail("chain validation after append", f"exit {rc}")
        data = json.loads(tmp_path.read_text())
        records = data["records"]
        if len(records) != 2:
            _fail("record count", f"got {len(records)}")
        if records[1]["previous_record_id"] != records[0]["record_id"]:
            _fail("chain link", "record[1] does not link to record[0]")
        _ok("append 2 records + validator accepts the chain")


def test_tamper_detected(writer, validator) -> None:
    with tempfile.TemporaryDirectory() as tmp:
        tmp_path = Path(tmp) / "status.json"
        seed = {
            "schema_version": 1,
            "kind": "synthetic",
            "candidate_commit": "0" * 40,
            "records": [],
            "evidence_writer_version": writer.EVIDENCE_WRITER_VERSION,
            "gates": {name: {"status": "not_run", "checks": []}
                      for name in writer.GATES},
        }
        tmp_path.write_text(json.dumps(seed, indent=2))
        writer.main([
            "--status", str(tmp_path),
            "--append-record",
            "--candidate-commit", "0" * 40,
            "--record-kind", "synthetic",
            "--wave", "19a", "--track", "I",
            "--record-gate", "G4", "--record-status", "PASS",
            "--notes", "original",
        ])
        # Tamper with a hashed field
        data = json.loads(tmp_path.read_text())
        data["records"][0]["status"] = "FAIL"
        tmp_path.write_text(json.dumps(data, indent=2))
        rc = subprocess.run(
            [sys.executable, str(VALIDATOR_PATH), str(tmp_path)],
        ).returncode
        if rc == 0:
            _fail("tamper detection", "validator accepted tampered chain")
        _ok("validator rejects tampered hashed field")


def test_reorder_detected(writer, validator) -> None:
    with tempfile.TemporaryDirectory() as tmp:
        tmp_path = Path(tmp) / "status.json"
        seed = {
            "schema_version": 1,
            "kind": "synthetic",
            "candidate_commit": "0" * 40,
            "records": [],
            "evidence_writer_version": writer.EVIDENCE_WRITER_VERSION,
            "gates": {name: {"status": "not_run", "checks": []}
                      for name in writer.GATES},
        }
        tmp_path.write_text(json.dumps(seed, indent=2))
        for gate in ("G4", "G5"):
            writer.main([
                "--status", str(tmp_path),
                "--append-record",
                "--candidate-commit", "0" * 40,
                "--record-kind", "synthetic",
                "--wave", "19a", "--track", "I",
                "--record-gate", gate, "--record-status", "PASS",
                "--notes", f"smoke {gate}",
            ])
        # Reverse record order
        data = json.loads(tmp_path.read_text())
        data["records"].reverse()
        tmp_path.write_text(json.dumps(data, indent=2))
        rc = subprocess.run(
            [sys.executable, str(VALIDATOR_PATH), str(tmp_path)],
        ).returncode
        if rc == 0:
            _fail("reorder detection", "validator accepted reversed chain")
        _ok("validator rejects re-ordered records")


def test_backward_compat_gate_mutation(writer, validator) -> None:
    with tempfile.TemporaryDirectory() as tmp:
        tmp_path = Path(tmp) / "status.json"
        seed = {
            "schema_version": 1,
            "kind": "synthetic",
            "candidate_commit": "0" * 40,
            "records": [],
            "evidence_writer_version": writer.EVIDENCE_WRITER_VERSION,
            "gates": {name: {"status": "not_run", "checks": []}
                      for name in writer.GATES},
        }
        tmp_path.write_text(json.dumps(seed, indent=2))
        rc = writer.main([
            "--status", str(tmp_path),
            "--gate", "static",
            "--check", "contract_audit",
            "--check-status", "pass",
            "--evidence-ref", "https://example.com/runs/1",
            "--candidate-commit", "0" * 40,
            "--checked-by", "tester",
        ])
        if rc != 0:
            _fail("gate mutation", f"main returned {rc}")
        data = json.loads(tmp_path.read_text())
        check = data["gates"]["static"]["checks"][0]
        if check.get("status") != "pass":
            _fail("gate mutation result", f"check={check}")
        # Validator should still accept the file (records empty, gates populated)
        rc = subprocess.run(
            [sys.executable, str(VALIDATOR_PATH), str(tmp_path)],
        ).returncode
        if rc != 0:
            _fail("validator after gate mutation", f"exit {rc}")
        _ok("gate-based mutation works alongside records (backward compat)")


def test_artifact_sha256_computed(writer, validator) -> None:
    with tempfile.TemporaryDirectory() as tmp:
        tmp_path = Path(tmp) / "status.json"
        artifact_path = Path(tmp) / "artifact.txt"
        artifact_path.write_text("hello world\n")
        seed = {
            "schema_version": 1,
            "kind": "synthetic",
            "candidate_commit": "0" * 40,
            "records": [],
            "evidence_writer_version": writer.EVIDENCE_WRITER_VERSION,
            "gates": {name: {"status": "not_run", "checks": []}
                      for name in writer.GATES},
        }
        tmp_path.write_text(json.dumps(seed, indent=2))
        rc = writer.main([
            "--status", str(tmp_path),
            "--append-record",
            "--candidate-commit", "0" * 40,
            "--record-kind", "real",
            "--wave", "19a", "--track", "I",
            "--record-gate", "G4", "--record-status", "PASS",
            "--artifact", str(artifact_path),
            "--notes", "with artifact",
        ])
        if rc != 0:
            _fail("artifact append", f"main returned {rc}")
        data = json.loads(tmp_path.read_text())
        artifacts = data["records"][0]["artifacts"]
        if not artifacts or not artifacts[0]["sha256"]:
            _fail("artifact sha256", f"got {artifacts}")
        if len(artifacts[0]["sha256"]) != 64:
            _fail("artifact sha256 length", f"got {len(artifacts[0]['sha256'])}")
        rc = subprocess.run(
            [sys.executable, str(VALIDATOR_PATH), str(tmp_path)],
        ).returncode
        if rc != 0:
            _fail("artifact validation", f"exit {rc}")
        _ok("artifact sha256 is computed and chain accepts it")


def main() -> int:
    writer = _load_module("evidence_writer", WRITER_PATH)
    validator = _load_module("validate_evidence", VALIDATOR_PATH)
    test_record_id_deterministic(writer)
    test_record_id_changes_on_input(writer)
    test_genesis_sentinel(writer)
    test_append_chain_and_validate(writer, validator)
    test_tamper_detected(writer, validator)
    test_reorder_detected(writer, validator)
    test_backward_compat_gate_mutation(writer, validator)
    test_artifact_sha256_computed(writer, validator)
    print("\nAll tests passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
