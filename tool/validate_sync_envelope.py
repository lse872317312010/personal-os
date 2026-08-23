#!/usr/bin/env python3
"""Dependency-free validator for ADR-0012 Sync Envelopes (v1).

Per ADR-0012 §"后续行动 #3" (M2-Exit), this script is the CI-level
validator for the EncryptedSyncEnvelope wire format. It enforces:

- Required fields: protocol_version, envelope_id, account_pseudonym,
  sender_device_id, recipient_epoch, sequence{first,last},
  ciphertext_length, ciphertext, signature.
- protocol_version must equal 1 (v1 wire).
- envelope_id must be a valid UUID v4 string.
- account_pseudonym must be non-empty (no business PII check is
  enforced at CI level — operator judgment required).
- sequence.last >= sequence.first >= 0.
- ciphertext must be valid base64.
- ciphertext_length must equal len(base64_decode(ciphertext)).
- signature must be valid base64.
- Optional --canonical-bytes flag prints the SHA-256 input that
  the device signs (per ADR-0012 §3) without performing Ed25519
  verification — full Ed25519 verification is deferred to Wave 22+
  when the production Relay lands.
- Optional --signature flag re-derives the SHA-256 of the canonical
  bytes and compares against the supplied hex digest (binary
  integrity check).

Exit codes:
- 0: schema + integrity OK
- 1: schema or integrity invalid
- 2: file unreadable / not a JSON object / CLI misuse
"""

import argparse
import base64
import hashlib
import json
import re
import sys
import uuid
from typing import Any

REQUIRED_FIELDS = {
    "protocol_version",
    "envelope_id",
    "account_pseudonym",
    "sender_device_id",
    "recipient_epoch",
    "sequence",
    "ciphertext_length",
    "ciphertext",
    "signature",
}

UUID_V4_RE = re.compile(
    r"^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$",
    re.IGNORECASE,
)
BASE64_RE = re.compile(r"^[A-Za-z0-9+/]*={0,2}$")


def require(condition: bool, label: str) -> None:
    if not condition:
        raise ValueError(label)


def _is_int(value: Any) -> bool:
    return isinstance(value, int) and not isinstance(value, bool)


def _is_base64(value: str) -> bool:
    if not isinstance(value, str) or not value:
        return False
    if not BASE64_RE.match(value):
        return False
    # Final sanity: actually try to decode to catch length errors.
    try:
        base64.b64decode(value, validate=True)
        return True
    except (ValueError, base64.binascii.Error):
        return False


def _is_uuid_v4(value: Any) -> bool:
    if not isinstance(value, str) or not UUID_V4_RE.match(value):
        return False
    # Cross-check via stdlib to catch rare RFC edge cases.
    try:
        parsed = uuid.UUID(value, version=4)
        return str(parsed) == value.lower()
    except (ValueError, AttributeError, TypeError):
        return False


def canonical_bytes(envelope: dict[str, Any]) -> bytes:
    """Per ADR-0012 §3: the SHA-256 input that the device signs.

    Format:
        sha256(
          protocol_version || '|' ||
          envelope_id || '|' ||
          account_pseudonym || '|' ||
          sender_device_id || '|' ||
          recipient_epoch || '|' ||
          sequence.first || ',' || sequence.last || '|' ||
          ciphertext_length || '|' ||
          ciphertext_bytes
        )

    NOTE: this returns the bytes *before* SHA-256 hashing. The signing
    scheme is Ed25519 — but the bytes the device signs are exactly
    these. For CI-level integrity checks we recompute the SHA-256 of
    these bytes (without doing Ed25519 verification, which would
    require the device's public key and a Curve25519 implementation).
    """
    seq = envelope["sequence"]
    preimage = (
        f"{envelope['protocol_version']}|"
        f"{envelope['envelope_id']}|"
        f"{envelope['account_pseudonym']}|"
        f"{envelope['sender_device_id']}|"
        f"{envelope['recipient_epoch']}|"
        f"{seq['first']},{seq['last']}|"
        f"{envelope['ciphertext_length']}|"
    ).encode("utf-8")
    ciphertext_bytes = base64.b64decode(envelope["ciphertext"], validate=True)
    return preimage + ciphertext_bytes


