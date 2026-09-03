import importlib.util
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).with_name("validate_redmi_evidence.py")
SPEC = importlib.util.spec_from_file_location("redmi_evidence", MODULE_PATH)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader
SPEC.loader.exec_module(MODULE)


def complete_evidence(result="PASS"):
    return {
        "schema_version": 1,
        "commit_sha": "a" * 40,
        "apk_sha256": "b" * 64,
        "device": {
            "model": "Redmi Turbo",
            "android_version": "15",
            "build_number": "OS2.0",
        },
        "toolchain": {
            "adb_version": "Android Debug Bridge 1.0.41",
            "flutter_version": "3.47.0",
            "runner": "owner workstation",
        },
        "scenarios": [
            {
                "id": f"RDM-{number:03d}",
                "result": result,
                "observed_at_utc": "2026-09-03T12:00:00Z",
                "notes": "Observed expected stable behavior.",
                "artifacts": [],
            }
            for number in range(1, 10)
        ],
    }


class ValidateRedmiEvidenceTests(unittest.TestCase):
    def test_complete_pass_is_device_verified(self):
        self.assertTrue(MODULE.validate(complete_evidence(), require_ready=True))

    def test_blocked_record_is_valid_but_not_ready(self):
        evidence = complete_evidence()
        evidence["scenarios"][0]["result"] = "BLOCKED"
        self.assertFalse(MODULE.validate(evidence))
        with self.assertRaisesRegex(ValueError, "not all ready"):
            MODULE.validate(evidence, require_ready=True)

    def test_missing_scenario_is_rejected(self):
        evidence = complete_evidence()
        evidence["scenarios"].pop()
        with self.assertRaisesRegex(ValueError, "exactly"):
            MODULE.validate(evidence)

    def test_placeholder_and_non_utc_time_are_rejected(self):
        placeholder = complete_evidence()
        placeholder["device"]["model"] = "<model>"
        with self.assertRaisesRegex(ValueError, "device.model"):
            MODULE.validate(placeholder)
        local_time = complete_evidence()
        local_time["scenarios"][0]["observed_at_utc"] = "2026-09-03T12:00:00+08:00"
        with self.assertRaisesRegex(ValueError, "UTC"):
            MODULE.validate(local_time)

    def test_na_is_limited_to_permission_scenario(self):
        evidence = complete_evidence()
        evidence["scenarios"][0]["result"] = "N/A"
        with self.assertRaisesRegex(ValueError, "only allowed"):
            MODULE.validate(evidence)
        permitted = complete_evidence()
        permitted["scenarios"][4]["result"] = "N/A"
        self.assertTrue(MODULE.validate(permitted, require_ready=True))


if __name__ == "__main__":
    unittest.main()
