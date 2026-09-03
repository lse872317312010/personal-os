#!/usr/bin/env python3
"""Validate one privacy-bounded Redmi evidence record."""

from __future__ import annotations

import argparse
import datetime as dt
import json
import re
import sys
from pathlib import Path


SCENARIOS = {f"RDM-{number:03d}" for number in range(1, 10)}
SHA40 = re.compile(r"^[0-9a-f]{40}$")
SHA256 = re.compile(r"^[0-9a-f]{64}$")
RESULTS = {"PASS", "FAIL", "BLOCKED", "N/A"}


def required_text(mapping: dict, key: str, label: str) -> str:
    value = mapping.get(key)
    if not isinstance(value, str) or not value.strip() or "<" in value:
        raise ValueError(f"missing completed {label}")
    return value.strip()


def utc_timestamp(value: str, label: str) -> None:
    if not value.endswith("Z"):
        raise ValueError(f"{label} must be RFC3339 UTC")
    try:
        parsed = dt.datetime.fromisoformat(value[:-1] + "+00:00")
    except ValueError as error:
        raise ValueError(f"{label} must be RFC3339 UTC") from error
    if parsed.utcoffset() != dt.timedelta(0):
        raise ValueError(f"{label} must be RFC3339 UTC")


def validate(data: object, require_ready: bool = False) -> bool:
    if not isinstance(data, dict) or data.get("schema_version") != 1:
        raise ValueError("schema_version must be 1")
    commit = required_text(data, "commit_sha", "commit_sha")
    if not SHA40.fullmatch(commit):
        raise ValueError("commit_sha must be lowercase SHA-1")
    apk_sha = required_text(data, "apk_sha256", "apk_sha256")
    if not SHA256.fullmatch(apk_sha):
        raise ValueError("apk_sha256 must be lowercase SHA-256")

    device = data.get("device")
    toolchain = data.get("toolchain")
    if not isinstance(device, dict) or not isinstance(toolchain, dict):
        raise ValueError("device and toolchain must be objects")
    for key in ("model", "android_version", "build_number"):
        required_text(device, key, f"device.{key}")
    for key in ("adb_version", "flutter_version", "runner"):
        required_text(toolchain, key, f"toolchain.{key}")

    scenarios = data.get("scenarios")
    if not isinstance(scenarios, list) or len(scenarios) != len(SCENARIOS):
        raise ValueError("scenarios must contain exactly RDM-001 through RDM-009")
    seen: set[str] = set()
    ready = True
    for scenario in scenarios:
        if not isinstance(scenario, dict):
            raise ValueError("each scenario must be an object")
        scenario_id = required_text(scenario, "id", "scenario.id")
        if scenario_id not in SCENARIOS or scenario_id in seen:
            raise ValueError(f"invalid or duplicate scenario id: {scenario_id}")
        seen.add(scenario_id)
        result = required_text(scenario, "result", f"{scenario_id}.result").upper()
        if result not in RESULTS:
            raise ValueError(f"invalid result for {scenario_id}: {result}")
        if result == "N/A" and scenario_id != "RDM-005":
            raise ValueError(f"N/A is only allowed for RDM-005, not {scenario_id}")
        observed = required_text(
            scenario, "observed_at_utc", f"{scenario_id}.observed_at_utc"
        )
        utc_timestamp(observed, f"{scenario_id}.observed_at_utc")
        required_text(scenario, "notes", f"{scenario_id}.notes")
        artifacts = scenario.get("artifacts")
        if not isinstance(artifacts, list) or not all(
            isinstance(item, str) and item.strip() for item in artifacts
        ):
            raise ValueError(f"{scenario_id}.artifacts must be a string array")
        ready = ready and (result == "PASS" or (scenario_id == "RDM-005" and result == "N/A"))
    if seen != SCENARIOS:
        raise ValueError("scenarios must contain exactly RDM-001 through RDM-009")
    if require_ready and not ready:
        raise ValueError("evidence is structurally valid but device scenarios are not all ready")
    return ready


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("evidence", type=Path)
    parser.add_argument("--require-ready", action="store_true")
    args = parser.parse_args()
    try:
        data = json.loads(args.evidence.read_text(encoding="utf-8"))
        ready = validate(data, require_ready=args.require_ready)
    except (OSError, json.JSONDecodeError, ValueError) as error:
        print(f"INVALID_EVIDENCE: {error}", file=sys.stderr)
        return 2
    print("DEVICE_VERIFIED" if ready else "VALID_NOT_READY")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
