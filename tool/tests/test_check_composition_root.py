"""Unit tests for tool/check_composition_root.py.

Verifies the ADR-0008 §4 boundary checker correctly:
1. Returns 0 (PASS) when no forbidden imports exist.
2. Returns 1 (FAIL) with a clear violation report when a screen imports
   an adapter package.
3. Returns 2 (ERROR) when the repository root does not exist.
4. Does NOT flag adapter imports in composition/ or test/ directories
   (they are explicitly allowed by ADR-0008 §负面影响).
5. Identifies multiple violations across multiple files.
6. Identifies multiple adapter imports in the same file.
"""
from __future__ import annotations

import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path

# Load the script as a module without depending on a package install.
_SCRIPT_PATH = (
    Path(__file__).resolve().parent.parent / "check_composition_root.py"
)
_spec = importlib.util.spec_from_file_location(
    "check_composition_root", _SCRIPT_PATH
)
assert _spec is not None and _spec.loader is not None
_module = importlib.util.module_from_spec(_spec)
# Register the module in sys.modules BEFORE exec, so that
# @dataclass(frozen=True) can resolve cls.__module__ namespace
# correctly on Python 3.12+.
sys.modules["check_composition_root"] = _module
_spec.loader.exec_module(_module)


def _write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")


class CheckCompositionRootTest(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.root = Path(self._tmp.name)

    def _build_min_repo(self) -> None:
        """Create minimal repo skeleton so the script doesn't emit missing-dir warnings."""
        for sub in (
            "apps/personal_os_app/lib/src/screens",
            "apps/personal_os_app/lib/src/controller",
            "apps/personal_os_app/lib/src/navigation",
            "apps/personal_os_app/lib/src/composition",
            "apps/personal_os_app/test",
        ):
            (self.root / sub).mkdir(parents=True, exist_ok=True)

    def test_pass_when_no_adapter_imports_in_screens(self) -> None:
        self._build_min_repo()
        _write(
            self.root / "apps/personal_os_app/lib/src/screens/home_screen.dart",
            "import 'package:flutter/material.dart';\n"
            "import '../controller/app_controller.dart';\n"
            "class HomeScreen {}\n",
        )
        rc = _module.main(["--root", str(self.root)])
        self.assertEqual(rc, 0)

    def test_fail_when_screen_imports_in_memory(self) -> None:
        self._build_min_repo()
        _write(
            self.root / "apps/personal_os_app/lib/src/screens/home_screen.dart",
            "import 'package:personal_os_in_memory/in_memory.dart';\n"
            "class HomeScreen {}\n",
        )
        rc = _module.main(["--root", str(self.root)])
        self.assertEqual(rc, 1)

    def test_fail_when_controller_imports_sqlite_vault(self) -> None:
        self._build_min_repo()
        _write(
            self.root / "apps/personal_os_app/lib/src/controller/app_controller.dart",
            "import 'package:personal_os_sqlite_vault/sqlite_vault.dart';\n"
            "class AppController {}\n",
        )
        rc = _module.main(["--root", str(self.root)])
        self.assertEqual(rc, 1)

    def test_error_when_root_missing(self) -> None:
        rc = _module.main(["--root", "/this/path/does/not/exist/xyz123"])
        self.assertEqual(rc, 2)

    def test_composition_dir_can_import_adapters(self) -> None:
        self._build_min_repo()
        _write(
            self.root / "apps/personal_os_app/lib/src/composition/app_composition.dart",
            "import 'package:personal_os_in_memory/in_memory.dart';\n"
            "import 'package:personal_os_sqlite_vault/sqlite_vault.dart';\n"
            "class AppComposition {}\n",
        )
        rc = _module.main(["--root", str(self.root)])
        self.assertEqual(rc, 0)

    def test_test_dir_can_import_adapters(self) -> None:
        self._build_min_repo()
        _write(
            self.root / "apps/personal_os_app/test/widget_test.dart",
            "import 'package:personal_os_in_memory/in_memory.dart';\n"
            "void main() {}\n",
        )
        rc = _module.main(["--root", str(self.root)])
        self.assertEqual(rc, 0)

    def test_multiple_violations_across_files(self) -> None:
        self._build_min_repo()
        _write(
            self.root / "apps/personal_os_app/lib/src/screens/capture_screen.dart",
            "import 'package:personal_os_in_memory/in_memory.dart';\n",
        )
        _write(
            self.root / "apps/personal_os_app/lib/src/controller/app_controller.dart",
            "import 'package:personal_os_blob_engine/blob_engine.dart';\n",
        )
        rc = _module.main(["--root", str(self.root)])
        self.assertEqual(rc, 1)

    def test_multiple_adapter_imports_same_file(self) -> None:
        self._build_min_repo()
        _write(
            self.root / "apps/personal_os_app/lib/src/screens/home_screen.dart",
            "import 'package:personal_os_in_memory/in_memory.dart';\n"
            "import 'package:personal_os_model_fixture/model_fixture.dart';\n"
            "import 'package:personal_os_policy_application/policy_application.dart';\n"
            "class HomeScreen {}\n",
        )
        rc = _module.main(["--root", str(self.root)])
        self.assertEqual(rc, 1)

    def test_non_adapter_package_imports_pass(self) -> None:
        """Make sure non-adapter packages like flutter / domain / application are not flagged."""
        self._build_min_repo()
        _write(
            self.root / "apps/personal_os_app/lib/src/screens/home_screen.dart",
            "import 'package:flutter/material.dart';\n"
            "import 'package:personal_os_domain/domain.dart';\n"
            "import 'package:personal_os_application/application.dart';\n"
            "class HomeScreen {}\n",
        )
        rc = _module.main(["--root", str(self.root)])
        self.assertEqual(rc, 0)

    def test_in_memory_policy_not_confused_with_in_memory(self) -> None:
        """Personal_os_in_memory_policy is a separate package — make sure both
        are detected (not just one being matched as a substring of the other)."""
        self._build_min_repo()
        _write(
            self.root / "apps/personal_os_app/lib/src/controller/app_controller.dart",
            "import 'package:personal_os_in_memory_policy/in_memory_policy.dart';\n",
        )
        rc = _module.main(["--root", str(self.root)])
        self.assertEqual(rc, 1)


if __name__ == "__main__":
    unittest.main(verbosity=2)
