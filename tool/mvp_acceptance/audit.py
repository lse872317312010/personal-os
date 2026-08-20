#!/usr/bin/env python3
"""Dependency-free audit of the Personal OS MVP usability evidence ledger."""

from __future__ import annotations

import argparse
import datetime as dt
import json
import re
import sys
from pathlib import Path

GATES = ("static", "flutter_test", "apk", "redmi_device", "dogfood")
LABELS = ("STATIC_VERIFIED", "TEST_VERIFIED", "BUILD_VERIFIED", "DEVICE_VERIFIED", "DOGFOOD_READY")
FLUTTER_CHECKS = {"flutter_analyze", "dart_unit", "flutter_widget", "flutter_integration"}
REDMI_SCENARIOS = {"install_launch", "offline_loop", "process_death", "device_reboot", "lock_unlock", "permission_denied", "battery_restriction", "export_delete", "recovery_drill"}
DOGFOOD_STEPS = {"baseline", "goal", "opportunity", "plan_approved", "execution", "feedback", "revision", "review", "user_value_confirmation"}
DOGFOOD_SAFETY = {"d4_not_persisted", "d3_revocation", "r3_draft_only", "export_delete_explained", "restart_consistent"}
FORBIDDEN_KEYS = {"device_serial", "android_id", "account_id", "user_content", "photo_path", "raw_log", "secret", "key_material", "system_fingerprint"}
SHA40 = re.compile(r"^[0-9a-f]{40}$")
SHA256 = re.compile(r"^[0-9a-f]{64}$")


def _utc(value: object) -> bool:
    if not isinstance(value, str) or not value.endswith("Z"):
        return False
    try:
        dt.datetime.fromisoformat(value[:-1] + "+00:00")
        return True
    except ValueError:
        return False


def _walk_forbidden(value: object, path: str = "$") -> list[str]:
    errors: list[str] = []
    if isinstance(value, dict):
        for key, child in value.items():
            if key.lower() in FORBIDDEN_KEYS:
                errors.append(f"{path}.{key}: forbidden sensitive field")
            errors.extend(_walk_forbidden(child, f"{path}.{key}"))
    elif isinstance(value, list):
        for index, child in enumerate(value):
            errors.extend(_walk_forbidden(child, f"{path}[{index}]"))
    return errors


def _check_set(gate: dict, expected: set[str], field: str = "checks") -> bool:
    items = gate.get(field)
    if not isinstance(items, list):
        return False
    passed = {
        item.get("id")
        for item in items
        if isinstance(item, dict)
        and item.get("status") == "pass"
        and isinstance(item.get("evidence_ref"), str)
        and item["evidence_ref"].strip()
    }
    return passed == expected and len(items) == len(expected)


def audit(data: object) -> tuple[list[bool], list[str]]:
    errors: list[str] = []
    if not isinstance(data, dict):
        return [False] * len(GATES), ["$: expected object"]
    errors.extend(_walk_forbidden(data))
    if data.get("schema_version") != 1:
        errors.append("$.schema_version: expected 1")
    kind = data.get("kind")
    if kind not in {"real", "synthetic"}:
        errors.append("$.kind: expected real or synthetic")
    commit = data.get("candidate_commit")
    if not isinstance(commit, str) or not SHA40.fullmatch(commit):
        errors.append("$.candidate_commit: expected lowercase 40-character git SHA")
    gates = data.get("gates")
    if not isinstance(gates, dict) or set(gates) != set(GATES):
        errors.append("$.gates: expected exactly five named gates")
        return [False] * len(GATES), errors

    passed: list[bool] = []
    for name in GATES:
        gate = gates[name]
        if not isinstance(gate, dict):
            errors.append(f"$.gates.{name}: expected object")
            passed.append(False)
            continue
        declared = gate.get("status") == "pass"
        valid = declared and kind == "real"
        if declared:
            if gate.get("commit") != commit:
                errors.append(f"$.gates.{name}.commit: must equal candidate_commit")
                valid = False
            if not _utc(gate.get("checked_at")):
                errors.append(f"$.gates.{name}.checked_at: expected RFC3339 UTC timestamp")
                valid = False
            if not isinstance(gate.get("checked_by"), str) or not gate["checked_by"].strip():
                errors.append(f"$.gates.{name}.checked_by: required")
                valid = False
        if name == "static" and declared:
            valid &= _check_set(gate, {"contract_audit", "dependency_audit"})
        elif name == "flutter_test" and declared:
            valid &= _check_set(gate, FLUTTER_CHECKS)
        elif name == "apk" and declared:
            artifact = gate.get("artifact")
            ok = isinstance(artifact, dict) and SHA256.fullmatch(str(artifact.get("sha256", ""))) is not None and isinstance(artifact.get("bytes"), int) and artifact["bytes"] > 0
            valid &= ok and _check_set(gate, {"release_apk_build"})
        elif name == "redmi_device" and declared:
            valid &= _check_set(gate, REDMI_SCENARIOS, "scenarios")
            valid &= isinstance(gate.get("android_major"), int) and gate["android_major"] > 0
            valid &= SHA256.fullmatch(str(gate.get("apk_sha256", ""))) is not None
        elif name == "dogfood" and declared:
            valid &= _check_set(gate, DOGFOOD_STEPS, "steps") and _check_set(gate, DOGFOOD_SAFETY, "safety_checks")
            try:
                start = dt.date.fromisoformat(gate["cycle_start"])
                end = dt.date.fromisoformat(gate["cycle_end"])
                valid &= 14 <= (end - start).days <= 42 and gate.get("cycle_id", "").strip() != ""
            except (KeyError, TypeError, ValueError):
                valid = False
        if declared and not valid:
            errors.append(f"$.gates.{name}: declared pass but required evidence is incomplete or synthetic")
        passed.append(bool(valid))

    # Gates are cumulative; an isolated later pass is never effective.
    cumulative = True
    for index, value in enumerate(passed):
        cumulative = cumulative and value
        passed[index] = cumulative
    return passed, errors


def conclusion(passed: list[bool]) -> str:
    level = sum(1 for value in passed if value)
    return "NOT_VERIFIED" if level == 0 else LABELS[level - 1]


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    default = Path(__file__).resolve().parents[2] / "evidence" / "mvp" / "status.json"
    parser.add_argument("--status", type=Path, default=default)
    parser.add_argument("--target", choices=GATES, default="dogfood")
    args = parser.parse_args(argv)
    try:
        data = json.loads(args.status.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        print(f"INVALID_EVIDENCE: {exc}", file=sys.stderr)
        return 2
    passed, errors = audit(data)
    result = conclusion(passed)
    print(result)
    for name, ok in zip(GATES, passed):
        print(f"{name}: {'PASS' if ok else 'NOT PASS'}")
    for error in errors:
        print(f"ERROR: {error}", file=sys.stderr)
    target_index = GATES.index(args.target)
    return 0 if passed[target_index] else 1


if __name__ == "__main__":
    raise SystemExit(main())
