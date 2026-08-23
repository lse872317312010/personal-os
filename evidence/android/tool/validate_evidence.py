#!/usr/bin/env python3
"""Dependency-free validator mirroring the non-sensitive evidence schema."""

import datetime
import json
import sys
from typing import Any

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

# ADR-0014 §6: error.cause and error.stack_trace MUST NOT appear anywhere in
# the evidence JSON. The recursive walker below catches both the top-level
# error object and any nested debugging leaks introduced by future schema
# extensions. Entries are stored in canonical lowercase; the walker
# normalizes each encountered key via .lower() so snake_case, camelCase,
# and PascalCase variants all match. Bare "stack" / "trace" are
# intentionally omitted to avoid false positives on unrelated fields.
FORBIDDEN_ERROR_KEYS = frozenset({
    "cause",
    "stack_trace",
    "stacktrace",
    "inner_exception",
    "innerexception",
    "raw_exception",
    "rawexception",
})


def require(condition: bool, label: str) -> None:
    if not condition:
        raise ValueError(label)


def _walk_forbidden_error_fields(value: Any, path: str = "$") -> list[str]:
    """Recursively flag forbidden error-debugging keys.

    Returns a list of human-readable violations; an empty list means the
    value is safe. The walker is defense-in-depth: even if the JSON schema
    permits a new field, this rule still rejects ``cause`` / ``stack_trace``
    style debug leaks before they enter the evidence ledger.
    """

    issues: list[str] = []
    if isinstance(value, dict):
        for key, child in value.items():
            normalized = str(key).lower()
            if normalized in FORBIDDEN_ERROR_KEYS:
                issues.append(f"{path}.{key}: forbidden error-debugging field")
            issues.extend(_walk_forbidden_error_fields(child, f"{path}.{key}"))
    elif isinstance(value, list):
        for index, child in enumerate(value):
            issues.extend(_walk_forbidden_error_fields(child, f"{path}[{index}]"))
    return issues


def validate_error_field(value: Any) -> None:
    """Validate the optional top-level ``error`` object (ADR-0014 §1, §6).

    The error field is the persistence-layer failure signal carried into the
    evidence ledger. Only ``code`` (stable wire value) and ``safe_message``
    (auditor-readable reason) are permitted. ``cause`` / ``stack_trace``
    are caught by :func:`_walk_forbidden_error_fields` even if a malicious
    or careless writer tries to add them here.
    """

    require(type(value) is dict, "error: must be object")
    require(set(value) <= {"code", "safe_message"}, "error: allowed fields")
    require(isinstance(value.get("code"), str) and value["code"],
            "error.code: must be non-empty string")
    safe_message = value.get("safe_message")
    require(safe_message is None or isinstance(safe_message, str),
            "error.safe_message: must be string or null")


def main(path: str) -> None:
    with open(path, encoding="utf-8") as source:
        value = json.load(source)

    # Defense-in-depth: walk the entire tree first so a forbidden key at any
    # depth is caught before structural validation short-circuits.
    forbidden = _walk_forbidden_error_fields(value)
    require(not forbidden, "; ".join(forbidden))

    required = {"schemaVersion", "recordKind", "targetClass", "buildProfile",
                "startedAtUtc", "completedAtUtc", "overall", "scenarios"}
    allowed = required | {"capabilities", "error"}
    require(type(value) is dict and set(value) <= allowed and required <= set(value),
            "root fields")
    require(value["schemaVersion"] == 1, "schemaVersion")
    require(value["recordKind"] in {"real_device", "synthetic"}, "recordKind")
    require(value["targetClass"] == "redmi_turbo", "targetClass")
    require(value["buildProfile"] in {"debug", "profile", "release"}, "buildProfile")
    require(value["overall"] in RESULTS, "overall")
    for field in ("startedAtUtc", "completedAtUtc"):
        datetime.datetime.fromisoformat(value[field].replace("Z", "+00:00"))
    scenarios = value["scenarios"]
    require(type(scenarios) is list and len(scenarios) == 9, "scenarios length")
    require({item.get("id") for item in scenarios} == SCENARIOS, "scenario IDs")
    for item in scenarios:
        require(set(item) == {"id", "result", "checksPassed", "checksTotal", "failureCode"},
                "scenario fields")
        require(item["result"] in RESULTS and item["failureCode"] in FAILURES,
                "scenario enums")
        require(type(item["checksPassed"]) is int and type(item["checksTotal"]) is int,
                "check count type")
        require(0 <= item["checksPassed"] <= item["checksTotal"]
                and item["checksTotal"] >= 1, "check counts")
    if "capabilities" in value:
        capabilities = value["capabilities"]
        fields = {"protectionLevel", "userAuthenticationAvailable",
                  "deviceCredentialAvailable", "nonExportableKeys",
                  "atomicDeviceRevocation"}
        require(type(capabilities) is dict and set(capabilities) == fields,
                "capability fields")
        require(capabilities["protectionLevel"]
                in {"unavailable", "software", "trusted_environment", "strongbox"},
                "protectionLevel")
        require(all(type(capabilities[field]) is bool
                    for field in fields - {"protectionLevel"}),
                "capability booleans")
    if "error" in value:
        validate_error_field(value["error"])


if __name__ == "__main__":
    try:
        main(sys.argv[1])
    except (IndexError, OSError, ValueError, TypeError, json.JSONDecodeError) as error:
        print(f"EVIDENCE_SCHEMA=fail CODE={type(error).__name__}", file=sys.stderr)
        raise SystemExit(1)
