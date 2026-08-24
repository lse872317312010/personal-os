import json
import importlib.util
import tempfile
import unittest
from pathlib import Path

MODULE_PATH = Path(__file__).with_name("validate_evidence.py")
SPEC = importlib.util.spec_from_file_location("android_validate_evidence", MODULE_PATH)
validate_evidence = importlib.util.module_from_spec(SPEC)
assert SPEC.loader
SPEC.loader.exec_module(validate_evidence)


COMMIT = "a" * 40
SCENARIOS = sorted(validate_evidence.SCENARIOS)


def valid_record():
    return {
        "schemaVersion": 1,
        "recordKind": "real_device",
        "targetClass": "redmi_turbo",
        "buildProfile": "debug",
        "candidateCommit": COMMIT,
        "startedAtUtc": "2026-08-24T00:00:00Z",
        "completedAtUtc": "2026-08-24T00:09:00Z",
        "overall": "pass",
        "scenarios": [
            {"id": item, "result": "pass", "checksPassed": 1,
             "checksTotal": 1, "failureCode": "none"}
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
        self.assert_valid(valid_record())

    def test_synthetic_pass_is_rejected(self):
        record = valid_record()
        record["recordKind"] = "synthetic"
        with self.assertRaises(ValueError):
            self.assert_valid(record)

    def test_overall_pass_requires_all_scenarios(self):
        record = valid_record()
        record["scenarios"][0] = {
            "id": SCENARIOS[0], "result": "blocked", "checksPassed": 0,
            "checksTotal": 1, "failureCode": "not_run"
        }
        with self.assertRaises(ValueError):
            self.assert_valid(record)

    def test_commit_is_required(self):
        record = valid_record()
        del record["candidateCommit"]
        with self.assertRaises((KeyError, ValueError)):
            self.assert_valid(record)

    def test_completed_time_cannot_precede_start(self):
        record = valid_record()
        record["completedAtUtc"] = "2026-08-23T23:59:00Z"
        with self.assertRaises(ValueError):
            self.assert_valid(record)


if __name__ == "__main__":
    unittest.main()
