#!/usr/bin/env python3
"""Fail-closed evidence ledger validation and truthful gate aggregation.

This module is intentionally dependency-free.  It is the small, canonical
implementation for the evidence ledger used by CI; Android evidence keeps
its existing schema validator and is not silently treated as a ledger.

Integrity rules:

* ``record_hash`` covers every record field except the derived hash and id.
* ``record_id`` binds the record hash to the previous record id.
* every record is bound to its candidate commit; callers must select the
  candidate explicitly before a PASS can become a verification label.
* error payloads are allow-listed and recursively checked for debug leaks.
"""

from __future__ import annotations

import datetime as dt
import hashlib
import json
import re
from pathlib import Path
from typing import Any

HEX40 = re.compile(r"^[0-9a-f]{40}$")
HEX64 = re.compile(r"^[0-9a-f]{64}$")
HEX12 = re.compile(r"^[0-9a-f]{12}$")
CODE = re.compile(r"^persistence\.[a-z0-9_]+$")

GENESIS = "0" * 12
STATUSES = {"PASS", "FAIL", "BLOCKED"}
KINDS = {"synthetic", "real", "device"}
GATES = ("static", "flutter_test", "apk", "redmi_device", "dogfood")
LABELS = (
    "STATIC_VERIFIED",
    "TEST_VERIFIED",
    "BUILD_VERIFIED",
    "DEVICE_VERIFIED",
    "DOGFOOD_READY",
)
FORBIDDEN_ERROR_KEYS = {
    "cause",
    "stack_trace",
    "stacktrace",
    "inner_exception",
    "innerexception",
    "raw_exception",
    "rawexception",
}
RECORD_FIELDS = {
    "previous_record_id",
    "recorded_at",
    "candidate_commit",
    "kind",
    "wave",
    "track",
    "gate",
    "status",
    "artifacts",
    "notes",
    "evidence_writer_version",
    "error",
}


class LedgerError(ValueError):
    """A malformed or untrusted ledger."""


def canonical_json(value: Any) -> str:
    """Return the one JSON representation used for integrity hashing."""
    try:
        return json.dumps(
            value,
            ensure_ascii=False,
            sort_keys=True,
            separators=(",", ":"),
            allow_nan=False,
        )
    except (TypeError, ValueError) as exc:
        raise LedgerError(f"non-canonical JSON value: {exc}") from exc


def _require(condition: bool, message: str) -> None:
    if not condition:
        raise LedgerError(message)


def _utc(value: Any, label: str) -> None:
    _require(isinstance(value, str) and value.endswith("Z"),
             f"{label} must be RFC3339 UTC")
    try:
        dt.datetime.fromisoformat(value[:-1] + "+00:00")
    except ValueError as exc:
        raise LedgerError(f"{label} must be RFC3339 UTC") from exc


def _walk_forbidden(value: Any, path: str = "$") -> list[str]:
    issues: list[str] = []
    if isinstance(value, dict):
        for key, child in value.items():
            if str(key).lower() in FORBIDDEN_ERROR_KEYS:
                issues.append(f"{path}.{key}: forbidden error-debugging field")
            issues.extend(_walk_forbidden(child, f"{path}.{key}"))
    elif isinstance(value, list):
        for index, child in enumerate(value):
            issues.extend(_walk_forbidden(child, f"{path}[{index}]"))
    return issues


def validate_safe_error(value: Any, label: str = "error") -> None:
    """Validate the only error shape allowed to enter evidence.

    ``safe_message`` is deliberately not caller-overridable in the Dart
    API; this Python boundary additionally rejects unsafe debugging keys at
    every nesting level.  A null safe message is permitted for unavailable
    detail, but a raw exception message is never accepted.
    """
    _require(type(value) is dict, f"{label} must be an object")
    _require(set(value) == {"code", "safe_message"},
             f"{label} must contain exactly code and safe_message")
    _require(isinstance(value["code"], str) and CODE.fullmatch(value["code"]),
             f"{label}.code must be a stable persistence code")
    _require(value["safe_message"] is None
             or isinstance(value["safe_message"], str),
             f"{label}.safe_message must be string or null")
    forbidden = _walk_forbidden(value, label)
    _require(not forbidden, "; ".join(forbidden))


def _record_body(record: dict[str, Any]) -> dict[str, Any]:
    return {key: record[key] for key in sorted(RECORD_FIELDS)}


def compute_record_hash(record: dict[str, Any]) -> str:
    """Hash all immutable record fields, including artifacts and error."""
    return hashlib.sha256(canonical_json(_record_body(record)).encode()).hexdigest()


def compute_record_id(previous_record_id: str, record_hash: str) -> str:
    _require(HEX12.fullmatch(previous_record_id) is not None,
             "previous_record_id must be 12 lowercase hex characters")
    _require(HEX64.fullmatch(record_hash) is not None,
             "record_hash must be 64 lowercase hex characters")
    return hashlib.sha256(
        f"{previous_record_id}{record_hash}".encode()
    ).hexdigest()[:12]