def validate_envelope(value: dict[str, Any]) -> None:
    require(type(value) is dict, "root must be a JSON object")
    require(
        set(value) >= REQUIRED_FIELDS,
        f"missing fields: {sorted(REQUIRED_FIELDS - set(value))}",
    )
    require(
        value["protocol_version"] == 1,
        f"protocol_version must equal 1 (got {value['protocol_version']!r})",
    )
    require(
        _is_uuid_v4(value["envelope_id"]),
        f"envelope_id must be a UUID v4 string (got {value['envelope_id']!r})",
    )
    require(
        isinstance(value["account_pseudonym"], str)
        and value["account_pseudonym"],
        "account_pseudonym must be a non-empty string",
    )
    require(
        isinstance(value["sender_device_id"], str)
        and value["sender_device_id"],
        "sender_device_id must be a non-empty string",
    )
    require(
        isinstance(value["recipient_epoch"], str)
        and value["recipient_epoch"],
        "recipient_epoch must be a non-empty string",
    )
    seq = value["sequence"]
    require(type(seq) is dict, "sequence must be an object")
    require(
        set(seq) == {"first", "last"},
        f"sequence must have exactly first+last (got {sorted(seq)})",
    )
    require(_is_int(seq["first"]), f"sequence.first must be int (got {seq['first']!r})")
    require(_is_int(seq["last"]), f"sequence.last must be int (got {seq['last']!r})")
    require(
        seq["first"] >= 0,
        f"sequence.first must be >= 0 (got {seq['first']!r})",
    )
    require(
        seq["last"] >= seq["first"],
        f"sequence.last must be >= sequence.first "
        f"(got first={seq['first']!r}, last={seq['last']!r})",
    )
    require(
        _is_int(value["ciphertext_length"]),
        f"ciphertext_length must be int (got {value['ciphertext_length']!r})",
    )
    require(
        value["ciphertext_length"] >= 0,
        f"ciphertext_length must be >= 0 (got {value['ciphertext_length']!r})",
    )
    require(
        _is_base64(value["ciphertext"]),
        "ciphertext must be valid base64",
    )
    decoded = base64.b64decode(value["ciphertext"], validate=True)
    require(
        len(decoded) == value["ciphertext_length"],
        f"ciphertext_length mismatch: declared={value['ciphertext_length']!r} "
        f"actual={len(decoded)!r}",
    )
    require(
        _is_base64(value["signature"]),
        "signature must be valid base64",
    )
    print(
        f"SYNC_ENVELOPE_OK seq={seq['first']}..{seq['last']} "
        f"ct_len={value['ciphertext_length']} "
        f"envelope_id={value['envelope_id']}",
        file=sys.stderr,
    )


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(
        description="Validate an ADR-0012 Sync Envelope (v1 wire).",
    )
    parser.add_argument("envelope", help="path to the envelope JSON file")
    parser.add_argument(
        "--canonical-bytes-sha256",
        metavar="HEX",
        help="recompute the SHA-256 of the canonical signing bytes "
        "(ADR-0012 §3) and compare against this hex digest",
    )
    parser.add_argument(
        "--print-canonical-bytes-sha256",
        action="store_true",
        help="print the SHA-256 of the canonical signing bytes to stdout "
        "and exit 0 (useful for generating test vectors)",
    )
    args = parser.parse_args(argv)

    try:
        with open(args.envelope, encoding="utf-8") as source:
            value = json.load(source)
    except (OSError, json.JSONDecodeError) as error:
        print(f"ERROR: cannot read envelope file: {error}", file=sys.stderr)
        return 1

    try:
        validate_envelope(value)
    except (ValueError, TypeError) as error:
        print(f"SYNC_ENVELOPE_SCHEMA=fail: {error}", file=sys.stderr)
        return 1

    if args.print_canonical_bytes_sha256:
        cb = canonical_bytes(value)
        print(hashlib.sha256(cb).hexdigest())
        return 0

    if args.canonical_bytes_sha256:
        cb = canonical_bytes(value)
        actual = hashlib.sha256(cb).hexdigest()
        expected = args.canonical_bytes_sha256.lower()
        if actual != expected:
            print(
                f"SYNC_ENVELOPE_SHA256_MISMATCH expected={expected} "
                f"actual={actual}",
                file=sys.stderr,
            )
            return 1
        print("SYNC_ENVELOPE_SHA256=match", file=sys.stderr)

    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except KeyboardInterrupt:
        sys.exit(2)
