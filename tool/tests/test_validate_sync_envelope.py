#!/usr/bin/env python3
"""Unit tests for tool/validate_sync_envelope.py (ADR-0012 v1).

Covers schema validation, ciphertext_length integrity, UUID v4
envelope_id, sequence ordering, base64 decoding, and canonical-bytes
SHA-256 re-derivation.

Run via: python3 -m unittest discover -s tool/tests -p 'test_*.py'
"""

import base64
import hashlib
import importlib.util
import json
import pathlib
import subprocess
import sys
import tempfile
import unittest
import uuid

REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
VALIDATOR = REPO_ROOT / "tool" / "validate_sync_envelope.py"

# Import the validator as a module so we can unit-test internal functions.
spec = importlib.util.spec_from_file_location(
    "validate_sync_envelope", VALIDATOR,
)
validate_sync_envelope = importlib.util.module_from_spec(spec)
sys.modules["validate_sync_envelope"] = validate_sync_envelope
spec.loader.exec_module(validate_sync_envelope)


def _envelope(**overrides):
    """Build a baseline valid envelope; overrides are applied last."""
    ciphertext_bytes = b"\x12\x34\x56\x78\x9a\xbc\xde\xf0" * 4  # 32 bytes
    base = {
        "protocol_version": 1,
        "envelope_id": str(uuid.uuid4()),
        "account_pseudonym": "acct-pseudonym-0123456789abcdef",
        "sender_device_id": "device-redmi-turbo-01",
        "recipient_epoch": "epoch-2026-08-23",
        "sequence": {"first": 0, "last": 7},
        "ciphertext_length": len(ciphertext_bytes),
        "ciphertext": base64.b64encode(ciphertext_bytes).decode("ascii"),
        "signature": base64.b64encode(b"\x00" * 64).decode("ascii"),
    }
    base.update(overrides)
    # If overrides changed ciphertext, recompute length.
    if "ciphertext" in overrides and "ciphertext_length" not in overrides:
        decoded = base64.b64decode(base["ciphertext"], validate=True)
        base["ciphertext_length"] = len(decoded)
    return base


