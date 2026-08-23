#!/usr/bin/env python3
"""ADR-0011 §"后续行动 #3" — Vault Export Envelope validator.

Validates the on-disk JSON envelope produced by Wave 17a `VaultExporter`.
The contract is documented in ADR-0011 (docs/decisions/0011-vault-export-envelope-format.md).

Checks (in order):
1. Root is a JSON object.
2. All 7 required fields are present:
   - schema_version (int, ==1)
   - exported_at (RFC3339 UTC)
   - composition_mode (in {"demo","devSqlite","prodEncrypted"})
   - events (list)
   - blob_manifest (list)
   - event_count (int, == len(events))
   - blob_count (int, == len(blob_manifest))
   - passphrase_challenge (string hex sha256 | null)
3. Per-event JSON shapes match EventEnvelopeJsonCodec output
   (id, schema_version, revision, stream_id, occurred_at, appended_at, payload).
4. SHA-256(envelope_bytes).hexdigest() equals `expected_sha256_hex` if
   supplied via --sha256; otherwise just prints the computed digest.
5. HMAC-SHA256(envelope_bytes, signing_key) hex equals `expected_signature_hex`
   if supplied via --signature + --passphrase (or --no-passphrase for dev seed).

Exit codes:
- 0: envelope is valid (and matches the optional --sha256 / --signature)
- 1: envelope schema invalid OR hash/signature mismatch
- 2: file unreadable / not a JSON object

Usage:
  python3 tool/validate_export_envelope.py <envelope.json>
  python3 tool/validate_export_envelope.py <envelope.json> \\
         --sha256 <hex64> \\
         --signature <hex64> \\
         [--passphrase <text> | --no-passphrase]

Refs:
- ADR-0011 Vault Export Envelope Format (v1)
- Wave 17a packages/storage_api/lib/src/vault_exporter.dart
"""
from __future__ import annotations

import argparse
import datetime
import hashlib
import hmac
import json
import sys
from pathlib import Path
from typing import Any

REQUIRED_FIELDS: tuple[str, ...] = (
    "schema_version",
    "exported_at",
    "composition_mode",
    "events",
    "blob_manifest",
    "event_count",
    "blob_count",
    "passphrase_challenge",
)

COMPOSITION_MODES: frozenset[str] = frozenset(
    {"demo", "devSqlite", "prodEncrypted"}
)

# Per ADR-0011 §"后续行动 #2": blob_manifest 元素 schema.
REQUIRED_BLOB_MANIFEST_FIELDS: frozenset[str] = frozenset(
    {"ref", "media_type", "byte_length", "sha256_hex"}
)

# EventEnvelopeJsonCodec 输出字段（M1 已落地）。
# 见 packages/events/lib/src/event_envelope.dart + json_codec.dart。
REQUIRED_EVENT_FIELDS: frozenset[str] = frozenset(
    {
        "event_id",
        "schema_version",
        "revision",
        "stream_id",
        "occurred_at",
        "appended_at",
        "payload",
    }
)

DEV_SIGNING_SEED = "personal-os-vault-export-dev-signing-seed-v1"


def require(condition: bool, label: str) -> None:
    if not condition:
        raise ValueError(label)


def _is_hex(value: Any, length: int) -> bool:
    return (
        isinstance(value, str)
        and len(value) == length
        and all(ch in "0123456789abcdef" for ch in value)
    )


def _is_rfc3339_utc(value: str) -> bool:
    try:
        # datetime.fromisoformat handles "+00:00" but not "Z" until 3.11+;
        # we accept both, and require timezone-aware (UTC or any offset).
        ts = value.replace("Z", "+00:00")
        parsed = datetime.datetime.fromisoformat(ts)
        return parsed.tzinfo is not None
    except (ValueError, TypeError):
        return False


