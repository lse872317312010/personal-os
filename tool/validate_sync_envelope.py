#!/usr/bin/env python3
"""Structural validator for the ADR-0012 Sync Envelope v1 wire contract.

This tool validates JSON shape, base64 encoding, byte lengths, and derives the
canonical signing preimage. It intentionally does not verify Ed25519: a
signature-shaped byte string is not evidence of authenticity until a trusted
device public key and a production crypto adapter exist.
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import struct
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
MAX_U64 = (1 << 64) - 1
DOMAIN = b"personal-os/sync-envelope/v1"


def _fail(message: str) -> None:
    raise ValueError(message)


def _is_int(value: Any) -> bool:
    return isinstance(value, int) and not isinstance(value, bool)


def _decode_b64(value: Any, field: str) -> bytes:
    if not isinstance(value, str) or not value:
        _fail(f"{field} must be a non-empty base64 string")
    try:
        return base64.b64decode(value, validate=True)
    except (ValueError, base64.binascii.Error) as error:
        _fail(f"{field} must be valid base64: {error}")
    raise AssertionError("unreachable")


def _require_u64(value: Any, field: str) -> int:
    if not _is_int(value) or value < 0 or value > MAX_U64:
        _fail(f"{field} must be an unsigned 64-bit integer")
    return value


def _require_text(value: Any, field: str) -> str:
    if not isinstance(value, str) or not value:
        _fail(f"{field} must be a non-empty string")
    try:
        value.encode("utf-8")
    except UnicodeEncodeError as error:
        _fail(f"{field} must be valid UTF-8: {error}")
    return value


def _uuid_v4(value: Any) -> str:
    text = _require_text(value, "envelope_id")
    try:
        parsed = uuid.UUID(text)
    except ValueError as error:
        _fail(f"envelope_id must be a UUID v4: {error}")
    if parsed.version != 4 or str(parsed) != text.lower():
        _fail("envelope_id must be a canonical UUID v4 string")
    return text


def validate_envelope(value: Any) -> dict[str, Any]:
    if type(value) is not dict:
        _fail("root must be a JSON object")
    missing = REQUIRED_FIELDS - set(value)
    if missing:
        _fail(f"missing fields: {sorted(missing)}")
    if not _is_int(value["protocol_version"]) or value["protocol_version"] != 1:
        _fail("protocol_version must be integer 1")
    _uuid_v4(value["envelope_id"])
    _require_text(value["account_pseudonym"], "account_pseudonym")
    _require_text(value["sender_device_id"], "sender_device_id")
    _require_text(value["recipient_epoch"], "recipient_epoch")

    sequence = value["sequence"]
    if type(sequence) is not dict or set(sequence) != {"first", "last"}:
        _fail("sequence must contain exactly first and last")
    first = _require_u64(sequence["first"], "sequence.first")
    last = _require_u64(sequence["last"], "sequence.last")
    if last < first:
        _fail("sequence.last must be >= sequence.first")

    ciphertext_length = _require_u64(
        value["ciphertext_length"], "ciphertext_length"
    )
    ciphertext = _decode_b64(value["ciphertext"], "ciphertext")
    if len(ciphertext) != ciphertext_length:
        _fail(
            "ciphertext_length mismatch: "
            f"declared={ciphertext_length} actual={len(ciphertext)}"
        )
    signature = _decode_b64(value["signature"], "signature")
    if len(signature) != 64:
        _fail("signature must decode to exactly 64 bytes for Ed25519")

    return {
        "protocol_version": 1,
        "envelope_id": value["envelope_id"],
        "account_pseudonym": value["account_pseudonym"],
        "sender_device_id": value["sender_device_id"],
        "recipient_epoch": value["recipient_epoch"],
        "sequence": {"first": first, "last": last},
        "ciphertext_length": ciphertext_length,
        "ciphertext_bytes": ciphertext,
        "signature_bytes": signature,
    }


def _u32(value: int) -> bytes:
    if value < 0 or value > 0xFFFFFFFF:
        _fail("text field exceeds u32 length")
    return struct.pack(">I", value)


def _u64(value: int) -> bytes:
    return struct.pack(">Q", _require_u64(value, "canonical integer"))


def canonical_preimage(envelope: dict[str, Any]) -> bytes:
    """Build canonical_preimage_v1; this does not verify a signature."""
    parts = [DOMAIN, _u32(envelope["protocol_version"])]
    for field in (
        "envelope_id",
        "account_pseudonym",
        "sender_device_id",
        "recipient_epoch",
    ):
        encoded = envelope[field].encode("utf-8")
        parts.extend((_u32(len(encoded)), encoded))
    sequence = envelope["sequence"]
    parts.extend(
        (
            _u64(sequence["first"]),
            _u64(sequence["last"]),
            _u64(envelope["ciphertext_length"]),
            envelope["ciphertext_bytes"],
        )
    )
    return b"".join(parts)


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(
        description="Validate an ADR-0012 Sync Envelope structurally."
    )
    parser.add_argument("envelope", help="path to envelope JSON")
    parser.add_argument(
        "--print-canonical-preimage-sha256",
        action="store_true",
        help="print a diagnostic SHA-256 of canonical_preimage_v1",
    )
    args = parser.parse_args(argv)
    try:
        with open(args.envelope, encoding="utf-8") as source:
            raw = json.load(source)
        envelope = validate_envelope(raw)
        preimage = canonical_preimage(envelope)
    except (OSError, json.JSONDecodeError, ValueError, TypeError) as error:
        print(f"SYNC_ENVELOPE_SCHEMA=fail: {error}", file=sys.stderr)
        return 1

    print(
        "SYNC_ENVELOPE_SCHEMA=pass "
        f"seq={envelope['sequence']['first']}..{envelope['sequence']['last']} "
        f"ct_len={envelope['ciphertext_length']}",
        file=sys.stderr,
    )
    print("SYNC_ENVELOPE_SIGNATURE=unverified", file=sys.stderr)
    if args.print_canonical_preimage_sha256:
        print(hashlib.sha256(preimage).hexdigest())
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
