from __future__ import annotations

import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path

_SCRIPT = Path(__file__).resolve().parents[1] / "check_composition_root.py"
_SPEC = importlib.util.spec_from_file_location("composition_audit", _SCRIPT)
assert _SPEC is not None and _SPEC.loader is not None
_MODULE = importlib.util.module_from_spec(_SPEC)
sys.modules[_SPEC.name] = _MODULE
_SPEC.loader.exec_module(_MODULE)


class CompositionRootAuditTest(unittest.TestCase):
    def setUp(self) -> None:
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self._write(
            "adapters/example/pubspec.yaml",
            "name: personal_os_example_adapter\n",
        )
        (self.root / "apps/personal_os_app/lib").mkdir(
            parents=True,
            exist_ok=True,
        )

    def _write(self, relative: str, content: str) -> None:
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")

    def test_clean_application_passes(self) -> None:
        self._write(
            "apps/personal_os_app/lib/src/features/home.dart",
            "import 'package:personal_os_domain/domain.dart';\n",
        )
        self.assertEqual(_MODULE.main(["--root", str(self.root)]), 0)

    def test_any_application_subdirectory_is_scanned(self) -> None:
        self._write(
            "apps/personal_os_app/lib/src/features/nested/service.dart",
            "import 'package:personal_os_example_adapter/api.dart';\n",
        )
        self.assertEqual(_MODULE.main(["--root", str(self.root)]), 1)

    def test_exports_are_also_rejected(self) -> None:
        self._write(
            "apps/personal_os_app/lib/src/widgets/widget.dart",
            "export 'package:personal_os_example_adapter/api.dart';\n",
        )
        self.assertEqual(_MODULE.main(["--root", str(self.root)]), 1)

    def test_composition_directory_is_allowed_by_path_segment(self) -> None:
        self._write(
            "apps/personal_os_app/lib/src/composition/nested/root.dart",
            "import 'package:personal_os_example_adapter/api.dart';\n",
        )
        self.assertEqual(_MODULE.main(["--root", str(self.root)]), 0)

    def test_similarly_named_directory_is_not_allowed(self) -> None:
        self._write(
            "apps/personal_os_app/lib/src/composition_evil/root.dart",
            "import 'package:personal_os_example_adapter/api.dart';\n",
        )
        self.assertEqual(_MODULE.main(["--root", str(self.root)]), 1)

    def test_only_explicit_launchers_are_allowed(self) -> None:
        import_line = (
            "import 'package:personal_os_example_adapter/api.dart';\n"
        )
        self._write("apps/personal_os_app/lib/main.dart", import_line)
        self._write("apps/personal_os_app/lib/main_dev.dart", import_line)
        self._write("apps/personal_os_app/lib/main_prod.dart", import_line)
        self.assertEqual(_MODULE.main(["--root", str(self.root)]), 0)
        self._write("apps/personal_os_app/lib/main_preview.dart", import_line)
        self.assertEqual(_MODULE.main(["--root", str(self.root)]), 1)

    def test_new_adapter_is_discovered_without_script_change(self) -> None:
        self._write(
            "adapters/future/pubspec.yaml",
            "name: personal_os_future_adapter\n",
        )
        self._write(
            "apps/personal_os_app/lib/src/future.dart",
            "import 'package:personal_os_future_adapter/api.dart';\n",
        )
        violations = _MODULE.scan(self.root)
        self.assertEqual(violations[0].package, "personal_os_future_adapter")

    def test_missing_adapter_manifests_is_an_error(self) -> None:
        empty = tempfile.TemporaryDirectory()
        self.addCleanup(empty.cleanup)
        root = Path(empty.name)
        (root / "apps/personal_os_app/lib").mkdir(parents=True)
        self.assertEqual(_MODULE.main(["--root", str(root)]), 2)


if __name__ == "__main__":
    unittest.main()
