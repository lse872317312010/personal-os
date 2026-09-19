#!/usr/bin/env python3
"""Validate one privacy-bounded Redmi MVP evidence record."""

from __future__ import annotations

import datetime
import json
import re
import sys

RESULTS = {"pass", "fail", "blocked"}
SCENARIOS = {
    "install_launch",
    "offline_loop",
    "process_death",
    "device_reboot",
    "lock_unlock",
    "permission_denied",
    "battery_restriction",
    "export_delete",
    "recovery_drill",
}
FAILURES = {
    "none",
    "not_run",
    "build_unavailable",
    "install_failed",
    "launch_failed",
    "network_dependency",
    "state_not_restored",
    "lock_bypass",
    "permission_behavior_invalid",
    "battery_behavior_invalid",
    "export_failed",
    "delete_failed",
    "backup_failed",
    "backup_authentication_failed",
    "backup_tamper_accepted",
    "recovery_failed",
    "unexpected_result",
}
SHA40 = re.compile(r"^[0-9a-f]{40}$")
SHA256 = re.compile(r"^[0-9a-f]{64}$")


def require(condition: bool, label: str) -> None:
    if not condition:
        raise ValueError(label)


def _utc(value: object, label: str) -> datetime.datetime:
    require(isinstance(value, str) and value.endswith("Z"), label)
    try:
        parsed = datetime.datetime.fromisoformat(value[:-1] + "+00:00")
    except ValueError as error:
        raise ValueError(label) from error
    require(parsed.utcoffset() == datetime.timedelta(0), label)
    return parsed


def validate(value: object) -> bool:
    required = {
        "schemaVersion",
        "recordKind",
        "targetClass",
        "buildProfile",
        "candidateCommit",
        "apkSha256",
        "startedAtUtc",
        "completedAtUtc",
        "overall",
        "scenarios",
    }
    require(type(value) is dict and set(value) == required, "root fields")
    require(value["schemaVersion"] == 2, "schemaVersion")
    require(value["recordKind"] in {"real_device", "synthetic"}, "recordKind")
    require(value["targetClass"] == "redmi_turbo", "targetClass")
    require(value["buildProfile"] in {"debug", "profile", "release"}, "buildProfile")
    require(
        isinstance(value["candidateCommit"], str)
        and SHA40.fullmatch(value["candidateCommit"]),
        "candidateCommit",
    )
    require(
        isinstance(value["apkSha256"], str)
        and SHA256.fullmatch(value["apkSha256"]),
        "apkSha256",
    )
    require(value["overall"] in RESULTS, "overall")
    started = _utc(value["startedAtUtc"], "startedAtUtc")
    completed = _utc(value["completedAtUtc"], "completedAtUtc")
    require(completed >= started, "completedAtUtc before startedAtUtc")

    scenarios = value["scenarios"]
    require(type(scenarios) is list and len(scenarios) == len(SCENARIOS), "scenarios length")
    require(
        all(type(item) is dict for item in scenarios)
        and {item.get("id") for item in scenarios} == SCENARIOS,
        "scenario IDs",
    )
    for item in scenarios:
        require(
            set(item)
            == {"id", "result", "checksPassed", "checksTotal", "failureCode"},
            "scenario fields",
        )
        require(item["result"] in RESULTS, "scenario result")
        require(item["failureCode"] in FAILURES, "scenario failureCode")
        require(
            type(item["checksPassed"]) is int
            and type(item["checksTotal"]) is int,
            "check count type",
        )
        require(
            0 <= item["checksPassed"] <= item["checksTotal"]
            and item["checksTotal"] >= 1,
            "check counts",
        )
        if item["result"] == "pass":
            require(value["recordKind"] == "real_device", "synthetic pass")
            require(
                item["checksPassed"] == item["checksTotal"]
                and item["failureCode"] == "none",
                "pass scenario evidence",
            )
        else:
            require(item["failureCode"] != "none", "non-pass scenario failureCode")

    passed = all(item["result"] == "pass" for item in scenarios)
    failed = any(item["result"] == "fail" for item in scenarios)
    if value["overall"] == "pass":
        require(value["recordKind"] == "real_device" and passed, "overall pass")
    elif value["overall"] == "fail":
        require(failed, "overall fail requires a failed scenario")
    else:
        require(not failed and not passed, "overall blocked requires blocked scenarios")
    return value["overall"] == "pass"


def main(path: str) -> None:
    with open(path, encoding="utf-8") as source:
        validate(json.load(source))


if __name__ == "__main__":
    try:
        main(sys.argv[1])
    except (IndexError, OSError, ValueError, TypeError, json.JSONDecodeError) as error:
        print(f"EVIDENCE_SCHEMA=fail CODE={type(error).__name__}", file=sys.stderr)
        raise SystemExit(1)
