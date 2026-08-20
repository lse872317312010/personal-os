#!/usr/bin/env python3
"""Validate local Dart path dependencies without requiring a Dart SDK."""

from __future__ import annotations

import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PACKAGE_ROOTS = (ROOT / "packages", ROOT / "adapters", ROOT / "test_contract")
PATH_LINE = re.compile(r"^\s*path:\s*([^#]+?)\s*$")


def main() -> int:
    manifests = sorted(
        manifest
        for package_root in PACKAGE_ROOTS
        if package_root.exists()
        for manifest in package_root.rglob("pubspec.yaml")
    )
    failures: list[str] = []
    checked = 0
    for manifest in manifests:
        for line_number, line in enumerate(
            manifest.read_text(encoding="utf-8").splitlines(), start=1
        ):
            match = PATH_LINE.match(line)
            if match is None:
                continue
            checked += 1
            raw_path = match.group(1).strip().strip("'\"")
            dependency = (manifest.parent / raw_path).resolve()
            try:
                dependency.relative_to(ROOT)
            except ValueError:
                failures.append(
                    f"{manifest.relative_to(ROOT)}:{line_number}: "
                    f"dependency escapes repository: {raw_path}"
                )
                continue
            if not (dependency / "pubspec.yaml").is_file():
                failures.append(
                    f"{manifest.relative_to(ROOT)}:{line_number}: "
                    f"missing local package: {raw_path}"
                )

    if failures:
        print("\n".join(failures), file=sys.stderr)
        return 1
    print(
        f"local dependency graph: PASS "
        f"({len(manifests)} manifests, {checked} path dependencies)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
