#!/usr/bin/env python3
"""Audit Recovery Protocol fixtures without third-party dependencies."""

from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable


PROTOCOL_STATES = (
    "intake",
    "envelope_validated",
    "package_authenticated",
    "account_verified",
    "device_bound",
    "security_state_syncing",
    "device_revocations_applied",
    "account_epoch_applied",
    "deletion_tombstones_applied",
    "security_state_applied",
    "vault_data_syncing",
    "consistency_verified",
    "unlocked",
)
STATE_RANK = {state: rank for rank, state in enumerate(PROTOCOL_STATES)}
MATERIAL_TRANSITIONS = {
    "not_configured": {"generated_unverified", "revoked"},
    "generated_unverified": {"recovery_ready", "revoked"},
    "recovery_ready": {"rotation_required", "revoked"},
    "rotation_required": {"recovery_ready", "revoked"},
    "revoked": set(),
}
CASE_ID = re.compile(r"^RC-[0-9]{3}$")
ERROR_TABLE_CELL = re.compile(r"^\|\s*`([A-Z][A-Z0-9_]+)`\s*\|")


@dataclass(frozen=True)
class AuditIssue:
    path: Path
    message: str

    def __str__(self) -> str:
        return f"{self.path}: {self.message}"


def extract_protocol_error_codes(protocol_text: str) -> set[str]:
    """Read stable codes directly from Markdown table rows."""
    return {
        match.group(1)
        for line in protocol_text.splitlines()
        if (match := ERROR_TABLE_CELL.match(line))
    }


def _load_json(path: Path, issues: list[AuditIssue]) -> dict[str, Any] | None:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        issues.append(AuditIssue(path, f"invalid JSON: {error}"))
        return None
    if not isinstance(value, dict):
        issues.append(AuditIssue(path, "root must be a JSON object"))
        return None
    return value


def _audit_states(
    path: Path, expect: dict[str, Any], issues: list[AuditIssue]
) -> None:
    states = expect.get("ordered_states")
    terminal = expect.get("terminal_state")
    if not isinstance(states, list) or not states:
        issues.append(AuditIssue(path, "expect.ordered_states must be non-empty"))
        return
    if not all(isinstance(state, str) for state in states):
        issues.append(AuditIssue(path, "ordered_states must contain strings"))
        return
    if terminal != states[-1]:
        issues.append(
            AuditIssue(path, "terminal_state must equal the last ordered state")
        )
    if states[0] == "not_configured":
        _audit_material_states(path, states, issues)
        return
    _audit_restore_states(path, states, issues)


def _audit_material_states(
    path: Path, states: list[str], issues: list[AuditIssue]
) -> None:
    for current, following in zip(states, states[1:]):
        allowed = MATERIAL_TRANSITIONS.get(current)
        if allowed is None:
            issues.append(AuditIssue(path, f"unknown material state {current!r}"))
        elif following not in allowed:
            issues.append(
                AuditIssue(path, f"invalid material transition {current!r} -> {following!r}")
            )
    if states[-1] not in MATERIAL_TRANSITIONS:
        issues.append(AuditIssue(path, f"unknown material state {states[-1]!r}"))


def _audit_restore_states(
    path: Path, states: list[str], issues: list[AuditIssue]
) -> None:
    seen: set[str] = set()
    previous_rank = -1
    for index, state in enumerate(states):
        if state in seen:
            issues.append(AuditIssue(path, f"ordered_states repeats {state!r}"))
        seen.add(state)
        if state == "failed":
            if index != len(states) - 1:
                issues.append(AuditIssue(path, "failed must be terminal"))
            continue
        rank = STATE_RANK.get(state)
        if rank is None:
            issues.append(AuditIssue(path, f"unknown protocol state {state!r}"))
            continue
        if rank <= previous_rank:
            issues.append(AuditIssue(path, f"state transition regresses at {state!r}"))
        previous_rank = rank


def audit_recovery_contract(
    protocol_path: Path, fixtures_dir: Path
) -> list[AuditIssue]:
    issues: list[AuditIssue] = []
    try:
        protocol_text = protocol_path.read_text(encoding="utf-8")
    except OSError as error:
        return [AuditIssue(protocol_path, f"cannot read protocol: {error}")]
    protocol_codes = extract_protocol_error_codes(protocol_text)
    if not protocol_codes:
        issues.append(AuditIssue(protocol_path, "no stable error codes found"))

    schema_paths = sorted(fixtures_dir.glob("*.schema.json"))
    schema_ids: dict[str, Path] = {}
    schema_names: set[str] = set()
    for path in schema_paths:
        schema = _load_json(path, issues)
        if schema is None:
            continue
        schema_id = schema.get("$id")
        if not isinstance(schema_id, str) or not schema_id:
            issues.append(AuditIssue(path, "schema must have a non-empty $id"))
        elif schema_id in schema_ids:
            issues.append(
                AuditIssue(path, f"duplicate schema $id also used by {schema_ids[schema_id]}")
            )
        else:
            schema_ids[schema_id] = path
        schema_names.add(path.name)

    case_ids: dict[str, Path] = {}
    fixture_paths = sorted(
        path
        for path in fixtures_dir.glob("*.json")
        if not path.name.endswith(".schema.json")
    )
    if not fixture_paths:
        issues.append(AuditIssue(fixtures_dir, "no recovery fixtures found"))
    for path in fixture_paths:
        fixture = _load_json(path, issues)
        if fixture is None:
            continue
        case_id = fixture.get("case_id")
        if not isinstance(case_id, str) or not CASE_ID.fullmatch(case_id):
            issues.append(AuditIssue(path, "case_id must match RC-NNN"))
        elif case_id in case_ids:
            issues.append(
                AuditIssue(path, f"duplicate case_id also used by {case_ids[case_id]}")
            )
        else:
            case_ids[case_id] = path

        schema_ref = fixture.get("$schema")
        if not isinstance(schema_ref, str) or schema_ref not in schema_names:
            issues.append(AuditIssue(path, "$schema must name a local unique schema"))

        expect = fixture.get("expect")
        if not isinstance(expect, dict):
            issues.append(AuditIssue(path, "expect must be an object"))
            continue
        error_code = expect.get("error_code")
        if error_code is not None and error_code not in protocol_codes:
            issues.append(
                AuditIssue(path, f"error_code {error_code!r} is absent from protocol")
            )
        _audit_states(path, expect, issues)
    return issues


def default_repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def main(argv: Iterable[str] | None = None) -> int:
    root = default_repo_root()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--protocol",
        type=Path,
        default=root / "architecture" / "RECOVERY_PROTOCOL.md",
    )
    parser.add_argument(
        "--fixtures",
        type=Path,
        default=root / "fixtures" / "recovery",
    )
    args = parser.parse_args(argv)
    issues = audit_recovery_contract(args.protocol, args.fixtures)
    for issue in issues:
        print(issue, file=sys.stderr)
    if issues:
        print(f"recovery contract audit failed: {len(issues)} issue(s)", file=sys.stderr)
        return 1
    print("recovery contract audit passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
