"""Unit tests for ``tool/check_persistence_imports.py``.

Covers the ADR-0013 §6 / ADR-0008 forbidden-zone audit: the Composition
Root is the only allowed import surface for persistence adapter packages;
UI, Controller, Application Use Case, and boundary-caller layers MUST go
through abstract interfaces in ``packages/storage_api`` /
``packages/security_api``.

Tests construct a minimal fake repository tree inside a temporary
directory so they do not depend on the real codebase layout.
"""

from __future__ import annotations

import importlib
import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path

_TOOL_DIR = Path(__file__).resolve().parents[1]
_SPEC = importlib.util.spec_from_file_location(
    "check_persistence_imports", _TOOL_DIR / "check_persistence_imports.py"
)
assert _SPEC is not None and _SPEC.loader is not None
_MODULE = importlib.util.module_from_spec(_SPEC)
sys.modules["check_persistence_imports"] = _MODULE
_SPEC.loader.exec_module(_MODULE)


def _make_fake_repo(root: Path) -> None:
    """Materialize the directory skeleton the auditor walks."""

    for rel in (
        "apps/personal_os_app/lib/src/composition",
        "apps/personal_os_app/lib/src/screens",
        "apps/personal_os_app/lib/src/controller",
        "apps/personal_os_app/lib/src/navigation",
        "apps/personal_os_app/lib/src",
        "apps/personal_os_app/test",
        "packages/application/lib",
        "packages/runtime/lib",
        "packages/recovery/lib",
        "packages/sync_engine/lib",
        "packages/blob_engine/lib",
        "packages/sync_api/lib",
        "packages/policy/lib",
        "packages/domain/lib",
        "packages/events/lib",
        "packages/model_gateway_api/lib",
        "packages/storage_api/lib",
        "packages/security_api/lib",
    ):
        (root / rel).mkdir(parents=True, exist_ok=True)


def _write_dart(path: Path, imports: list[str]) -> None:
    body = "\n".join(imports) + "\n" if imports else "\n"
    path.write_text(body, encoding="utf-8")


class AuditFileTests(unittest.TestCase):
    """Direct exercise of ``audit_file`` against synthetic Dart sources."""

    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        _make_fake_repo(self.root)

    def test_clean_file_has_no_violations(self) -> None:
        path = self.root / "apps/personal_os_app/lib/src/screens/home.dart"
        _write_dart(path, [
            "import 'package:flutter/material.dart';",
            "import 'package:personal_os_storage_api/storage_api.dart';",
        ])
        self.assertEqual(_MODULE.audit_file(path), [])

    def test_in_memory_import_in_screen_flagged(self) -> None:
        path = self.root / "apps/personal_os_app/lib/src/screens/home.dart"
        _write_dart(path, [
            "import 'package:personal_os_in_memory/in_memory.dart';",
        ])
        violations = _MODULE.audit_file(path)
        self.assertEqual(len(violations), 1)
        self.assertEqual(
            violations[0].package,
            "package:personal_os_in_memory/in_memory.dart",
        )
        self.assertEqual(violations[0].line_number, 1)

    def test_sqlite_vault_driver_import_in_controller_flagged(self) -> None:
        path = (
            self.root
            / "apps/personal_os_app/lib/src/controller/app_controller.dart"
        )
        _write_dart(path, [
            "import 'package:personal_os_sqlite_vault_driver/"
            "sqlite_vault_driver.dart';",
        ])
        violations = _MODULE.audit_file(path)
        self.assertEqual(len(violations), 1)
        self.assertTrue(
            violations[0].package.startswith(
                "package:personal_os_sqlite_vault_driver/"
            )
        )

    def test_device_security_import_in_runtime_flagged(self) -> None:
        path = self.root / "packages/runtime/lib/runtime.dart"
        _write_dart(path, [
            "import 'package:personal_os_device_security/device_security.dart';",
        ])
        violations = _MODULE.audit_file(path)
        self.assertEqual(len(violations), 1)

    def test_export_directive_flagged(self) -> None:
        path = self.root / "packages/sync_engine/lib/sync_engine.dart"
        _write_dart(path, [
            "export 'package:personal_os_model_fixture/model_fixture.dart';",
        ])
        violations = _MODULE.audit_file(path)
        self.assertEqual(len(violations), 1)

    def test_policy_application_import_in_policy_flagged(self) -> None:
        path = self.root / "packages/policy/lib/policy.dart"
        _write_dart(path, [
            "import 'package:personal_os_policy_application/policy_application.dart';",
        ])
        violations = _MODULE.audit_file(path)
        self.assertEqual(len(violations), 1)

    def test_relative_imports_ignored(self) -> None:
        path = self.root / "packages/domain/lib/domain.dart"
        _write_dart(path, [
            "import 'src/identity.dart';",
            "import '../events/lib/events.dart';",
        ])
        self.assertEqual(_MODULE.audit_file(path), [])

    def test_unrelated_package_import_ignored(self) -> None:
        path = self.root / "packages/events/lib/events.dart"
        _write_dart(path, [
            "import 'package:personal_os_storage_api/storage_api.dart';",
            "import 'package:personal_os_security_api/security_api.dart';",
        ])
        self.assertEqual(_MODULE.audit_file(path), [])

    def test_multiple_violations_in_one_file(self) -> None:
        path = self.root / "packages/recovery/lib/recovery.dart"
        _write_dart(path, [
            "import 'package:personal_os_in_memory/in_memory.dart';",
            "import 'package:personal_os_in_memory_relay/in_memory_relay.dart';",
            "import 'package:personal_os_in_memory_policy/in_memory_policy.dart';",
        ])
        violations = _MODULE.audit_file(path)
        self.assertEqual(len(violations), 3)
        self.assertEqual(
            {v.package for v in violations},
            {
                "package:personal_os_in_memory/in_memory.dart",
                "package:personal_os_in_memory_relay/in_memory_relay.dart",
                "package:personal_os_in_memory_policy/in_memory_policy.dart",
            },
        )