def validate_record(record: Any, index: int, previous_id: str) -> str:
    label = f"records[{index}]"
    _require(type(record) is dict, f"{label} must be an object")
    required = RECORD_FIELDS | {"record_hash", "record_id"}
    _require(set(record) == required, f"{label} fields are not exact")
    _require(record["previous_record_id"] == previous_id,
             f"{label}.previous_record_id does not continue the chain")
    _require(HEX12.fullmatch(record["previous_record_id"]) is not None,
             f"{label}.previous_record_id is invalid")
    _require(HEX40.fullmatch(record["candidate_commit"]) is not None,
             f"{label}.candidate_commit is invalid")
    _require(record["kind"] in KINDS, f"{label}.kind is invalid")
    _require(record["gate"] in GATES, f"{label}.gate is invalid")
    _require(record["status"] in STATUSES, f"{label}.status is invalid")
    _utc(record["recorded_at"], f"{label}.recorded_at")
    for field in ("wave", "track", "notes", "evidence_writer_version"):
        _require(isinstance(record[field], str), f"{label}.{field} must be string")
    artifacts = record["artifacts"]
    _require(type(artifacts) is list, f"{label}.artifacts must be a list")
    for artifact_index, artifact in enumerate(artifacts):
        artifact_label = f"{label}.artifacts[{artifact_index}]"
        _require(type(artifact) is dict and set(artifact) == {"name", "sha256"},
                 f"{artifact_label} must contain name and sha256 only")
        _require(isinstance(artifact["name"], str) and artifact["name"].strip(),
                 f"{artifact_label}.name must be non-empty")
        _require(isinstance(artifact["sha256"], str)
                 and HEX64.fullmatch(artifact["sha256"]) is not None,
                 f"{artifact_label}.sha256 must be lowercase SHA-256")
    if record["error"] is not None:
        validate_safe_error(record["error"], f"{label}.error")
    expected_hash = compute_record_hash(record)
    _require(record["record_hash"] == expected_hash,
             f"{label}.record_hash does not cover the complete record")
    expected_id = compute_record_id(previous_id, expected_hash)
    _require(record["record_id"] == expected_id,
             f"{label}.record_id does not bind previous id and record hash")
    return record["record_id"]


def validate_ledger(value: Any) -> dict[str, Any]:
    _require(type(value) is dict, "ledger root must be object")
    _require(value.get("schema_version") in {1, 2},
             "schema_version must be 1 or 2")
    _require(value.get("kind") in KINDS, "ledger kind is invalid")
    candidate = value.get("candidate_commit")
    _require(isinstance(candidate, str) and HEX40.fullmatch(candidate) is not None,
             "ledger candidate_commit is invalid")
    records = value.get("records")
    _require(type(records) is list, "ledger records must be a list")
    previous_id = GENESIS
    last_timestamp: str | None = None
    for index, record in enumerate(records):
        previous_id = validate_record(record, index, previous_id)
        timestamp = record["recorded_at"]
        if last_timestamp is not None:
            _require(timestamp >= last_timestamp,
                     f"records[{index}].recorded_at moves backwards")
        last_timestamp = timestamp
    return value


def load_ledger(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise LedgerError(f"cannot read ledger: {exc}") from exc
    return validate_ledger(value)


def aggregate(value: dict[str, Any], candidate_commit: str | None) -> dict[str, Any]:
    """Aggregate only explicitly selected, real candidate-bound records."""
    if candidate_commit is not None:
        _require(HEX40.fullmatch(candidate_commit) is not None,
                 "candidate_commit selector is invalid")
    records = value["records"]
    selected = [
        record for record in records
        if candidate_commit is not None
        and record["candidate_commit"] == candidate_commit
    ]
    passed: list[bool] = []
    for gate in GATES:
        passed.append(any(
            record["gate"] == gate
            and record["status"] == "PASS"
            and record["kind"] in {"real", "device"}
            for record in selected
        ))
    cumulative: list[bool] = []
    prior = True
    for current in passed:
        prior = prior and current
        cumulative.append(prior)
    level = sum(cumulative)
    return {
        "candidate_commit": candidate_commit,
        "records_considered": len(selected),
        "passed": dict(zip(GATES, cumulative)),
        "overall": "NOT_VERIFIED" if level == 0 else LABELS[level - 1],
        "legacy_gates_ignored": True,
    }


def main(argv: list[str] | None = None) -> int:
    import argparse

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ledger", type=Path, default=Path("evidence/mvp/status.json"))
    parser.add_argument("--candidate-commit")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args(argv)
    try:
        result = aggregate(load_ledger(args.ledger), args.candidate_commit)
    except LedgerError as exc:
        print(f"EVIDENCE_LEDGER=fail {exc}")
        return 1
    if args.json:
        print(json.dumps(result, sort_keys=True))
    else:
        print(result["overall"])
        print(f"candidate_commit: {result['candidate_commit'] or '(not selected)'}")
        print(f"records_considered: {result['records_considered']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
