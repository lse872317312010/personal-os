#!/usr/bin/env python3
"""Dependency-free validator for evidence files.

Per ADR-0010 §4, this script is the CI-level validator for the evidence
ledger chain. It auto-detects the file shape:

- ``evidence/mvp/status.json`` (schema_version + records) — validates the
  ADR-0010 SHA-256 chain integrity.
- ``evidence/android/records/*.json`` (schemaVersion + scenarios) —
  validates the Android device record schema.

Exit codes:
- 0: schema + chain OK
- 1: schema or chain invalid
- 2: file unreadable / not a JSON object
"""

import datetime
import hashlib
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

# ADR-0010 chain constants — must match tool/evidence_writer.py.
RECORD_ID_LEN = 12
GENESIS_PREV_ID = "0" * RECORD_ID_LEN
KIND_LEVELS = {"synthetic", "real", "device"}
RECORD_STATUSES = {"PASS", "FAIL", "BLOCKED"}
REQUIRED_RECORD_FIELDS = {
    "record_id", "previous_record_id", "recorded_at",
    "candidate_commit", "kind", "wave", "track",
    "gate", "status", "artifacts",
    "evidence_writer_version", "notes",
}


def require(condition: bool, label: str) -> None:
    if not condition:
        raise ValueError(label)


def _is_hex(value: str, length: int) -> bool:
    return (
        isinstance(value, str)
        and len(value) == length
        and all(ch in "0123456789abcdef" for ch in value)
    )


def _is_record_id(value: Any) -> bool:
    return _is_hex(value, RECORD_ID_LEN)


def _is_sha256(value: Any) -> bool:
    return _is_hex(value, 64)


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


def validate_chain(value: dict[str, Any]) -> None:
    """Validate the ADR-0010 SHA-256 chain in the ``records`` array."""
    require(type(value) is dict, "ledger root must be object")
    require(value.get("schema_version") == 1, "schema_version must equal 1")
    require(
        value.get("kind") in {"real", "synthetic", "device"},
        "ledger kind must be one of real/synthetic/device",
    )
    require(
        _is_hex(str(value.get("candidate_commit", "")), 40),
        "candidate_commit must be 40-hex lowercase",
    )
    records = value.get("records")
    require(type(records) is list, "records must be a list")
    prev_id = GENESIS_PREV_ID
    for idx, record in enumerate(records):
        label = f"records[{idx}]"
        require(type(record) is dict, f"{label}: must be object")
        require(
            set(record) >= REQUIRED_RECORD_FIELDS,
            f"{label}: missing fields "
            f"{sorted(REQUIRED_RECORD_FIELDS - set(record))}",
        )
        rid = record["record_id"]
        prev = record["previous_record_id"]
        require(_is_record_id(rid), f"{label}.record_id invalid: {rid!r}")
        require(_is_record_id(prev), f"{label}.previous_record_id invalid: {prev!r}")
        require(prev == prev_id, (
            f"{label}.previous_record_id={prev} but expected {prev_id} "
            "(chain broken — record was inserted or re-ordered)"
        ))
        expected_rid = _compute_record_id(
            prev_id,
            str(record["candidate_commit"]),
            str(record["recorded_at"]),
            str(record["gate"]),
            str(record["status"]),
        )
        require(expected_rid == rid, (
            f"{label}.record_id={rid} but recomputed={expected_rid} "
            "(content does not match chain — record was tampered with)"
        ))
        require(
            record["kind"] in KIND_LEVELS,
            f"{label}.kind must be one of {sorted(KIND_LEVELS)}",
        )
        require(
            record["status"] in RECORD_STATUSES,
            f"{label}.status must be one of {sorted(RECORD_STATUSES)}",
        )
        require(
            isinstance(record["artifacts"], list),
            f"{label}.artifacts must be a list",
        )
        for a_idx, artifact in enumerate(record["artifacts"]):
            a_label = f"{label}.artifacts[{a_idx}]"
            require(type(artifact) is dict, f"{a_label}: must be object")
            require(
                set(artifact) == {"name", "sha256"},
                f"{a_label}: must have exactly name+sha256",
            )
            require(
                isinstance(artifact["name"], str) and artifact["name"],
                f"{a_label}.name must be non-empty string",
            )
            sha = artifact["sha256"]
            require(
                sha == "" or _is_sha256(sha),
                f"{a_label}.sha256 must be empty or 64-hex",
            )
        # RFC3339 UTC sanity check
        datetime.datetime.fromisoformat(
            record["recorded_at"].replace("Z", "+00:00")
        )
        prev_id = rid
    if records:
        print(
            f"EVIDENCE_CHAIN=ok records={len(records)} "
            f"last_record_id={prev_id}",
            file=sys.stderr,
        )
    else:
        print("EVIDENCE_CHAIN=ok records=0 (genesis only)", file=sys.stderr)


def validate_android_record(value: dict[str, Any]) -> None:
    required = {"schemaVersion", "recordKind", "targetClass", "buildProfile",
                "startedAtUtc", "completedAtUtc", "overall", "scenarios"}
    allowed = required | {"capabilities"}
    require(type(value) is dict and set(value) <= allowed and required <= set(value), "root fields")
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
        require(set(item) == {"id", "result", "checksPassed", "checksTotal", "failureCode"}, "scenario fields")
        require(item["result"] in RESULTS and item["failureCode"] in FAILURES, "scenario enums")
        require(type(item["checksPassed"]) is int and type(item["checksTotal"]) is int, "check count type")
        require(0 <= item["checksPassed"] <= item["checksTotal"] and item["checksTotal"] >= 1, "check counts")
    if "capabilities" in value:
        capabilities = value["capabilities"]
        fields = {"protectionLevel", "userAuthenticationAvailable", "deviceCredentialAvailable", "nonExportableKeys", "atomicDeviceRevocation"}
        require(type(capabilities) is dict and set(capabilities) == fields, "capability fields")
        require(capabilities["protectionLevel"] in {"unavailable", "software", "trusted_environment", "strongbox"}, "protectionLevel")
        require(all(type(capabilities[field]) is bool for field in fields - {"protectionLevel"}), "capability booleans")


def main(path: str) -> None:
    with open(path, encoding="utf-8") as source:
        value = json.load(source)
    require(type(value) is dict, "root must be a JSON object")
    # Auto-dispatch by schema shape (ADR-0010 §4).
    if "schema_version" in value and "records" in value:
        validate_chain(value)
    elif "schemaVersion" in value and "scenarios" in value:
        validate_android_record(value)
    else:
        raise ValueError(
            "unrecognized evidence file shape: expected "
            "{schema_version,records} or {schemaVersion,scenarios}"
        )


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("usage: validate_evidence.py <evidence.json>", file=sys.stderr)
        raise SystemExit(2)
    try:
        main(sys.argv[1])
    except (OSError, ValueError, TypeError, json.JSONDecodeError) as error:
        print(f"EVIDENCE_SCHEMA=fail CODE={type(error).__name__}: {error}",
              file=sys.stderr)
        raise SystemExit(1)
