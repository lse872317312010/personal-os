#!/usr/bin/env python3
"""Reject concrete persistence adapters outside composition roots."""

from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import dataclass
from pathlib import Path

_IMPORT_RE = re.compile(
    r"""^\s*(?:import|export)\s+['"]package:([^/'"]+)/[^'"]+['"]""",
)
_NAME_RE = re.compile(r"^name:\s*([a-zA-Z0-9_]+)\s*$", re.MULTILINE)
_CLASSIFICATION = Path("architecture/adapter_classification.json")
_APP_LIB = Path("apps/personal_os_app/lib")
_COMPOSITION = Path("apps/personal_os_app/lib/src/composition")
_LAUNCHERS = frozenset(
    {
        Path("apps/personal_os_app/lib/main.dart"),
        Path("apps/personal_os_app/lib/main_dev.dart"),
        Path("apps/personal_os_app/lib/main_prod.dart"),
    }
)


@dataclass(frozen=True)
class Violation:
    path: Path
    line: int
    package: str


def load_persistence_packages(root: Path) -> frozenset[str]:
    data = json.loads((root / _CLASSIFICATION).read_text(encoding="utf-8"))
    if data.get("schema_version") != 1:
        raise ValueError("unsupported adapter classification schema")
    entries = data.get("adapters")
    if not isinstance(entries, dict):
        raise ValueError("adapter classification must contain an object")

    adapter_root = root / "adapters"
    actual_dirs = {
        path.parent.name for path in adapter_root.glob("*/pubspec.yaml")
    }
    classified_dirs = set(entries)
    if actual_dirs != classified_dirs:
        missing = sorted(actual_dirs - classified_dirs)
        stale = sorted(classified_dirs - actual_dirs)
        raise ValueError(
            f"adapter classification mismatch: missing={missing}, stale={stale}"
        )

    persistence: set[str] = set()
    for directory, entry in entries.items():
        if not isinstance(entry, dict):
            raise ValueError(f"invalid classification: {directory}")
        package = entry.get("package")
        kind = entry.get("kind")
        if not isinstance(package, str) or not isinstance(kind, str):
            raise ValueError(f"invalid classification fields: {directory}")
        manifest = adapter_root / directory / "pubspec.yaml"
        match = _NAME_RE.search(manifest.read_text(encoding="utf-8"))
        if match is None or match.group(1) != package:
            raise ValueError(f"package name mismatch: {directory}")
        if kind == "persistence":
            persistence.add(package)
    if not persistence:
        raise ValueError("no persistence adapters classified")
    return frozenset(persistence)


def _allowed_application_path(path: Path) -> bool:
    if path in _LAUNCHERS:
        return True
    try:
        path.relative_to(_COMPOSITION)
        return True
    except ValueError:
        return False


def _production_files(root: Path) -> list[Path]:
    files = list((root / "packages").glob("*/lib/**/*.dart"))
    app = root / _APP_LIB
    if not app.is_dir():
        raise ValueError("application lib directory is missing")
    for path in app.rglob("*.dart"):
        if not _allowed_application_path(path.relative_to(root)):
            files.append(path)
    return sorted(files)


def scan(root: Path) -> list[Violation]:
    packages = load_persistence_packages(root)
    violations: list[Violation] = []
    for path in _production_files(root):
        relative = path.relative_to(root)
        for line_number, line in enumerate(
            path.read_text(encoding="utf-8").splitlines(),
            start=1,
        ):
            match = _IMPORT_RE.match(line)
            if match is not None and match.group(1) in packages:
                violations.append(
                    Violation(relative, line_number, match.group(1))
                )
    return violations


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--root",
        type=Path,
        default=Path(__file__).resolve().parent.parent,
    )
    args = parser.parse_args(argv)
    try:
        violations = scan(args.root.resolve())
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"persistence-boundary audit: ERROR: {error}", file=sys.stderr)
        return 2
    if not violations:
        print("persistence-boundary audit: PASS")
        return 0
    print("persistence-boundary audit: FAIL", file=sys.stderr)
    for violation in violations:
        print(
            f"{violation.path}:{violation.line}: "
            f"concrete persistence adapter {violation.package}",
            file=sys.stderr,
        )
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
