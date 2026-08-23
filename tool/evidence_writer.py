#!/usr/bin/env python3
"""Incremental writer for MVP evidence ledger (evidence/mvp/status.json).

v1.1.0 — adds ADR-0010 Evidence Ledger Chain support.

The ledger now has two coexisting sections:

1. ``gates`` — the original gate/check status tree (consumed by
   ``tool/mvp_acceptance/audit.py``). Preserved for backward compatibility.
2. ``records`` — append-only SHA-256 chained entries per ADR-0010. Each
   record links to the previous one via ``previous_record_id`` and its
   ``record_id`` is derived from SHA-256(previous_record_id +
   candidate_commit + recorded_at + gate + status)[:12].

This tool is intentionally dependency-free (Python 3.10+ stdlib only).
It only mutates fields explicitly requested by the operator and preserves
unknown keys untouched, so future ledger schema growth is safe.

Chain semantics
---------------
- Genesis record uses ``previous_record_id = "0" * 12``.
- ``record_id`` is deterministic given its inputs, so any later tampering
  with a record's contents breaks the chain for every subsequent record.
- The chain is NOT a cryptographic blockchain — it is a tamper-evident
  timeline. GitHub commit SHAs already provide immutable anchoring.

Examples
--------
Mark static gate's contract_audit check as PASS:
    python3 tool/evidence_writer.py \\
        --gate static \\
        --check contract_audit \\
        --check-status pass \\
        --evidence-ref "https://github.com/.../actions/runs/123" \\
        --commit 27d0b9e000000000000000000000000000000000 \\
        --checked-by "trae-subagent"

Declare a gate as PASS (requires all sub-checks declared earlier):
    python3 tool/evidence_writer.py --gate static --declare-pass

Append a chain record (ADR-0010):
    python3 tool/evidence_writer.py \\
        --append-record \\
        --candidate-commit f70a202 \\
        --record-kind real \\
        --wave 19a --track I --gate G4 \\
        --record-status PASS \\
        --artifact path/to/file.dart \\
        --notes "RealSqlCipherPlatformOpener verified"

Validate the resulting ledger immediately (recommended):
    python3 tool/evidence_writer.py ... --audit
"""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import subprocess
import sys
from pathlib import Path
from typing import Any


GATES = ("static", "flutter_test", "apk", "redmi_device", "dogfood")
SHA40_LEN = 40
SHA256_LEN = 64
RECORD_ID_LEN = 12
GENESIS_PREV_ID = "0" * RECORD_ID_LEN
EVIDENCE_WRITER_VERSION = "1.1.0"
KIND_LEVELS = ("synthetic", "real", "device")
REQUIRED_CHECK_GROUPS = {
    "static": {"contract_audit", "dependency_audit"},
    "flutter_test": {
        "flutter_analyze",
        "dart_unit",
        "flutter_widget",
        "flutter_integration",
    },
    "apk": {"release_apk_build"},
    "redmi_device": {
        "install_launch",
        "offline_loop",
        "process_death",
        "device_reboot",
        "lock_unlock",
        "permission_denied",
        "battery_restriction",
        "export_delete",
        "recovery_drill",
    },
    "dogfood": {
        "steps": {
            "baseline",
            "goal",
            "opportunity",
            "plan_approved",
            "execution",
            "feedback",
            "revision",
            "review",
            "user_value_confirmation",
        },
        "safety_checks": {
            "d4_not_persisted",
            "d3_revocation",
            "r3_draft_only",
            "export_delete_explained",
            "restart_consistent",
        },
    },
}


def _utc_now_iso() -> str:
    return dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _is_sha40(value: str) -> bool:
    return len(value) == SHA40_LEN and all(ch in "0123456789abcdef" for ch in value)


def _is_sha256(value: str) -> bool:
    return len(value) == SHA256_LEN and all(
        ch in "0123456789abcdef" for ch in value
    )


