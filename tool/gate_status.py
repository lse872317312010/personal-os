#!/usr/bin/env python3
"""Dependency-free gate status aggregator (ADR-0010 v2 companion).

Reads evidence/mvp/status.json (the v1.1 ledger with both a legacy
``gates`` dict and the new ``records`` SHA-256 chain) and produces a
single human-readable summary. Also accepts a synthetic ledger path
(--ledger) for ad-hoc inspection.

The aggregator does NOT re-validate the chain — that's the job of
``evidence/android/tool/validate_evidence.py``. This tool assumes the
ledger has already passed validation and produces a *report*:

- Per-gate status from the legacy ``gates`` dict (not_run / blocked /
  pass / fail).
- Per-record chain summary (record_id prefix, gate, status, wave,
  track, commit prefix, timestamp, cumulative_hash yes/no).
- Cross-record consistency summary (unique record_ids count, unique
  (commit, gate, status) tuples count, monotonic timestamp check,
  cumulative_hash chain presence).
- Overall conclusion label mirroring tool/mvp_acceptance/audit.py:
  NOT_VERIFIED | STATIC_VERIFIED | TEST_VERIFIED | BUILD_VERIFIED |
  DEVICE_VERIFIED | DOGFOOD_READY.

Exit codes:
- 0: aggregation succeeded (regardless of pass/fail status)
- 1: file unreadable or not a JSON object
- 2: CLI misuse
"""

import argparse
import json
import sys
from pathlib import Path
from typing import Any

GATES = ("static", "flutter_test", "apk", "redmi_device", "dogfood")
LABELS = (
    "NOT_VERIFIED",
    "STATIC_VERIFIED",
    "TEST_VERIFIED",
    "BUILD_VERIFIED",
    "DEVICE_VERIFIED",
    "DOGFOOD_READY",
)


def _short(value: str, length: int = 7) -> str:
    """Return the first `length` chars of a string, suffixed with … if truncated."""
    if not isinstance(value, str):
        return str(value)
    return value if len(value) <= length else f"{value[:length]}\u2026"


def _gate_status(gate: Any) -> str:
    if not isinstance(gate, dict):
        return "?"
    return str(gate.get("status", "?"))


def _aggregate_gates(ledger: dict[str, Any]) -> list[tuple[str, str]]:
    """Return [(gate_name, status)] from the legacy `gates` dict."""
    gates = ledger.get("gates", {})
    if not isinstance(gates, dict):
        return [(name, "?") for name in GATES]
    return [(name, _gate_status(gates.get(name))) for name in GATES]


def _aggregate_records(ledger: dict[str, Any]) -> list[dict[str, Any]]:
    """Summarize each record in the `records` array."""
    records = ledger.get("records", [])
    if not isinstance(records, list):
        return []
    summary: list[dict[str, Any]] = []
    for idx, record in enumerate(records):
        if not isinstance(record, dict):
            summary.append({"index": idx, "error": "non-object record"})
            continue
        summary.append({
            "index": idx,
            "record_id": record.get("record_id", "?"),
            "previous_record_id": record.get("previous_record_id", "?"),
            "gate": record.get("gate", "?"),
            "status": record.get("status", "?"),
            "wave": record.get("wave", "?"),
            "track": record.get("track", "?"),
            "candidate_commit": record.get("candidate_commit", "?"),
            "recorded_at": record.get("recorded_at", "?"),
            "kind": record.get("kind", "?"),
            "has_cumulative_hash": "cumulative_hash" in record,
        })
    return summary


def _cross_record_summary(
    records: list[dict[str, Any]],
) -> dict[str, Any]:
    """Summarize cross-record invariants without re-validating."""
    if not records:
        return {
            "records": 0,
            "unique_record_ids": 0,
            "unique_replay_tuples": 0,
            "monotonic_timestamps": "n/a",
            "cumulative_hash_chain": "absent",
            "last_record_id": None,
        }
    record_ids = {r.get("record_id") for r in records}
    replay_tuples = {
        (r.get("candidate_commit"), r.get("gate"), r.get("status"))
        for r in records
    }
    timestamps = [r.get("recorded_at") for r in records]
    monotonic = "yes"
    for i in range(1, len(timestamps)):
        if timestamps[i] < timestamps[i - 1]:
            monotonic = "no"
            break
    has_ch_flags = [bool(r.get("has_cumulative_hash", False)) for r in records]
    if any(has_ch_flags) and not all(has_ch_flags):
        cumulative = "partial"
    elif any(has_ch_flags):
        cumulative = "yes"
    else:
        cumulative = "absent"
    return {
        "records": len(records),
        "unique_record_ids": len(record_ids),
        "unique_replay_tuples": len(replay_tuples),
        "monotonic_timestamps": monotonic,
        "cumulative_hash_chain": cumulative,
        "last_record_id": records[-1].get("record_id"),
    }


