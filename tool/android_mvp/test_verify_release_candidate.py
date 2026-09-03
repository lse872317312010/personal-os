import hashlib
import json
import tempfile
import unittest
from pathlib import Path

from verify_release_candidate import verify


class VerifyReleaseCandidateTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.apk = self.root / "personal-os-latest-debug.apk"
        self.checksum = self.root / "personal-os-latest-debug.apk.sha256"
        self.provenance = self.root / "personal-os-latest-debug.provenance.json"
        self.apk.write_bytes(b"verified apk")
        self.digest = hashlib.sha256(b"verified apk").hexdigest()
        # The workflow sidecar retains this path even when GitHub flattens the
        # downloaded artifact. Verification must rely on the digest, not cwd.
        self.checksum.write_text(
            f"{self.digest}  release/personal-os-latest-debug.apk\n",
            encoding="utf-8",
        )
        self.provenance.write_text(
            json.dumps({
                "schema_version": 1,
                "github_sha": "a" * 40,
                "run_id": "123",
                "app_version": "0.1.0-dev.1+123",
                "apk_sha256": self.digest,
            }),
            encoding="utf-8",
        )

    def tearDown(self):
        self.temporary.cleanup()

    def test_accepts_flattened_release_download(self):
        result = verify(self.apk, self.checksum, self.provenance)
        self.assertEqual(self.digest, result["apk_sha256"])
        self.assertEqual("a" * 40, result["commit_sha"])

    def test_rejects_tampered_apk(self):
        self.apk.write_bytes(b"tampered")
        with self.assertRaisesRegex(ValueError, "checksum sidecar"):
            verify(self.apk, self.checksum, self.provenance)

    def test_rejects_provenance_for_another_apk(self):
        data = json.loads(self.provenance.read_text(encoding="utf-8"))
        data["apk_sha256"] = "b" * 64
        self.provenance.write_text(json.dumps(data), encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "provenance"):
            verify(self.apk, self.checksum, self.provenance)


if __name__ == "__main__":
    unittest.main()
