"""Unit tests for tool/validate_export_envelope.py.

Verifies ADR-0011 envelope schema + SHA-256 / HMAC-SHA256 verification.
"""
from __future__ import annotations

import hashlib
import hmac
import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path

_SCRIPT_PATH = (
    Path(__file__).resolve().parent.parent / "validate_export_envelope.py"
)
_spec = importlib.util.spec_from_file_location(
    "validate_export_envelope", _SCRIPT_PATH
)
assert _spec is not None and _spec.loader is not None
_module = importlib.util.module_from_spec(_spec)
sys.modules["validate_export_envelope"] = _module
_spec.loader.exec_module(_module)

# Convenience constants.
DEV_SEED = _module.DEV_SIGNING_SEED


def _envelope(
    *,
    events: list | None = None,
    blob_manifest: list | None = None,
    composition_mode: str = "demo",
    passphrase_challenge: str | None = None,
) -> dict:
    return {
        "schema_version": 1,
        "exported_at": "2026-08-23T12:00:00Z",
        "composition_mode": composition_mode,
        "events": events or [],
        "blob_manifest": blob_manifest or [],
        "event_count": len(events or []),
        "blob_count": len(blob_manifest or []),
        "passphrase_challenge": passphrase_challenge,
    }


def _event(event_id: str = "evt-1") -> dict:
    return {
        "event_id": event_id,
        "schema_version": 1,
        "revision": "rev-1",
        "stream_id": "profile-1",
        "occurred_at": "2026-08-23T11:00:00Z",
        "appended_at": "2026-08-23T11:00:01Z",
        "payload": {"type": "appearance_observed", "subject": "primary-user"},
    }


def _blob(ref: str = "blob://vault/1") -> dict:
    return {
        "ref": ref,
        "media_type": "image/jpeg",
        "byte_length": 1024,
        "sha256_hex": hashlib.sha256(b"test").hexdigest(),
    }


class ValidateExportEnvelopeTest(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.root = Path(self._tmp.name)
        self.envelope_path = self.root / "envelope.json"
        # write_file helper
        self._write = self._make_writer(self.envelope_path)

    @staticmethod
    def _make_writer(path: Path):
        def _w(envelope: dict) -> bytes:
            data = json.dumps(envelope, separators=(",", ":")).encode("utf-8")
            path.write_bytes(data)
            return data
        return _w

    def _run(self, *extra: str) -> int:
        return _module.main([str(self.envelope_path), *extra])

    # ------------------------- schema -------------------------

    def test_minimal_envelope_passes(self) -> None:
        self._write(_envelope())
        rc = self._run()
        self.assertEqual(rc, 0)

    def test_envelope_with_events_and_blobs_passes(self) -> None:
        env = _envelope(events=[_event()], blob_manifest=[_blob()])
        self._write(env)
        rc = self._run()
        self.assertEqual(rc, 0)

    def test_missing_field_fails(self) -> None:
        env = _envelope()
        del env["schema_version"]
        self._write(env)
        rc = self._run()
        self.assertEqual(rc, 1)

    def test_wrong_schema_version_fails(self) -> None:
        env = _envelope()
        env["schema_version"] = 2
        self._write(env)
        rc = self._run()
        self.assertEqual(rc, 1)

    def test_unknown_composition_mode_fails(self) -> None:
        env = _envelope(composition_mode="experiment")
        self._write(env)
        rc = self._run()
        self.assertEqual(rc, 1)

    def test_event_count_mismatch_fails(self) -> None:
        env = _envelope(events=[_event()])
        env["event_count"] = 0
        self._write(env)
        rc = self._run()
        self.assertEqual(rc, 1)

    def test_blob_count_mismatch_fails(self) -> None:
        env = _envelope(blob_manifest=[_blob()])
        env["blob_count"] = 0
        self._write(env)
        rc = self._run()
        self.assertEqual(rc, 1)

    def test_passphrase_challenge_must_be_hex_or_null(self) -> None:
        env = _envelope(passphrase_challenge="not-a-hex")
        self._write(env)
        rc = self._run()
        self.assertEqual(rc, 1)

    def test_event_missing_payload_fails(self) -> None:
        e = _event()
        del e["payload"]
        env = _envelope(events=[e])
        self._write(env)
        rc = self._run()
        self.assertEqual(rc, 1)

    def test_blob_missing_sha256_fails(self) -> None:
        b = _blob()
        del b["sha256_hex"]
        env = _envelope(blob_manifest=[b])
        self._write(env)
        rc = self._run()
        self.assertEqual(rc, 1)

    def test_invalid_exported_at_fails(self) -> None:
        env = _envelope()
        env["exported_at"] = "yesterday"
        self._write(env)
        rc = self._run()
        self.assertEqual(rc, 1)

    # ------------------------- SHA-256 -------------------------

    def test_sha256_match_passes(self) -> None:
        data = self._write(_envelope())
        expected = hashlib.sha256(data).hexdigest()
        rc = self._run("--sha256", expected)
        self.assertEqual(rc, 0)

    def test_sha256_mismatch_fails(self) -> None:
        self._write(_envelope())
        rc = self._run("--sha256", "0" * 64)
        self.assertEqual(rc, 1)

    # ------------------------- signature -------------------------

    def test_signature_with_dev_seed_passes(self) -> None:
        data = self._write(_envelope())
        expected = hmac.new(
            DEV_SEED.encode("utf-8"), data, hashlib.sha256
        ).hexdigest()
        rc = self._run("--signature", expected, "--no-passphrase")
        self.assertEqual(rc, 0)

    def test_signature_with_passphrase_passes(self) -> None:
        passphrase = "hunter2-correct-horse-battery-staple"
        env = _envelope(
            passphrase_challenge=hashlib.sha256(
                passphrase.encode("utf-8")
            ).hexdigest(),
        )
        data = self._write(env)
        expected = hmac.new(
            passphrase.encode("utf-8"), data, hashlib.sha256
        ).hexdigest()
        rc = self._run("--signature", expected, "--passphrase", passphrase)
        self.assertEqual(rc, 0)

    def test_signature_with_wrong_passphrase_fails(self) -> None:
        data = self._write(_envelope())
        # Compute signature with right passphrase but verify with wrong one.
        right_passphrase = "right"
        wrong_passphrase = "wrong"
        expected = hmac.new(
            right_passphrase.encode("utf-8"), data, hashlib.sha256
        ).hexdigest()
        rc = self._run(
            "--signature", expected, "--passphrase", wrong_passphrase
        )
        self.assertEqual(rc, 1)

    def test_passphrase_and_no_passphrase_mutually_exclusive(self) -> None:
        self._write(_envelope())
        rc = self._run(
            "--signature", "0" * 64,
            "--passphrase", "foo",
            "--no-passphrase",
        )
        self.assertEqual(rc, 2)

    # ------------------------- file errors -------------------------

    def test_missing_file_returns_2(self) -> None:
        rc = _module.main([str(self.root / "nope.json")])
        self.assertEqual(rc, 2)

    def test_invalid_json_returns_2(self) -> None:
        self.envelope_path.write_text("not-json", encoding="utf-8")
        rc = self._run()
        self.assertEqual(rc, 2)


if __name__ == "__main__":
    unittest.main(verbosity=2)