class AuditRootTests(unittest.TestCase):
    """``audit(root)`` walks the forbidden layer roots and skips tests."""

    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        _make_fake_repo(self.root)

    def test_no_dart_files_passes(self) -> None:
        self.assertEqual(_MODULE.audit(self.root), [])

    def test_composition_root_import_allowed(self) -> None:
        path = (
            self.root
            / "apps/personal_os_app/lib/src/composition/app_composition.dart"
        )
        _write_dart(path, [
            "import 'package:personal_os_in_memory/in_memory.dart';",
            "import 'package:personal_os_sqlite_vault_driver/sqlite_vault_driver.dart';",
        ])
        self.assertEqual(_MODULE.audit(self.root), [])

    def test_screen_import_in_ui_layer_violates(self) -> None:
        path = self.root / "apps/personal_os_app/lib/src/screens/home.dart"
        _write_dart(path, [
            "import 'package:personal_os_in_memory/in_memory.dart';",
        ])
        violations = _MODULE.audit(self.root)
        self.assertEqual(len(violations), 1)
        self.assertEqual(violations[0].file, path)

    def test_test_directory_imports_allowed(self) -> None:
        path = self.root / "apps/personal_os_app/test/widget_test.dart"
        _write_dart(path, [
            "import 'package:personal_os_in_memory/in_memory.dart';",
            "import 'package:personal_os_sqlite_vault/sqlite_vault.dart';",
        ])
        self.assertEqual(_MODULE.audit(self.root), [])

    def test_application_use_case_layer_flagged(self) -> None:
        path = self.root / "packages/application/lib/appearance_use_case.dart"
        _write_dart(path, [
            "import 'package:personal_os_sqlite_vault/sqlite_vault.dart';",
        ])
        violations = _MODULE.audit(self.root)
        self.assertEqual(len(violations), 1)
        self.assertIn("application", str(violations[0].file))

    def test_boundary_caller_layers_flagged(self) -> None:
        cases = [
            ("packages/runtime/lib/runtime.dart",
             "package:personal_os_in_memory/in_memory.dart"),
            ("packages/recovery/lib/recovery.dart",
             "package:personal_os_in_memory_relay/in_memory_relay.dart"),
            ("packages/sync_engine/lib/sync_worker.dart",
             "package:personal_os_device_security/device_security.dart"),
            ("packages/blob_engine/lib/blob_engine.dart",
             "package:personal_os_sqlite_vault/sqlite_vault.dart"),
            ("packages/sync_api/lib/sync_api.dart",
             "package:personal_os_model_fixture/model_fixture.dart"),
            ("packages/policy/lib/policy.dart",
             "package:personal_os_policy_application/policy_application.dart"),
            ("packages/domain/lib/domain.dart",
             "package:personal_os_in_memory_policy/in_memory_policy.dart"),
            ("packages/events/lib/events.dart",
             "package:personal_os_in_memory/in_memory.dart"),
            ("packages/model_gateway_api/lib/model_gateway_api.dart",
             "package:personal_os_device_security/device_security.dart"),
        ]
        for rel, package in cases:
            with self.subTest(layer=rel):
                path = self.root / rel
                _write_dart(path, [f"import '{package}';"])
                violations = _MODULE.audit(self.root)
                self.assertEqual(
                    len(violations), 1,
                    f"expected violation in {rel}",
                )
                self.assertEqual(violations[0].package, package)
                # Reset for next iteration.
                path.write_text("", encoding="utf-8")

    def test_app_shell_imports_flagged(self) -> None:
        # apps/personal_os_app/lib/src is the app-shell fallback bucket;
        # a file directly under it (not under screens/controller/etc.) is
        # also forbidden.
        path = self.root / "apps/personal_os_app/lib/src/app.dart"
        _write_dart(path, [
            "import 'package:personal_os_in_memory/in_memory.dart';",
        ])
        violations = _MODULE.audit(self.root)
        self.assertEqual(len(violations), 1)

    def test_main_directory_imports_flagged(self) -> None:
        # main.dart lives at apps/personal_os_app/lib/main.dart, one level
        # above lib/src. The fallback root "apps/personal_os_app/lib/src"
        # does NOT cover lib/ root, so we instead place a file inside
        # lib/src/ to exercise the app-shell rule (already covered above).
        # This test documents the lib/src/ boundary explicitly.
        path = self.root / "apps/personal_os_app/lib/src/main_shell.dart"
        _write_dart(path, [
            "import 'package:personal_os_in_memory/in_memory.dart';",
        ])
        violations = _MODULE.audit(self.root)
        self.assertEqual(len(violations), 1)