class TestSchema(unittest.TestCase):
    def test_baseline_envelope_passes(self):
        validate_sync_envelope.validate_envelope(_envelope())

    def test_missing_required_field_fails(self):
        env = _envelope()
        del env["signature"]
        with self.assertRaises(ValueError) as ctx:
            validate_sync_envelope.validate_envelope(env)
        self.assertIn("missing fields", str(ctx.exception))

    def test_protocol_version_must_be_one(self):
        with self.assertRaises(ValueError) as ctx:
            validate_sync_envelope.validate_envelope(
                _envelope(protocol_version=2)
            )
        self.assertIn("protocol_version", str(ctx.exception))

    def test_invalid_envelope_id_uuid_fails(self):
        with self.assertRaises(ValueError) as ctx:
            validate_sync_envelope.validate_envelope(
                _envelope(envelope_id="not-a-uuid")
            )
        self.assertIn("envelope_id", str(ctx.exception))

    def test_envelope_id_must_be_v4_not_v1(self):
        # UUID v1 has a different format — must be rejected.
        v1 = str(uuid.uuid1())
        with self.assertRaises(ValueError) as ctx:
            validate_sync_envelope.validate_envelope(
                _envelope(envelope_id=v1)
            )
        self.assertIn("envelope_id", str(ctx.exception))

    def test_empty_account_pseudonym_fails(self):
        with self.assertRaises(ValueError) as ctx:
            validate_sync_envelope.validate_envelope(
                _envelope(account_pseudonym="")
            )
        self.assertIn("account_pseudonym", str(ctx.exception))

    def test_empty_sender_device_id_fails(self):
        with self.assertRaises(ValueError) as ctx:
            validate_sync_envelope.validate_envelope(
                _envelope(sender_device_id="")
            )
        self.assertIn("sender_device_id", str(ctx.exception))

    def test_empty_recipient_epoch_fails(self):
        with self.assertRaises(ValueError) as ctx:
            validate_sync_envelope.validate_envelope(
                _envelope(recipient_epoch="")
            )
        self.assertIn("recipient_epoch", str(ctx.exception))

    def test_sequence_missing_first_fails(self):
        env = _envelope()
        del env["sequence"]["first"]
        with self.assertRaises(ValueError) as ctx:
            validate_sync_envelope.validate_envelope(env)
        self.assertIn("sequence", str(ctx.exception))

    def test_sequence_extra_field_fails(self):
        env = _envelope()
        env["sequence"]["middle"] = 3
        with self.assertRaises(ValueError) as ctx:
            validate_sync_envelope.validate_envelope(env)
        self.assertIn("sequence", str(ctx.exception))

    def test_sequence_first_negative_fails(self):
        with self.assertRaises(ValueError) as ctx:
            validate_sync_envelope.validate_envelope(
                _envelope(sequence={"first": -1, "last": 0})
            )
        self.assertIn("first", str(ctx.exception))

    def test_sequence_last_less_than_first_fails(self):
        with self.assertRaises(ValueError) as ctx:
            validate_sync_envelope.validate_envelope(
                _envelope(sequence={"first": 5, "last": 3})
            )
        self.assertIn("last", str(ctx.exception))

    def test_sequence_first_equals_last_passes(self):
        validate_sync_envelope.validate_envelope(
            _envelope(sequence={"first": 7, "last": 7})
        )

    def test_ciphertext_length_must_be_int(self):
        with self.assertRaises(ValueError) as ctx:
            validate_sync_envelope.validate_envelope(
                _envelope(ciphertext_length="32")
            )
        self.assertIn("ciphertext_length", str(ctx.exception))

    def test_ciphertext_length_negative_fails(self):
        with self.assertRaises(ValueError) as ctx:
            validate_sync_envelope.validate_envelope(
                _envelope(ciphertext_length=-1, ciphertext="")
            )
        self.assertIn("ciphertext_length", str(ctx.exception))

    def test_invalid_base64_ciphertext_fails(self):
        with self.assertRaises(ValueError) as ctx:
            validate_sync_envelope.validate_envelope(
                _envelope(
                    ciphertext="not!base64??",
                    ciphertext_length=12,
                )
            )
        self.assertIn("ciphertext", str(ctx.exception))

    def test_ciphertext_length_mismatch_fails(self):
        # Declare 100 bytes but provide 32-byte ciphertext.
        with self.assertRaises(ValueError) as ctx:
            validate_sync_envelope.validate_envelope(
                _envelope(ciphertext_length=100)
            )
        self.assertIn("ciphertext_length mismatch", str(ctx.exception))

    def test_invalid_base64_signature_fails(self):
        with self.assertRaises(ValueError) as ctx:
            validate_sync_envelope.validate_envelope(
                _envelope(signature="not!base64??")
            )
        self.assertIn("signature", str(ctx.exception))

    def test_non_object_root_fails(self):
        with self.assertRaises(ValueError) as ctx:
            validate_sync_envelope.validate_envelope([1, 2, 3])  # type: ignore[arg-type]
        self.assertIn("JSON object", str(ctx.exception))


