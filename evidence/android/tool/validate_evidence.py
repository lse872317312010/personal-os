#!/usr/bin/env python3
"""Dependency-free validator mirroring the non-sensitive evidence schema."""

import datetime
import json
import re
import sys

RESULTS = {"pass", "fail", "blocked"}
SCENARIOS = {
    "install_launch", "offline_operation", "screen_lock", "device_reboot",
    "capability_report", "vault_wrong_key", "trusted_device_recovery",
    "offline_package_recovery", "device_revocation",
}
FAILURES = {
    "none", "not_run", "build_unavailable", "install_failed", "launch_failed",
    "network_dependency", "lock_bypass", "state_not_restored",
    "capability_mismatch", "wrong_key_accepted", "recovery_failed",
    "revoked_device_authorized", "unexpected_result",
}
SHA40 = re.compile(r"^[0-9a-f]{40}$")


def require(condition: bool, label: str) -> None:
    if not condition:
        raise ValueError(label)


def main(path: str) -> None:
    with open(path, encoding="utf-8") as source:
        value = json.load(source)
    required = {"schemaVersion", "recordKind", "targetClass", "buildProfile",
                "candidateCommit",
                "startedAtUtc", "completedAtUtc", "overall", "scenarios"}
    allowed = required | {"capabilities"}
    require(type(value) is dict and set(value) <= allowed and required <= set(value), "root fields")
    require(value["schemaVersion"] == 1, "schemaVersion")
    require(value["recordKind"] in {"real_device", "synthetic"}, "recordKind")
    require(value["targetClass"] == "redmi_turbo", "targetClass")
    require(value["buildProfile"] in {"debug", "profile", "release"}, "buildProfile")
    require(isinstance(value["candidateCommit"], str) and SHA40.fullmatch(value["candidateCommit"]), "candidateCommit")
    require(value["overall"] in RESULTS, "overall")
    for field in ("startedAtUtc", "completedAtUtc"):
        datetime.datetime.fromisoformat(value[field].replace("Z", "+00:00"))
    require(value["startedAtUtc"].endswith("Z") and value["completedAtUtc"].endswith("Z"), "UTC timestamps")
    started = datetime.datetime.fromisoformat(value["startedAtUtc"].replace("Z", "+00:00"))
    completed = datetime.datetime.fromisoformat(value["completedAtUtc"].replace("Z", "+00:00"))
    require(completed >= started, "completedAtUtc before startedAtUtc")
    scenarios = value["scenarios"]
    require(type(scenarios) is list and len(scenarios) == 9, "scenarios length")
    require({item.get("id") for item in scenarios} == SCENARIOS, "scenario IDs")
    for item in scenarios:
        require(set(item) == {"id", "result", "checksPassed", "checksTotal", "failureCode"}, "scenario fields")
        require(item["result"] in RESULTS and item["failureCode"] in FAILURES, "scenario enums")
        require(type(item["checksPassed"]) is int and type(item["checksTotal"]) is int, "check count type")
        require(0 <= item["checksPassed"] <= item["checksTotal"] and item["checksTotal"] >= 1, "check counts")
        if item["result"] == "pass":
            require(value["recordKind"] == "real_device", "synthetic pass")
            require(item["checksPassed"] == item["checksTotal"] and item["failureCode"] == "none", "pass scenario evidence")
        else:
            require(item["failureCode"] != "none", "non-pass scenario failureCode")
    if value["overall"] == "pass":
        require(value["recordKind"] == "real_device", "synthetic overall pass")
        require(all(item["result"] == "pass" for item in scenarios), "overall pass requires all scenarios")
    if "capabilities" in value:
        capabilities = value["capabilities"]
        fields = {"protectionLevel", "userAuthenticationAvailable", "deviceCredentialAvailable", "nonExportableKeys", "atomicDeviceRevocation"}
        require(type(capabilities) is dict and set(capabilities) == fields, "capability fields")
        require(capabilities["protectionLevel"] in {"unavailable", "software", "trusted_environment", "strongbox"}, "protectionLevel")
        require(all(type(capabilities[field]) is bool for field in fields - {"protectionLevel"}), "capability booleans")


if __name__ == "__main__":
    try:
        main(sys.argv[1])
    except (IndexError, OSError, ValueError, TypeError, json.JSONDecodeError) as error:
        print(f"EVIDENCE_SCHEMA=fail CODE={type(error).__name__}", file=sys.stderr)
        raise SystemExit(1)