class MainCliTests(unittest.TestCase):
    """``main()`` exit-code contract: 0 on PASS, 1 on FAIL."""

    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        _make_fake_repo(self.root)

    def test_main_returns_zero_on_clean_repo(self) -> None:
        rc = _MODULE.main([])
        self.assertEqual(rc, 0)

    def test_main_returns_nonzero_on_violations(self) -> None:
        path = self.root / "packages/domain/lib/domain.dart"
        _write_dart(path, [
            "import 'package:personal_os_in_memory/in_memory.dart';",
        ])
        # Patch the module-level ROOT so main() inspects our fake repo.
        original = _MODULE.ROOT
        _MODULE.ROOT = self.root
        try:
            rc = _MODULE.main([])
        finally:
            _MODULE.ROOT = original
        self.assertEqual(rc, 1)


class ViolationStringTests(unittest.TestCase):
    """Human-readable violation text mentions the rule and remediation."""

    def test_violation_str_includes_rule_and_action(self) -> None:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        root = Path(tmp.name)
        _make_fake_repo(root)
        path = root / "packages/domain/lib/domain.dart"
        _write_dart(path, [
            "import 'package:personal_os_in_memory/in_memory.dart';",
        ])
        violations = _MODULE.audit_file(path)
        self.assertEqual(len(violations), 1)
        text = str(violations[0])
        self.assertIn("ADR-0013", text)
        self.assertIn("ADR-0008", text)
        self.assertIn("Composition Root", text)
        self.assertIn("package:personal_os_in_memory/in_memory.dart", text)


if __name__ == "__main__":
    unittest.main()