class TestCanonicalBytes(unittest.TestCase):
    def test_canonical_bytes_match_adr_0012_section_3(self):
        env = _envelope()
        cb = validate_sync_envelope.canonical_bytes(env)
        # Re-derive the expected canonical bytes manually per ADR-0012 §3.
        seq = env["sequence"]
        expected_preimage = (
            f"{env['protocol_version']}|"
            f"{env['envelope_id']}|"
            f"{env['account_pseudonym']}|"
            f"{env['sender_device_id']}|"
            f"{env['recipient_epoch']}|"
            f"{seq['first']},{seq['last']}|"
            f"{env['ciphertext_length']}|"
        ).encode("utf-8") + base64.b64decode(env["ciphertext"], validate=True)
        self.assertEqual(cb, expected_preimage)

    def test_canonical_bytes_change_when_ciphertext_changes(self):
        env1 = _envelope()
        env2 = _envelope(ciphertext=base64.b64encode(b"\xff" * 32).decode("ascii"))
        self.assertNotEqual(
            hashlib.sha256(validate_sync_envelope.canonical_bytes(env1)).hexdigest(),
            hashlib.sha256(validate_sync_envelope.canonical_bytes(env2)).hexdigest(),
        )

    def test_canonical_bytes_change_when_sequence_changes(self):
        env1 = _envelope(sequence={"first": 0, "last": 7})
        env2 = _envelope(sequence={"first": 0, "last": 8})
        self.assertNotEqual(
            hashlib.sha256(validate_sync_envelope.canonical_bytes(env1)).hexdigest(),
            hashlib.sha256(validate_sync_envelope.canonical_bytes(env2)).hexdigest(),
        )


class TestCLI(unittest.TestCase):
    def setUp(self):
        self.tmp = pathlib.Path(tempfile.mkdtemp(prefix="sync-env-test-"))

    def _write(self, payload):
        path = self.tmp / "envelope.json"
        path.write_text(json.dumps(payload, indent=2), encoding="utf-8")
        return path

    def _run(self, *args):
        proc = subprocess.run(
            [sys.executable, str(VALIDATOR), *args],
            capture_output=True, text=True,
        )
        return proc

    def test_synthetic_fixture_passes(self):
        path = REPO_ROOT / "evidence" / "sync_envelope" / "synthetic.example.json"
        proc = self._run(str(path))
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn("SYNC_ENVELOPE_OK", proc.stderr)

    def test_print_canonical_bytes_sha256(self):
        env = _envelope()
        path = self._write(env)
        proc = self._run(str(path), "--print-canonical-bytes-sha256")
        self.assertEqual(proc.returncode, 0, proc.stderr)
        actual = proc.stdout.strip()
        expected = hashlib.sha256(
            validate_sync_envelope.canonical_bytes(env)
        ).hexdigest()
        self.assertEqual(actual, expected)

    def test_canonical_bytes_sha256_match_flag_passes(self):
        env = _envelope()
        path = self._write(env)
        expected = hashlib.sha256(
            validate_sync_envelope.canonical_bytes(env)
        ).hexdigest()
        proc = self._run(str(path), "--canonical-bytes-sha256", expected)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn("SYNC_ENVELOPE_SHA256=match", proc.stderr)

    def test_canonical_bytes_sha256_mismatch_flag_fails(self):
        env = _envelope()
        path = self._write(env)
        # Wrong expected digest.
        proc = self._run(
            str(path),
            "--canonical-bytes-sha256",
            "0" * 64,
        )
        self.assertEqual(proc.returncode, 1, proc.stderr)
        self.assertIn("SYNC_ENVELOPE_SHA256_MISMATCH", proc.stderr)

    def test_schema_failure_exits_1(self):
        env = _envelope()
        del env["signature"]
        path = self._write(env)
        proc = self._run(str(path))
        self.assertEqual(proc.returncode, 1, proc.stderr)
        self.assertIn("SYNC_ENVELOPE_SCHEMA=fail", proc.stderr)

    def test_nonexistent_file_exits_1(self):
        proc = self._run(str(self.tmp / "nope.json"))
        self.assertEqual(proc.returncode, 1, proc.stderr)
        self.assertIn("cannot read", proc.stderr)

    def test_invalid_json_exits_1(self):
        path = self.tmp / "bad.json"
        path.write_text("{not valid json", encoding="utf-8")
        proc = self._run(str(path))
        self.assertEqual(proc.returncode, 1, proc.stderr)


if __name__ == "__main__":
    unittest.main()