def _highest_passed_gate(records: list[dict[str, Any]]) -> int:
    """Return the index of the highest gate that has a PASS record.

    0 = no PASS records; 1 = static only; 2 = flutter_test; 3 = apk;
    4 = redmi_device; 5 = dogfood. Uses the cumulative gate order
    (GATES tuple). If a record's `gate` is not in GATES, it's
    ignored for this calculation.
    """
    passed: set[str] = set()
    for r in records:
        gate = r.get("gate")
        status = r.get("status")
        if status == "PASS" and isinstance(gate, str):
            passed.add(gate)
    level = 0
    for name in GATES:
        if name in passed:
            level += 1
        else:
            break
    return level


def _conclusion_label(level: int) -> str:
    if level < 0 or level >= len(LABELS):
        return LABELS[0]
    return LABELS[level]


def aggregate(ledger: dict[str, Any]) -> dict[str, Any]:
    gates_summary = _aggregate_gates(ledger)
    records_summary = _aggregate_records(ledger)
    cross_summary = _cross_record_summary(records_summary)
    level = _highest_passed_gate(records_summary)
    return {
        "gates": gates_summary,
        "records": records_summary,
        "cross_record": cross_summary,
        "level": level,
        "conclusion": _conclusion_label(level),
    }


def render_text(report: dict[str, Any], ledger_path: Path) -> str:
    lines: list[str] = []
    lines.append(f"=== Gate Status ({ledger_path}) ===")
    lines.append("")
    lines.append("Per-Gate Summary (from gates[]):")
    for name, status in report["gates"]:
        lines.append(f"  {name:<15} {status}")
    lines.append("")
    records = report["records"]
    if records:
        lines.append("Per-Record Chain (from records[]):")
        lines.append(
            f"  {'#':<3} {'gate':<5} {'status':<8} "
            f"{'wave':<6} {'track':<6} {'commit':<10} "
            f"{'ts':<22} {'cumul':<5}"
        )
        for r in records:
            if "error" in r:
                lines.append(f"  {r['index']:<3} ERROR: {r['error']}")
                continue
            lines.append(
                f"  {r['index']:<3} "
                f"{str(r['gate']):<5} "
                f"{str(r['status']):<8} "
                f"{str(r['wave']):<6} "
                f"{str(r['track']):<6} "
                f"{_short(r['candidate_commit']):<10} "
                f"{str(r['recorded_at']):<22} "
                f"{'yes' if r['has_cumulative_hash'] else 'no':<5}"
            )
        lines.append("")
    else:
        lines.append("Per-Record Chain: (no records — genesis only)")
        lines.append("")
    cross = report["cross_record"]
    lines.append("Cross-Record Summary:")
    lines.append(f"  records:                       {cross['records']}")
    lines.append(f"  unique record_ids:             {cross['unique_record_ids']}")
    lines.append(f"  unique (commit,gate,status):   {cross['unique_replay_tuples']}")
    lines.append(f"  monotonic timestamps:          {cross['monotonic_timestamps']}")
    lines.append(f"  cumulative_hash chain:          {cross['cumulative_hash_chain']}")
    last = cross["last_record_id"]
    lines.append(f"  last_record_id:                {last if last else '(none)'}")
    lines.append("")
    lines.append(f"Overall: {report['conclusion']}")
    return "\n".join(lines) + "\n"


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(
        description="Aggregate gate status from the ADR-0010 v1.1 ledger.",
    )
    default_ledger = (
        Path(__file__).resolve().parents[1]
        / "evidence" / "mvp" / "status.json"
    )
    parser.add_argument(
        "--ledger",
        type=Path,
        default=default_ledger,
        help="path to the ledger JSON (default: evidence/mvp/status.json)",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="emit the report as JSON instead of human-readable text",
    )
    args = parser.parse_args(argv)

    try:
        with open(args.ledger, encoding="utf-8") as source:
            ledger = json.load(source)
    except (OSError, json.JSONDecodeError) as error:
        print(f"ERROR: cannot read ledger: {error}", file=sys.stderr)
        return 1
    if not isinstance(ledger, dict):
        print("ERROR: ledger root must be a JSON object", file=sys.stderr)
        return 1

    report = aggregate(ledger)
    if args.json:
        print(json.dumps(report, indent=2, ensure_ascii=False))
    else:
        sys.stdout.write(render_text(report, args.ledger))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except KeyboardInterrupt:
        sys.exit(2)
