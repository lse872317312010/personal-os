import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

MODULE_PATH = Path(__file__).resolve().parents[1] / "audit.py"
SPEC = importlib.util.spec_from_file_location("mvp_audit", MODULE_PATH)
audit_module = importlib.util.module_from_spec(SPEC)
assert SPEC.loader
SPEC.loader.exec_module(audit_module)

COMMIT = "a" * 40
DIGEST = "b" * 64


def check(item_id):
    return {"id": item_id, "status": "pass", "evidence_ref": f"review:{item_id}", "commit": COMMIT}


def valid_ledger():
    common = {"status": "pass", "commit": COMMIT, "checked_at": "2026-08-20T12:00:00Z", "checked_by": "owner"}
    return {
        "schema_version": 2,
        "kind": "real",
        "candidate_commit": COMMIT,
        "gates": {
            "static": {**common, "checks": [check(x) for x in sorted({"contract_audit", "dependency_audit"})]},
            "flutter_test": {**common, "checks": [check(x) for x in sorted(audit_module.FLUTTER_CHECKS)]},
            "apk": {**common, "checks": [check("release_apk_build")], "artifact": {"sha256": DIGEST, "bytes": 42}},
            "redmi_device": {**common, "android_major": 15, "apk_sha256": DIGEST, "scenarios": [check(x) for x in sorted(audit_module.REDMI_SCENARIOS)]},
            "dogfood": {
                **common,
                "cycle_id": "cycle-001",
                "cycle_start": "2026-08-01",
                "cycle_end": "2026-08-20",
                "steps": [check(x) for x in sorted(audit_module.DOGFOOD_STEPS)],
                "continuity_checks": [
                    check(x) for x in sorted(audit_module.DOGFOOD_CONTINUITY)
                ],
                "rounds": [
                    {
                        "round": 1,
                        "strategy_ref": "strategy:v1@3",
                        "harness_ref": "harness:first",
                        "execution_count": 3,
                        "outcome_count": 2,
                    },
                    {
                        "round": 2,
                        "strategy_ref": "strategy:v2@3",
                        "parent_strategy_ref": "strategy:v1@3",
                        "harness_ref": "harness:second",
                        "execution_count": 2,
                        "outcome_count": 2,
                    },
                ],
                "safety_checks": [check(x) for x in sorted(audit_module.DOGFOOD_SAFETY)],
            },
        },
    }


class AuditTests(unittest.TestCase):
    def test_complete_real_ledger_is_dogfood_ready(self):
        passed, errors = audit_module.audit(valid_ledger())
        self.assertEqual([True] * 5, passed)
        self.assertEqual([], errors)
        self.assertEqual("DOGFOOD_READY", audit_module.conclusion(passed))

    def test_synthetic_can_never_pass(self):
        ledger = valid_ledger()
        ledger["kind"] = "synthetic"
        passed, errors = audit_module.audit(ledger)
        self.assertEqual([False] * 5, passed)
        self.assertTrue(errors)

    def test_later_gate_cannot_skip_flutter_gate(self):
        ledger = valid_ledger()
        ledger["gates"]["flutter_test"]["status"] = "blocked"
        passed, _ = audit_module.audit(ledger)
        self.assertEqual([True, False, False, False, False], passed)
        self.assertEqual("STATIC_VERIFIED", audit_module.conclusion(passed))

    def test_incomplete_redmi_scenarios_rejected(self):
        ledger = valid_ledger()
        ledger["gates"]["redmi_device"]["scenarios"].pop()
        passed, errors = audit_module.audit(ledger)
        self.assertFalse(passed[3])
        self.assertTrue(any("redmi_device" in error for error in errors))

    def test_dogfood_requires_feedback_revision(self):
        ledger = valid_ledger()
        ledger["gates"]["dogfood"]["steps"] = [x for x in ledger["gates"]["dogfood"]["steps"] if x["id"] != "revision"]
        passed, _ = audit_module.audit(ledger)
        self.assertFalse(passed[4])

    def test_dogfood_requires_two_distinct_harnesses(self):
        ledger = valid_ledger()
        ledger["gates"]["dogfood"]["rounds"][1]["harness_ref"] = "harness:first"
        passed, errors = audit_module.audit(ledger)
        self.assertFalse(passed[4])
        self.assertTrue(any("dogfood" in error for error in errors))

    def test_dogfood_requires_v2_parent_lineage(self):
        ledger = valid_ledger()
        ledger["gates"]["dogfood"]["rounds"][1]["parent_strategy_ref"] = "strategy:other@1"
        passed, errors = audit_module.audit(ledger)
        self.assertFalse(passed[4])
        self.assertTrue(any("dogfood" in error for error in errors))

    def test_dogfood_requires_explicit_continuity_checks(self):
        ledger = valid_ledger()
        ledger["gates"]["dogfood"]["continuity_checks"].pop()
        passed, errors = audit_module.audit(ledger)
        self.assertFalse(passed[4])
        self.assertTrue(any("dogfood" in error for error in errors))

    def test_redmi_apk_must_match_built_artifact(self):
        ledger = valid_ledger()
        ledger["gates"]["redmi_device"]["apk_sha256"] = "c" * 64
        passed, errors = audit_module.audit(ledger)
        self.assertFalse(passed[3])
        self.assertTrue(any("redmi_device" in error for error in errors))

    def test_pass_without_evidence_reference_is_rejected(self):
        ledger = valid_ledger()
        del ledger["gates"]["flutter_test"]["checks"][0]["evidence_ref"]
        passed, errors = audit_module.audit(ledger)
        self.assertFalse(passed[1])
        self.assertTrue(any("flutter_test" in error for error in errors))

    def test_short_demo_is_not_dogfood_cycle(self):
        ledger = valid_ledger()
        ledger["gates"]["dogfood"]["cycle_start"] = "2026-08-19"
        passed, errors = audit_module.audit(ledger)
        self.assertFalse(passed[4])
        self.assertTrue(any("dogfood" in error for error in errors))

    def test_pass_check_must_bind_candidate_commit(self):
        ledger = valid_ledger()
        ledger["gates"]["static"]["checks"][0]["commit"] = "b" * 40
        passed, errors = audit_module.audit(ledger)
        self.assertFalse(passed[0])
        self.assertTrue(any("commit" in error for error in errors))

    def test_rejects_forbidden_sensitive_field_anywhere(self):
        ledger = valid_ledger()
        ledger["gates"]["redmi_device"]["device_serial"] = "do-not-store"
        passed, errors = audit_module.audit(ledger)
        self.assertEqual([False] * 5, passed)
        self.assertTrue(any("forbidden sensitive field" in error for error in errors))

    def test_root_schema_error_is_fail_closed(self):
        ledger = valid_ledger()
        ledger["schema_version"] = 999
        passed, errors = audit_module.audit(ledger)
        self.assertEqual([False] * 5, passed)
        self.assertTrue(any("schema_version" in error for error in errors))

    def test_cli_target_exit_codes(self):
        ledger = valid_ledger()
        ledger["gates"]["dogfood"]["status"] = "not_run"
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "status.json"
            path.write_text(json.dumps(ledger), encoding="utf-8")
            self.assertEqual(0, audit_module.main(["--status", str(path), "--target", "redmi_device"]))
            self.assertEqual(1, audit_module.main(["--status", str(path), "--target", "dogfood"]))


if __name__ == "__main__":
    unittest.main()
