from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from audit_recovery import audit_recovery_contract, extract_protocol_error_codes


PROTOCOL = """\
| Error code | condition |
|---|---|
| `RECOVERY_AUTH_FAILED` | auth |
| `RECOVERY_PACKAGE_REVOKED` | revoked |
"""


class RecoveryContractAuditTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.protocol = self.root / "protocol.md"
        self.fixtures = self.root / "fixtures"
        self.fixtures.mkdir()
        self.protocol.write_text(PROTOCOL, encoding="utf-8")
        self._write_schema()

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def _write_schema(self, name: str = "fixture.schema.json", schema_id: str = "urn:test:1") -> None:
        (self.fixtures / name).write_text(
            json.dumps({"$id": schema_id}), encoding="utf-8"
        )

    def _write_fixture(
        self,
        name: str = "case.json",
        *,
        case_id: str = "RC-001",
        code: str | None = "RECOVERY_AUTH_FAILED",
        states: list[str] | None = None,
        terminal: str = "failed",
    ) -> None:
        expect: dict[str, object] = {
            "terminal_state": terminal,
            "ordered_states": states or ["intake", "envelope_validated", "failed"],
        }
        if code is not None:
            expect["error_code"] = code
        (self.fixtures / name).write_text(
            json.dumps(
                {
                    "$schema": "fixture.schema.json",
                    "case_id": case_id,
                    "expect": expect,
                }
            ),
            encoding="utf-8",
        )

    def test_extracts_codes_from_markdown_table(self) -> None:
        self.assertEqual(
            extract_protocol_error_codes(PROTOCOL),
            {"RECOVERY_AUTH_FAILED", "RECOVERY_PACKAGE_REVOKED"},
        )

    def test_accepts_consistent_contract(self) -> None:
        self._write_fixture()
        self.assertEqual(audit_recovery_contract(self.protocol, self.fixtures), [])

    def test_accepts_material_rotation_cycle(self) -> None:
        self._write_fixture(
            code=None,
            states=[
                "not_configured",
                "generated_unverified",
                "recovery_ready",
                "rotation_required",
                "recovery_ready",
                "revoked",
            ],
            terminal="revoked",
        )
        self.assertEqual(audit_recovery_contract(self.protocol, self.fixtures), [])

    def test_rejects_error_code_absent_from_protocol(self) -> None:
        self._write_fixture(code="RECOVERY_UNKNOWN")
        messages = self._messages()
        self.assertTrue(any("absent from protocol" in item for item in messages))

    def test_rejects_regression_and_terminal_mismatch(self) -> None:
        self._write_fixture(
            states=["intake", "account_verified", "envelope_validated"],
            terminal="failed",
        )
        messages = self._messages()
        self.assertTrue(any("regresses" in item for item in messages))
        self.assertTrue(any("terminal_state" in item for item in messages))

    def test_rejects_nonterminal_failed_and_duplicate_state(self) -> None:
        self._write_fixture(states=["intake", "failed", "failed"])
        messages = self._messages()
        self.assertTrue(any("failed must be terminal" in item for item in messages))
        self.assertTrue(any("repeats" in item for item in messages))

    def test_rejects_duplicate_case_and_schema_ids(self) -> None:
        self._write_fixture(name="one.json")
        self._write_fixture(name="two.json")
        self._write_schema(name="other.schema.json", schema_id="urn:test:1")
        messages = self._messages()
        self.assertTrue(any("duplicate case_id" in item for item in messages))
        self.assertTrue(any("duplicate schema $id" in item for item in messages))

    def test_rejects_unknown_local_schema_reference(self) -> None:
        self._write_fixture()
        path = self.fixtures / "case.json"
        fixture = json.loads(path.read_text(encoding="utf-8"))
        fixture["$schema"] = "missing.schema.json"
        path.write_text(json.dumps(fixture), encoding="utf-8")
        self.assertTrue(any("$schema" in item for item in self._messages()))

    def _messages(self) -> list[str]:
        return [
            issue.message
            for issue in audit_recovery_contract(self.protocol, self.fixtures)
        ]


if __name__ == "__main__":
    unittest.main()
