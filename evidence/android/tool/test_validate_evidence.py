import copy
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

MODULE_PATH = Path(__file__).with_name("validate_evidence.py")
SPEC = importlib.util.spec_from_file_location("android_validate_evidence", MODULE_PATH)
validate_evidence = importlib.util.module_from_spec(SPEC)
assert SPEC.loader
SPEC.loader.exec_module(validate_evidence)

COMMIT = "a" * 40
APK_SHA = "b" * 64
SCENARIOS = sorted(validate_evidence.SCENARIOS)


def valid_record():
    return {
        "schemaVersion": 2,
        "recordKind": "real_device",
        "targetClass": "redmi_turbo",
        "buildProfile": "debug",
        "candidateCommit": COMMIT,
        "apkSha256": APK_SHA,
        "startedAtUtc": "2026-09-19T00:00:00Z",
        "completedAtUtc": "2026-09-19T00:30:00Z",
        "overall": "pass",
        "scenarios": [
            {
                "id": item,
                "result": "pass",
                "checksPassed": 1,
                "checksTotal": 1,
                "failureCode": "none",
            }
            for item in SCENARIOS
        ],
    }


class AndroidEvidenceTests(unittest.TestCase):
    def assert_valid(self, value):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "record.json"
            path.write_text(json.dumps(value), encoding="utf-8")
            validate_evidence.main(str(path))

    def test_real_complete_record_is_valid(self):
        self.assertTrue(validate_evidence.validate(valid_record()))
        self.assert_valid(valid_record())

    def test_synthetic_pass_is_rejected(self):
        record = valid_record()
        record["recordKind"] = "synthetic"
        with self.assertRaisesRegex(ValueError, "synthetic pass"):
            validate_evidence.validate(record)

    def test_overall_pass_requires_all_scenarios(self):
        record = valid_record()
        record["scenarios"][0] = {
            "id": SCENARIOS[0],
            "result": "blocked",
            "checksPassed": 0,
            "checksTotal": 1,
            "failureCode": "not_run",
        }
        with self.assertRaisesRegex(ValueError, "overall pass"):
            validate_evidence.validate(record)

    def test_blocked_record_is_valid_but_not_ready(self):
        record = valid_record()
        record["recordKind"] = "synthetic"
        record["overall"] = "blocked"
        for scenario in record["scenarios"]:
            scenario.update(
                result="blocked",
                checksPassed=0,
                failureCode="not_run",
            )
        self.assertFalse(validate_evidence.validate(record))

    def test_apk_digest_and_candidate_commit_are_required(self):
        for field, message in (
            ("candidateCommit", "candidateCommit"),
            ("apkSha256", "apkSha256"),
        ):
            record = valid_record()
            record[field] = "invalid"
            with self.assertRaisesRegex(ValueError, message):
                validate_evidence.validate(record)

    def test_failed_scenario_requires_overall_failure(self):
        record = valid_record()
        record["scenarios"][0].update(
            result="fail",
            checksPassed=0,
            failureCode="backup_tamper_accepted",
        )
        record["overall"] = "blocked"
        with self.assertRaisesRegex(ValueError, "overall blocked"):
            validate_evidence.validate(record)
        record["overall"] = "fail"
        self.assertFalse(validate_evidence.validate(record))

    def test_completed_time_cannot_precede_start(self):
        record = valid_record()
        record["completedAtUtc"] = "2026-09-18T23:59:00Z"
        with self.assertRaisesRegex(ValueError, "completedAtUtc"):
            validate_evidence.validate(record)


if __name__ == "__main__":
    unittest.main()
