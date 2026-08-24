#!/usr/bin/env python3
"""Tests for the structural ADR-0012 Sync Envelope validator."""
from __future__ import annotations
import base64
import importlib.util
import json
import pathlib
import subprocess
import sys
import tempfile
import unittest
import uuid

ROOT = pathlib.Path(__file__).resolve().parents[2]
VALIDATOR = ROOT / "tool" / "validate_sync_envelope.py"
spec = importlib.util.spec_from_file_location("sync_validator", VALIDATOR)
validator = importlib.util.module_from_spec(spec)
assert spec.loader is not None
sys.modules[spec.name] = validator
spec.loader.exec_module(validator)


def envelope(**overrides):
    ciphertext = bytes(range(32))
    result = {
        "protocol_version": 1,
        "envelope_id": str(uuid.uuid4()),
        "account_pseudonym": "acct-pseudonym",
        "sender_device_id": "device-redmi-turbo-01",
        "recipient_epoch": "epoch-2026-08-24",
        "sequence": {"first": 0, "last": 7},
        "ciphertext_length": len(ciphertext),
        "ciphertext": base64.b64encode(ciphertext).decode("ascii"),
        "signature": base64.b64encode(bytes(64)).decode("ascii"),
    }
    result.update(overrides)
    return result


class ValidatorTest(unittest.TestCase):
    def test_valid_synthetic_fixture_is_structural_only(self):
        path = ROOT / "evidence/sync_envelope/synthetic.example.json"
        process = subprocess.run(
            [sys.executable, str(VALIDATOR), str(path)],
            capture_output=True, text=True, check=False,
        )
        self.assertEqual(process.returncode, 0, process.stderr)
        self.assertIn("SYNC_ENVELOPE_SCHEMA=pass", process.stderr)
        self.assertIn("SYNC_ENVELOPE_SIGNATURE=unverified", process.stderr)

    def test_required_fields_and_unknown_fields(self):
        value = envelope(extra_future_field="ignored")
        validator.validate_envelope(value)
        del value["signature"]
        with self.assertRaises(ValueError):
            validator.validate_envelope(value)

    def test_lengths_and_signature_shape(self):
        value = envelope(ciphertext_length=31)
        with self.assertRaisesRegex(ValueError, "ciphertext_length mismatch"):
            validator.validate_envelope(value)
        value = envelope(signature=base64.b64encode(bytes(63)).decode("ascii"))
        with self.assertRaisesRegex(ValueError, "exactly 64"):
            validator.validate_envelope(value)

    def test_versions_and_sequence(self):
        with self.assertRaises(ValueError):
            validator.validate_envelope(envelope(protocol_version=2))
        with self.assertRaises(ValueError):
            validator.validate_envelope(
                envelope(sequence={"first": 8, "last": 7})
            )

    def test_canonical_preimage_is_deterministic_and_binary(self):
        first = validator.validate_envelope(envelope())
        second = validator.validate_envelope(envelope(
            envelope_id=first["envelope_id"],
            account_pseudonym=first["account_pseudonym"],
            sender_device_id=first["sender_device_id"],
            recipient_epoch=first["recipient_epoch"],
            sequence=first["sequence"],
            ciphertext_length=first["ciphertext_length"],
            ciphertext=base64.b64encode(first["ciphertext_bytes"]).decode("ascii"),
            signature=base64.b64encode(first["signature_bytes"]).decode("ascii"),
        ))
        self.assertEqual(validator.canonical_preimage(first),
                         validator.canonical_preimage(second))
        self.assertTrue(validator.canonical_preimage(first).startswith(
            b"personal-os/sync-envelope/v1"
        ))

    def test_canonical_preimage_changes_when_a_signed_field_changes(self):
        first = validator.validate_envelope(envelope())
        changed = validator.validate_envelope(envelope(sender_device_id="device-other"))
        self.assertNotEqual(validator.canonical_preimage(first),
                            validator.canonical_preimage(changed))

    def test_cli_diagnostic_digest_is_not_a_signature_verification(self):
        path = pathlib.Path(tempfile.mkstemp(suffix=".json")[1])
        try:
            path.write_text(json.dumps(envelope()), encoding="utf-8")
            process = subprocess.run(
                [sys.executable, str(VALIDATOR), str(path),
                 "--print-canonical-preimage-sha256"],
                capture_output=True, text=True, check=False,
            )
            self.assertEqual(process.returncode, 0, process.stderr)
            self.assertRegex(process.stdout.strip(), r"^[0-9a-f]{64}$")
            self.assertIn("unverified", process.stderr)
        finally:
            path.unlink(missing_ok=True)


if __name__ == "__main__":
    unittest.main()