def validate_envelope(value: dict[str, Any]) -> None:
    """Validate ADR-0011 §1 envelope schema. Raises ValueError on failure."""
    require(type(value) is dict, "root must be a JSON object")
    require(set(value) >= set(REQUIRED_FIELDS), f"missing fields: "
            f"{sorted(set(REQUIRED_FIELDS) - set(value))}")

    require(
        value["schema_version"] == 1,
        f"schema_version must equal 1 (got {value['schema_version']!r})",
    )
    require(
        value["composition_mode"] in COMPOSITION_MODES,
        f"composition_mode must be one of {sorted(COMPOSITION_MODES)} "
        f"(got {value['composition_mode']!r})",
    )
    require(
        _is_rfc3339_utc(value["exported_at"]),
        f"exported_at must be RFC3339 UTC (got {value['exported_at']!r})",
    )

    events = value["events"]
    blob_manifest = value["blob_manifest"]
    require(type(events) is list, "events must be a list")
    require(type(blob_manifest) is list, "blob_manifest must be a list")
    require(
        isinstance(value["event_count"], int)
        and value["event_count"] == len(events),
        f"event_count ({value['event_count']!r}) must equal "
        f"len(events) ({len(events)})",
    )
    require(
        isinstance(value["blob_count"], int)
        and value["blob_count"] == len(blob_manifest),
        f"blob_count ({value['blob_count']!r}) must equal "
        f"len(blob_manifest) ({len(blob_manifest)})",
    )

    pc = value["passphrase_challenge"]
    require(
        pc is None or _is_hex(pc, 64),
        f"passphrase_challenge must be null or 64-hex sha256 "
        f"(got {pc!r})",
    )

    # Per-event shape check.
    for idx, event in enumerate(events):
        label = f"events[{idx}]"
        require(type(event) is dict, f"{label}: must be object")
        missing = set(REQUIRED_EVENT_FIELDS) - set(event)
        require(
            not missing,
            f"{label}: missing fields {sorted(missing)}",
        )
        require(
            isinstance(event["event_id"], str) and event["event_id"],
            f"{label}.event_id must be non-empty string",
        )
        require(
            isinstance(event["schema_version"], int)
            and event["schema_version"] >= 1,
            f"{label}.schema_version must be int >= 1",
        )
        require(
            isinstance(event["revision"], (str, int))
            and (str(event["revision"]).strip() != ""),
            f"{label}.revision must be non-empty string or int",
        )
        require(
            isinstance(event["stream_id"], str) and event["stream_id"],
            f"{label}.stream_id must be non-empty string",
        )
        require(
            _is_rfc3339_utc(event["occurred_at"]),
            f"{label}.occurred_at must be RFC3339 UTC",
        )
        require(
            _is_rfc3339_utc(event["appended_at"]),
            f"{label}.appended_at must be RFC3339 UTC",
        )
        require(
            type(event["payload"]) is dict,
            f"{label}.payload must be a JSON object",
        )

    # Per-blob manifest element check (ADR-0011 §"后续行动 #2").
    for idx, blob in enumerate(blob_manifest):
        label = f"blob_manifest[{idx}]"
        require(type(blob) is dict, f"{label}: must be object")
        missing = set(REQUIRED_BLOB_MANIFEST_FIELDS) - set(blob)
        require(
            not missing,
            f"{label}: missing fields {sorted(missing)}",
        )
        require(
            isinstance(blob["ref"], str) and blob["ref"],
            f"{label}.ref must be non-empty string",
        )
        require(
            isinstance(blob["media_type"], str) and blob["media_type"],
            f"{label}.media_type must be non-empty string",
        )
        require(
            isinstance(blob["byte_length"], int) and blob["byte_length"] >= 0,
            f"{label}.byte_length must be non-negative int",
        )
        sha = blob["sha256_hex"]
        require(
            sha == "" or _is_hex(sha, 64),
            f"{label}.sha256_hex must be empty or 64-hex",
        )


def compute_sha256_hex(envelope_bytes: bytes) -> str:
    return hashlib.sha256(envelope_bytes).hexdigest()


def compute_signature_hex(envelope_bytes: bytes, signing_key: bytes) -> str:
    return hmac.new(signing_key, envelope_bytes, hashlib.sha256).hexdigest()


def signing_key_for(passphrase: str | None) -> bytes:
    if passphrase is not None:
        return passphrase.encode("utf-8")
    return DEV_SIGNING_SEED.encode("utf-8")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="ADR-0011 Vault Export Envelope validator.",
    )
    parser.add_argument(
        "envelope_path",
        type=Path,
        help="Path to the envelope JSON file.",
    )
    parser.add_argument(
        "--sha256",
        type=str,
        default=None,
        help="Expected SHA-256 hex of the envelope bytes (optional).",
    )
    parser.add_argument(
        "--signature",
        type=str,
        default=None,
        help="Expected HMAC-SHA256 hex of the envelope bytes (optional).",
    )
    parser.add_argument(
        "--passphrase",
        type=str,
        default=None,
        help="Passphrase used to sign the envelope (mutually exclusive "
        "with --no-passphrase). If neither flag is given, the dev "
        "signing seed is used.",
    )
    parser.add_argument(
        "--no-passphrase",
        action="store_true",
        help="Explicitly assert the envelope was signed with the dev "
        "signing seed (i.e. no passphrase was supplied at export time).",
    )
    args = parser.parse_args(argv)

    if not args.envelope_path.is_file():
        print(
            f"ERROR: envelope file not found: {args.envelope_path}",
            file=sys.stderr,
        )
        return 2

    if args.passphrase is not None and args.no_passphrase:
        print(
            "ERROR: --passphrase and --no-passphrase are mutually exclusive.",
            file=sys.stderr,
        )
        return 2

    try:
        envelope_bytes = args.envelope_path.read_bytes()
        value = json.loads(envelope_bytes.decode("utf-8"))
    except (OSError, json.JSONDecodeError, UnicodeDecodeError) as error:
        print(
            f"ERROR: cannot read envelope file: {type(error).__name__}: {error}",
            file=sys.stderr,
        )
        return 2

    try:
        validate_envelope(value)
    except ValueError as error:
        print(f"ENVELOPE_SCHEMA=fail: {error}", file=sys.stderr)
        return 1

    actual_sha256 = compute_sha256_hex(envelope_bytes)
    print(f"ENVELOPE_SHA256={actual_sha256}", file=sys.stderr)
    if args.sha256 is not None:
        if args.sha256.lower() != actual_sha256:
            print(
                f"ENVELOPE_SHA256_MISMATCH expected={args.sha256.lower()} "
                f"actual={actual_sha256}",
                file=sys.stderr,
            )
            return 1
        print("ENVELOPE_SHA256=match", file=sys.stderr)

    if args.signature is not None:
        # Choose signing key.
        if args.no_passphrase:
            signing_key = signing_key_for(None)
        else:
            signing_key = signing_key_for(args.passphrase)
        actual_signature = compute_signature_hex(envelope_bytes, signing_key)
        if args.signature.lower() != actual_signature:
            print(
                f"ENVELOPE_SIGNATURE_MISMATCH expected={args.signature.lower()} "
                f"actual={actual_signature}",
                file=sys.stderr,
            )
            return 1
        print("ENVELOPE_SIGNATURE=match", file=sys.stderr)

    events_count = len(value["events"])
    blobs_count = len(value["blob_manifest"])
    print(
        f"ENVELOPE_OK events={events_count} blobs={blobs_count} "
        f"mode={value['composition_mode']}",
        file=sys.stderr,
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
