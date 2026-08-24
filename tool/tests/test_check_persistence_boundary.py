from __future__ import annotations

import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path

_SCRIPT = Path(__file__).resolve().parents[1] / "check_persistence_boundary.py"
_SPEC = importlib.util.spec_from_file_location("persistence_audit", _SCRIPT)
assert _SPEC is not None and _SPEC.loader is not None
_MODULE = importlib.util.module_from_spec(_SPEC)
sys.modules[_SPEC.name] = _MODULE
_SPEC.loader.exec_module(_MODULE)


class PersistenceBoundaryAuditTest(unittest.TestCase):
    def setUp(self) -> None:
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self._adapter("vault", "personal_os_vault", "persistence")
        self._adapter("model", "personal_os_model", "model")
        (self.root / "apps/personal_os_app/lib").mkdir(
            parents=True,
            exist_ok=True,
        )
        self._write_classification()

    def _adapter(self, directory: str, package: str, kind: str) -> None:
        path = self.root / "adapters" / directory / "pubspec.yaml"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(f"name: {package}\n", encoding="utf-8")
        if not hasattr(self, "entries"):
            self.entries = {}
        self.entries[directory] = {"package": package, "kind": kind}

    def _write_classification(self) -> None:
        path = self.root / "architecture/adapter_classification.json"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(
            json.dumps({"schema_version": 1, "adapters": self.entries}),
            encoding="utf-8",
        )

    def _write(self, relative: str, content: str) -> None:
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")

    def test_core_package_cannot_import_persistence_adapter(self) -> None:
        self._write(
            "packages/runtime/lib/runtime.dart",
            "import 'package:personal_os_vault/vault.dart';\n",
        )
        self.assertEqual(_MODULE.main(["--root", str(self.root)]), 1)

    def test_all_application_subdirectories_are_scanned(self) -> None:
        self._write(
            "apps/personal_os_app/lib/src/features/service.dart",
            "export 'package:personal_os_vault/vault.dart';\n",
        )
        self.assertEqual(_MODULE.main(["--root", str(self.root)]), 1)

    def test_composition_is_precisely_allowed(self) -> None:
        line = "import 'package:personal_os_vault/vault.dart';\n"
        self._write(
            "apps/personal_os_app/lib/src/composition/root.dart",
            line,
        )
        self.assertEqual(_MODULE.main(["--root", str(self.root)]), 0)
        self._write(
            "apps/personal_os_app/lib/src/composition_evil/root.dart",
            line,
        )
        self.assertEqual(_MODULE.main(["--root", str(self.root)]), 1)

    def test_non_persistence_adapter_is_out_of_scope(self) -> None:
        self._write(
            "packages/runtime/lib/runtime.dart",
            "import 'package:personal_os_model/model.dart';\n",
        )
        self.assertEqual(_MODULE.main(["--root", str(self.root)]), 0)

    def test_unclassified_new_adapter_fails_closed(self) -> None:
        path = self.root / "adapters/future/pubspec.yaml"
        path.parent.mkdir(parents=True)
        path.write_text("name: personal_os_future\n", encoding="utf-8")
        self.assertEqual(_MODULE.main(["--root", str(self.root)]), 2)

    def test_stale_classification_fails_closed(self) -> None:
        (self.root / "adapters/model/pubspec.yaml").unlink()
        self.assertEqual(_MODULE.main(["--root", str(self.root)]), 2)

    def test_manifest_name_must_match_classification(self) -> None:
        path = self.root / "adapters/vault/pubspec.yaml"
        path.write_text("name: personal_os_renamed\n", encoding="utf-8")
        self.assertEqual(_MODULE.main(["--root", str(self.root)]), 2)


if __name__ == "__main__":
    unittest.main()
