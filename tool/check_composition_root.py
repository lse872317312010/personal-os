#!/usr/bin/env python3
"""Enforce ADR-0008's application composition boundary."""

from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass
from pathlib import Path

_NAME_RE = re.compile(r"^name:\s*([a-zA-Z0-9_]+)\s*$", re.MULTILINE)
_IMPORT_RE = re.compile(
    r"""^\s*(?:import|export)\s+['"]package:([^/'"]+)/[^'"]+['"]""",
)
_APP_LIB = Path("apps/personal_os_app/lib")
_ALLOWED_FILES = frozenset(
    {
        Path("apps/personal_os_app/lib/main.dart"),
        Path("apps/personal_os_app/lib/main_dev.dart"),
        Path("apps/personal_os_app/lib/main_prod.dart"),
    }
)
_COMPOSITION_DIR = Path("apps/personal_os_app/lib/src/composition")


@dataclass(frozen=True)
class Violation:
    path: Path
    line: int
    package: str


def discover_adapter_packages(root: Path) -> frozenset[str]:
    """Read adapter package names from manifests; never use a stale list."""
    adapters = root / "adapters"
    if not adapters.is_dir():
        raise ValueError("adapters directory is missing")
    names: set[str] = set()
    for manifest in sorted(adapters.glob("*/pubspec.yaml")):
        match = _NAME_RE.search(manifest.read_text(encoding="utf-8"))
        if match is None:
            raise ValueError(f"missing package name: {manifest}")
        names.add(match.group(1))
    if not names:
        raise ValueError("no adapter packages discovered")
    return frozenset(names)


def _is_allowed(relative_path: Path) -> bool:
    if relative_path in _ALLOWED_FILES:
        return True
    try:
        relative_path.relative_to(_COMPOSITION_DIR)
        return True
    except ValueError:
        return False


def scan(root: Path) -> list[Violation]:
    app_lib = root / _APP_LIB
    if not app_lib.is_dir():
        raise ValueError(f"application lib directory is missing: {app_lib}")
    adapter_packages = discover_adapter_packages(root)
    violations: list[Violation] = []
    for path in sorted(app_lib.rglob("*.dart")):
        relative = path.relative_to(root)
        if _is_allowed(relative):
            continue
        for line_number, line in enumerate(
            path.read_text(encoding="utf-8").splitlines(),
            start=1,
        ):
            match = _IMPORT_RE.match(line)
            if match is not None and match.group(1) in adapter_packages:
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
    root = args.root.resolve()
    try:
        violations = scan(root)
    except (OSError, ValueError) as error:
        print(f"composition-root audit: ERROR: {error}", file=sys.stderr)
        return 2
    if not violations:
        print("composition-root audit: PASS")
        return 0
    print("composition-root audit: FAIL", file=sys.stderr)
    for violation in violations:
        print(
            f"{violation.path}:{violation.line}: "
            f"adapter import {violation.package}",
            file=sys.stderr,
        )
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
