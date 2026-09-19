import importlib.util
import unittest
from pathlib import Path

MODULE_PATH = Path(__file__).with_name("validate_redmi_evidence.py")
SPEC = importlib.util.spec_from_file_location("redmi_evidence", MODULE_PATH)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader
SPEC.loader.exec_module(MODULE)

SCENARIOS = (
    "install_launch",
    "offline_loop",
    "process_death",
    "device_reboot",
    "lock_unlock",
    "permission_denied",
    "battery_restriction",
    "export_delete",
    "recovery_drill",
)


def complete_evidence(result="pass"):
    failure = "none" if result == "pass" else "not_run"
    passed = 1 if result == "pass" else 0
    return {
        "schemaVersion": 2,
        "recordKind": "real_device",
        "targetClass": "redmi_turbo",
        "buildProfile": "debug",
        "candidateCommit": "a" * 40,
        "apkSha256": "b" * 64,
        "startedAtUtc": "2026-09-19T12:00:00Z",
        "completedAtUtc": "2026-09-19T12:30:00Z",
        "overall": result,
        "scenarios": [
            {
                "id": scenario,
                "result": result,
                "checksPassed": passed,
                "checksTotal": 1,
                "failureCode": failure,
            }
            for scenario in SCENARIOS
        ],
    }


class ValidateRedmiEvidenceTests(unittest.TestCase):
    def test_complete_pass_is_device_verified(self):
        self.assertTrue(MODULE.validate(complete_evidence(), require_ready=True))

    def test_blocked_record_is_valid_but_not_ready(self):
        evidence = complete_evidence("blocked")
        self.assertFalse(MODULE.validate(evidence))
        with self.assertRaisesRegex(ValueError, "not all ready"):
            MODULE.validate(evidence, require_ready=True)

    def test_old_rdm_scenario_set_is_rejected(self):
        evidence = complete_evidence()
        evidence["scenarios"][0]["id"] = "RDM-001"
        with self.assertRaisesRegex(ValueError, "scenario IDs"):
            MODULE.validate(evidence)

    def test_candidate_and_apk_digest_are_bound(self):
        for field in ("candidateCommit", "apkSha256"):
            evidence = complete_evidence()
            evidence[field] = "invalid"
            with self.assertRaisesRegex(ValueError, field):
                MODULE.validate(evidence)


if __name__ == "__main__":
    unittest.main()