def _is_record_id(value: str) -> bool:
    return len(value) == RECORD_ID_LEN and all(
        ch in "0123456789abcdef" for ch in value
    )


def _compute_record_id(
    previous_record_id: str,
    candidate_commit: str,
    recorded_at: str,
    gate: str,
    status: str,
) -> str:
    """Per ADR-0010 §2: SHA-256(prev + commit + ts + gate + status)[:12]."""
    data = f"{previous_record_id}{candidate_commit}{recorded_at}{gate}{status}"
    return hashlib.sha256(data.encode("utf-8")).hexdigest()[:RECORD_ID_LEN]


def _default_ledger() -> dict[str, Any]:
    return {
        "schema_version": 1,
        "kind": "synthetic",
        "candidate_commit": "0" * SHA40_LEN,
        "gates": {name: {"status": "not_run", "checks": []} for name in GATES},
        "records": [],
        "evidence_writer_version": EVIDENCE_WRITER_VERSION,
    }


def _load(ledger_path: Path) -> dict[str, Any]:
    if not ledger_path.exists():
        print(
            f"WARNING: {ledger_path} not found, seeding default skeleton.",
            file=sys.stderr,
        )
        return _default_ledger()
    try:
        data = json.loads(ledger_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        print(f"ERROR: invalid JSON in {ledger_path}: {exc}", file=sys.stderr)
        raise SystemExit(2)
    if not isinstance(data, dict):
        print("ERROR: ledger root must be a JSON object.", file=sys.stderr)
        raise SystemExit(2)
    # Ensure minimum skeleton exists
    data.setdefault("schema_version", 1)
    data.setdefault("kind", "synthetic")
    data.setdefault("candidate_commit", "0" * SHA40_LEN)
    gates = data.setdefault("gates", {})
    for name in GATES:
        gate = gates.setdefault(name, {})
        gate.setdefault("status", "not_run")
        if name == "dogfood":
            gate.setdefault("steps", [])
            gate.setdefault("safety_checks", [])
        elif name == "redmi_device":
            gate.setdefault("scenarios", [])
        else:
            gate.setdefault("checks", [])
    data.setdefault("records", [])
    data.setdefault("evidence_writer_version", EVIDENCE_WRITER_VERSION)
    return data


def _save(ledger_path: Path, data: dict[str, Any]) -> None:
    ledger_path.parent.mkdir(parents=True, exist_ok=True)
    tmp = ledger_path.with_suffix(".json.tmp")
    tmp.write_text(
        json.dumps(data, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    tmp.replace(ledger_path)


def _upsert_check(
    checks: list[dict[str, Any]],
    check_id: str,
    status: str,
    evidence_ref: str,
) -> None:
    for item in checks:
        if isinstance(item, dict) and item.get("id") == check_id:
            item["status"] = status
            item["evidence_ref"] = evidence_ref
            return
    checks.append({"id": check_id, "status": status, "evidence_ref": evidence_ref})


def _all_checks_passed(
    checks: list[dict[str, Any]], expected: set[str]
) -> bool:
    actual = {
        item.get("id")
        for item in checks
        if isinstance(item, dict)
        and item.get("status") == "pass"
        and isinstance(item.get("evidence_ref"), str)
        and item["evidence_ref"].strip()
    }
    return actual == expected and len(checks) == len(expected)


def _get_previous_record_id(records: list[dict[str, Any]]) -> str:
    """Return the record_id of the last record, or genesis '0'*12 if empty."""
    for record in reversed(records):
        rid = record.get("record_id") if isinstance(record, dict) else None
        if isinstance(rid, str) and _is_record_id(rid):
            return rid
    return GENESIS_PREV_ID


def _sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def _verify_commit_on_origin(commit: str) -> bool:
    """Best-effort check that the candidate commit exists on origin.

    Returns True if verification could not be performed (e.g., no git repo,
    no network, or the synthetic all-zeros sentinel) — caller proceeds.
    Returns False only if git explicitly reports the commit as absent.
    """
    # The all-zeros SHA is the synthetic-ledger sentinel (no real commit yet);
    # accept it so freshly-seeded ledgers can record synthetic evidence.
    if commit == "0" * SHA40_LEN:
        return True
    try:
        result = subprocess.run(
            ["git", "cat-file", "-t", commit],
            capture_output=True,
            text=True,
            timeout=5,
        )
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return True
    return result.returncode == 0 and result.stdout.strip() == "commit"


def _validate_chain(records: list[dict[str, Any]]) -> list[str]:
    """Return list of validation errors (empty = chain is healthy)."""
    errors: list[str] = []
    prev_id = GENESIS_PREV_ID
    for idx, record in enumerate(records):
        if not isinstance(record, dict):
            errors.append(f"records[{idx}] is not an object")
            continue
        rid = record.get("record_id")
        prev = record.get("previous_record_id")
        if not (isinstance(rid, str) and _is_record_id(rid)):
            errors.append(f"records[{idx}].record_id invalid: {rid!r}")
            continue
        if not (isinstance(prev, str) and _is_record_id(prev)):
            errors.append(f"records[{idx}].previous_record_id invalid: {prev!r}")
            continue
        if prev != prev_id:
            errors.append(
                f"records[{idx}].previous_record_id={prev} but expected {prev_id}"
            )
            prev_id = rid
            continue
        expected_rid = _compute_record_id(
            prev_id,
            str(record.get("candidate_commit", "")),
            str(record.get("recorded_at", "")),
            str(record.get("gate", "")),
            str(record.get("status", "")),
        )
        if expected_rid != rid:
            errors.append(
                f"records[{idx}].record_id={rid} but recomputed={expected_rid} "
                "(content does not match chain)"
            )
        prev_id = rid
    return errors


def _append_record(args: argparse.Namespace, data: dict[str, Any]) -> None:
    """Append a new ADR-0010 chain record to data['records']."""
    if args.record_kind not in KIND_LEVELS:
        print(
            f"ERROR: --record-kind must be one of {KIND_LEVELS}.",
            file=sys.stderr,
        )
        raise SystemExit(2)
    if args.record_status not in {"PASS", "FAIL", "BLOCKED"}:
        print(
            "ERROR: --record-status must be PASS/FAIL/BLOCKED.",
            file=sys.stderr,
        )
        raise SystemExit(2)
    if not args.candidate_commit:
        print(
            "ERROR: --append-record requires --candidate-commit.",
            file=sys.stderr,
        )
        raise SystemExit(2)
    if not _verify_commit_on_origin(args.candidate_commit):
        print(
            f"ERROR: candidate commit {args.candidate_commit} not found "
            "in local git object store. Run `git fetch origin` first.",
            file=sys.stderr,
        )
        raise SystemExit(1)

    artifacts: list[dict[str, Any]] = []
    if args.artifact:
        repo_root = Path(__file__).resolve().parent.parent
        for raw in args.artifact:
            p = Path(raw)
            full = p if p.is_absolute() else repo_root / p
            if not full.exists():
                print(
                    f"WARNING: artifact {raw} not found, skipping sha256.",
                    file=sys.stderr,
                )
                artifacts.append({"name": raw, "sha256": ""})
                continue
            artifacts.append({"name": raw, "sha256": _sha256_file(full)})

    records = data.setdefault("records", [])
    prev_id = _get_previous_record_id(records)
    recorded_at = args.recorded_at or _utc_now_iso()
    rid = _compute_record_id(
        prev_id,
        args.candidate_commit,
        recorded_at,
        args.record_gate,
        args.record_status,
    )
    record = {
        "record_id": rid,
        "previous_record_id": prev_id,
        "recorded_at": recorded_at,
        "candidate_commit": args.candidate_commit,
        "kind": args.record_kind,
        "wave": args.wave or "",
        "track": args.track or "",
        "gate": args.record_gate,
        "status": args.record_status,
        "artifacts": artifacts,
        "evidence_writer_version": EVIDENCE_WRITER_VERSION,
        "notes": args.notes or "",
    }
    records.append(record)
    print(
        f"Appended record_id={rid} (prev={prev_id}) to {len(records)}-entry chain.",
        file=sys.stderr,
    )


def _mutate(args: argparse.Namespace, data: dict[str, Any]) -> list[str]:
    warnings: list[str] = []

    # --- Top-level fields ---
    if args.kind is not None:
        if args.kind not in {"real", "synthetic"}:
            print("ERROR: --kind must be 'real' or 'synthetic'.", file=sys.stderr)
            raise SystemExit(2)
        data["kind"] = args.kind

    if args.candidate_commit is not None and not args.append_record:
        commit = args.candidate_commit.strip().lower()
        if not _is_sha40(commit):
            print(
                "ERROR: --candidate-commit must be lowercase 40-hex SHA.",
                file=sys.stderr,
            )
            raise SystemExit(2)
        data["candidate_commit"] = commit

    # --- ADR-0010 chain record append ---
    if args.append_record:
        # Normalize commit to lowercase 40-hex for chain hash determinism.
        commit = args.candidate_commit.strip().lower()
        if not _is_sha40(commit):
            print(
                "ERROR: --candidate-commit must be lowercase 40-hex SHA.",
                file=sys.stderr,
            )
            raise SystemExit(2)
        args.candidate_commit = commit
        _append_record(args, data)
        data["candidate_commit"] = commit

    # --- Gate-specific mutations ---
    gate_name = args.gate
    if gate_name is not None:
        if gate_name not in GATES:
            print(
                f"ERROR: --gate must be one of {', '.join(GATES)}.",
                file=sys.stderr,
            )
            raise SystemExit(2)
        gate: dict[str, Any] = data["gates"][gate_name]

        if args.declare_pass:
            expected = REQUIRED_CHECK_GROUPS[gate_name]
            if gate_name == "dogfood":
                steps_ok = _all_checks_passed(
                    gate.get("steps", []), expected["steps"]  # type: ignore[arg-type]
                )
                safety_ok = _all_checks_passed(
                    gate.get("safety_checks", []), expected["safety_checks"]  # type: ignore[arg-type]
                )
                if not (steps_ok and safety_ok):
                    print(
                        "ERROR: --declare-pass for dogfood requires all 9 steps "
                        "and 5 safety_checks declared with evidence.",
                        file=sys.stderr,
                    )
                    raise SystemExit(1)
            elif gate_name == "redmi_device":
                scenarios = gate.get("scenarios", [])
                if not _all_checks_passed(
                    scenarios, expected  # type: ignore[arg-type]
                ):
                    print(
                        "ERROR: --declare-pass for redmi_device requires all 9 "
                        "scenarios passed with evidence.",
                        file=sys.stderr,
                    )
                    raise SystemExit(1)
                if (
                    not isinstance(gate.get("android_major"), int)
                    or gate["android_major"] <= 0
                ):
                    print(
                        "ERROR: --declare-pass for redmi_device needs --android-major.",
                        file=sys.stderr,
                    )
                    raise SystemExit(1)
                if not _is_sha256(str(gate.get("apk_sha256", ""))):
                    print(
                        "ERROR: --declare-pass for redmi_device needs --gate-apk-sha256.",
                        file=sys.stderr,
                    )
                    raise SystemExit(1)
            else:
                checks = gate.get("checks", [])
                if not _all_checks_passed(checks, expected):  # type: ignore[arg-type]
                    print(
                        f"ERROR: --declare-pass for {gate_name} requires all "
                        f"checks {sorted(expected)} with pass+evidence.",
                        file=sys.stderr,
                    )
                    raise SystemExit(1)
                if gate_name == "apk":
                    artifact = gate.get("artifact")
                    if not (
                        isinstance(artifact, dict)
                        and _is_sha256(str(artifact.get("sha256", "")))
                        and isinstance(artifact.get("bytes"), int)
                        and artifact["bytes"] > 0
                    ):
                        print(
                            "ERROR: --declare-pass for apk requires valid "
                            "artifact.sha256 and artifact.bytes (--artifact-sha256 "
                            "and --artifact-bytes).",
                            file=sys.stderr,
                        )
                        raise SystemExit(1)
            # Fill gate metadata to satisfy audit.py
            commit = data["candidate_commit"]
            if not _is_sha40(commit):
                print(
                    "ERROR: --declare-pass requires --candidate-commit set first.",
                    file=sys.stderr,
                )
                raise SystemExit(1)
            gate["status"] = "pass"
            gate["commit"] = commit
            gate["checked_at"] = args.checked_at or _utc_now_iso()
            if not isinstance(gate.get("checked_by"), str) or not gate["checked_by"]:
                if not args.checked_by:
                    print(
                        "ERROR: --declare-pass requires --checked-by.",
                        file=sys.stderr,
                    )
                    raise SystemExit(1)
                gate["checked_by"] = args.checked_by

        # Meta fields: checked_at/checked_by (set even without --declare-pass so
        # reviewers can see when a gate was last touched).
        if args.checked_at is not None:
            # Light validation: must end with Z and parseable
            try:
                dt.datetime.fromisoformat(args.checked_at[:-1] + "+00:00")
                if not args.checked_at.endswith("Z"):
                    raise ValueError("missing Z suffix")
            except (ValueError, IndexError):
                print(
                    "ERROR: --checked-at must be RFC3339 UTC ending with Z.",
                    file=sys.stderr,
                )
                raise SystemExit(2)
            gate["checked_at"] = args.checked_at
        if args.checked_by is not None:
            if not args.checked_by.strip():
                print("ERROR: --checked-by must not be blank.", file=sys.stderr)
                raise SystemExit(2)
            gate["checked_by"] = args.checked_by.strip()

        # Per-check mutation (static/flutter_test/apk use checks;
        # redmi_device uses scenarios; dogfood uses steps + safety_checks)
        if args.check is not None and args.check_status is not None:
            if args.evidence_ref is None:
                print(
                    "ERROR: --check/--check-status requires --evidence-ref.",
                    file=sys.stderr,
                )
                raise SystemExit(2)
            if args.check_status not in {"pass", "fail", "blocked", "not_run"}:
                print(
                    "ERROR: --check-status must be pass/fail/blocked/not_run.",
                    file=sys.stderr,
                )
                raise SystemExit(2)
            if gate_name in {"static", "flutter_test", "apk"}:
                _upsert_check(
                    gate.setdefault("checks", []),
                    args.check,
                    args.check_status,
                    args.evidence_ref,
                )
            elif gate_name == "redmi_device":
                _upsert_check(
                    gate.setdefault("scenarios", []),
                    args.check,
                    args.check_status,
                    args.evidence_ref,
                )
            elif gate_name == "dogfood":
                if args.check_group not in {"steps", "safety_checks"}:
                    print(
                        "ERROR: dogfood checks need --check-group {steps,safety_checks}.",
                        file=sys.stderr,
                    )
                    raise SystemExit(2)
                _upsert_check(
                    gate.setdefault(args.check_group, []),
                    args.check,
                    args.check_status,
                    args.evidence_ref,
                )

        # APK artifact metadata
        if gate_name == "apk":
            if args.artifact_sha256 is not None or args.artifact_bytes is not None:
                artifact = gate.setdefault("artifact", {})
                if args.artifact_sha256 is not None:
                    sha = args.artifact_sha256.strip().lower()
                    if not _is_sha256(sha):
                        print(
                            "ERROR: --artifact-sha256 must be 64-hex lowercase SHA.",
                            file=sys.stderr,
                        )
                        raise SystemExit(2)
                    artifact["sha256"] = sha
                if args.artifact_bytes is not None:
                    if args.artifact_bytes <= 0:
                        print(
                            "ERROR: --artifact-bytes must be positive int.",
                            file=sys.stderr,
                        )
                        raise SystemExit(2)
                    artifact["bytes"] = args.artifact_bytes

        # Redmi device metadata
        if gate_name == "redmi_device":
            if args.android_major is not None:
                if args.android_major <= 0:
                    print(
                        "ERROR: --android-major must be positive int.",
                        file=sys.stderr,
                    )
                    raise SystemExit(2)
                gate["android_major"] = args.android_major
            if args.gate_apk_sha256 is not None:
                sha = args.gate_apk_sha256.strip().lower()
                if not _is_sha256(sha):
                    print(
                        "ERROR: --gate-apk-sha256 must be 64-hex SHA.",
                        file=sys.stderr,
                    )
                    raise SystemExit(2)
                gate["apk_sha256"] = sha

        # Dogfood cycle metadata
        if gate_name == "dogfood":
            if args.cycle_id is not None:
                if not args.cycle_id.strip():
                    print("ERROR: --cycle-id must not be blank.", file=sys.stderr)
                    raise SystemExit(2)
                gate["cycle_id"] = args.cycle_id.strip()
            if args.cycle_start is not None or args.cycle_end is not None:
                try:
                    start = (
                        dt.date.fromisoformat(args.cycle_start)
                        if args.cycle_start
                        else dt.date.fromisoformat(gate.get("cycle_start", ""))
                    )
                    end = (
                        dt.date.fromisoformat(args.cycle_end)
                        if args.cycle_end
                        else dt.date.fromisoformat(gate.get("cycle_end", ""))
                    )
                except (KeyError, TypeError, ValueError):
                    print(
                        "ERROR: --cycle-start/--cycle-end require YYYY-MM-DD dates.",
                        file=sys.stderr,
                    )
                    raise SystemExit(2)
                if args.cycle_start:
                    gate["cycle_start"] = args.cycle_start
                if args.cycle_end:
                    gate["cycle_end"] = args.cycle_end
                days = (end - start).days
                if not (14 <= days <= 42):
                    warnings.append(
                        f"dogfood cycle length is {days} days; audit "
                        "requires 14-42 for gate to pass."
                    )

    return warnings


def _run_audit(ledger_path: Path, target: str) -> int:
    repo_root = Path(__file__).resolve().parent.parent
    audit = repo_root / "tool" / "mvp_acceptance" / "audit.py"
    if not audit.exists():
        print(
            f"WARNING: audit script not found at {audit}; skipping --audit.",
            file=sys.stderr,
        )
        return 0
    return subprocess.call(
        [sys.executable, str(audit), "--status", str(ledger_path), "--target", target],
    )


def _parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        description="Incrementally write MVP evidence ledger (v1.1, ADR-0010 chain).",
    )
    default_path = (
        Path(__file__).resolve().parent.parent
        / "evidence"
        / "mvp"
        / "status.json"
    )
    p.add_argument("--status", type=Path, default=default_path)
    p.add_argument("--kind", choices=["real", "synthetic"])
    p.add_argument("--candidate-commit", help="40-hex lowercase git SHA")
    p.add_argument("--gate", choices=GATES)
    p.add_argument("--declare-pass", action="store_true",
                   help="Validate and mark gate status=pass with commit/time/author.")
    p.add_argument("--checked-at",
                   help="RFC3339 UTC timestamp ending with Z (default: now).")
    p.add_argument("--checked-by", help="Persona/agent identifier.")
    p.add_argument("--check", help="ID of the check/scenario/step to update.")
    p.add_argument("--check-status", choices=["pass", "fail", "blocked", "not_run"],
                   help="New status for the --check item.")
    p.add_argument("--evidence-ref",
                   help="CI URL / artifact digest / runbook ref for this check.")
    p.add_argument("--check-group", choices=["steps", "safety_checks"],
                   help="Required when gate=dogfood and --check is used.")
    p.add_argument("--artifact-sha256", help="For gate=apk only.")
    p.add_argument("--artifact-bytes", type=int, help="For gate=apk only.")
    p.add_argument("--android-major", type=int,
                   help="For gate=redmi_device only.")
    p.add_argument("--gate-apk-sha256", help="For gate=redmi_device only.")
    p.add_argument("--cycle-id", help="For gate=dogfood only.")
    p.add_argument("--cycle-start", help="For gate=dogfood only, YYYY-MM-DD.")
    p.add_argument("--cycle-end", help="For gate=dogfood only, YYYY-MM-DD.")
    p.add_argument("--audit", action="store_true",
                   help="After writing, run MVP acceptance audit script.")
    p.add_argument("--audit-target", choices=GATES, default="dogfood")

    # ADR-0010 chain record arguments
    p.add_argument("--append-record", action="store_true",
                   help="Append a new SHA-256-chained record per ADR-0010.")
    p.add_argument("--record-kind", choices=list(KIND_LEVELS),
                   help="Record kind: synthetic/real/device.")
    p.add_argument("--record-status", choices=["PASS", "FAIL", "BLOCKED"],
                   help="Record status for chain entry.")
    p.add_argument("--wave", help="Wave label, e.g. 19a.")
    p.add_argument("--track", help="Track label: A/B/C/D/E/F/G/I.")
    p.add_argument("--record-gate", default="G0",
                   help="Gate label for record, e.g. G0/G4/G5/G6.")
    p.add_argument("--recorded-at",
                   help="RFC3339 UTC timestamp for record (default: now).")
    p.add_argument("--artifact", action="append", default=[],
                   help="Path to artifact file (sha256 computed automatically). "
                        "Repeatable for multiple files.")
    p.add_argument("--notes", help="Free-form notes for the record.")
    p.add_argument("--validate-chain", action="store_true",
                   help="Only validate the existing records chain (no writes).")
    return p


def main(argv: list[str] | None = None) -> int:
    args = _parser().parse_args(argv)

    # --validate-chain is read-only and short-circuits everything else.
    if args.validate_chain:
        ledger_path = args.status.resolve()
        data = _load(ledger_path)
        records = data.get("records", [])
        errors = _validate_chain(records)
        if errors:
            print(f"CHAIN_INVALID records={len(records)} errors={len(errors)}",
                  file=sys.stderr)
            for e in errors:
                print(f"  - {e}", file=sys.stderr)
            return 1
        print(f"CHAIN_OK records={len(records)} "
              f"last_record_id={_get_previous_record_id(records)}",
              file=sys.stderr)
        return 0

    mutation_given = any([
        args.kind is not None,
        args.candidate_commit is not None,
        args.append_record,
        args.gate is not None and any([
            args.declare_pass,
            args.checked_at is not None,
            args.checked_by is not None,
            args.check is not None and args.check_status is not None,
            args.artifact_sha256 is not None,
            args.artifact_bytes is not None,
            args.android_major is not None,
            args.gate_apk_sha256 is not None,
            args.cycle_id is not None,
            args.cycle_start is not None,
            args.cycle_end is not None,
        ]),
    ])
    if not mutation_given and not args.audit:
        _parser().print_help()
        return 0

    ledger_path = args.status.resolve()
    data = _load(ledger_path)
    warnings = _mutate(args, data)
    _save(ledger_path, data)
    print(f"Wrote {ledger_path}")
    for w in warnings:
        print(f"WARNING: {w}", file=sys.stderr)

    if args.audit:
        return _run_audit(ledger_path, args.audit_target)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
