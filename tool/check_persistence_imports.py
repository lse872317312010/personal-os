#!/usr/bin/env python3
"""ADR-0013 §6 / ADR-0008 forbidden-zone audit.

Statically scans Dart sources for direct imports of persistence-layer
adapter packages from UI / Controller / Application Use Case / boundary
caller layers. The Composition Root (``apps/personal_os_app/lib/src/
composition``) is the only allowed import surface; everything else MUST
go through abstract interfaces defined in ``packages/storage_api`` and
``packages/security_api``.

The audit is dependency-free and runs in CI via
``tool/check_contracts.sh``. It does NOT require a Dart SDK and does
NOT evaluate types; it only inspects ``import`` and ``export``
directives. False positives are impossible by construction (the rule
matches package prefixes, not symbol names), and any genuine exception
must be added to ``_allow_list`` with a short rationale.

Reference:
- ADR-0008 — Composition Root (PR #14, may not yet be merged on main)
- ADR-0013 §6 — Persistence Layer Contract (PR #21)
- ADR-0014 §5 — caller-side mapper obligation (PR #23)
"""

from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

ROOT = Path(__file__).resolve().parents[1]

# Adapter packages that MUST NOT be imported outside the Composition Root.
# Sourced from ``adapters/*/pubspec.yaml`` ``name:`` field. New adapters
# added in the future should be appended here so they are caught from
# day one.
ADAPTER_PACKAGE_PREFIXES: tuple[str, ...] = (
    "package:personal_os_in_memory/",
    "package:personal_os_in_memory_policy/",
    "package:personal_os_in_memory_relay/",
    "package:personal_os_sqlite_vault/",
    "package:personal_os_sqlite_vault_driver/",
    "package:personal_os_device_security/",
    "package:personal_os_model_fixture/",
    "package:personal_os_policy_application/",
)

# Layers that are forbidden from importing adapter packages. Anything
# outside ``COMPOSITION_ROOT`` falls into one of these buckets. The
# paths are relative to repo root and use POSIX separators.
FORBIDDEN_LAYER_ROOTS: tuple[str, ...] = (
    "apps/personal_os_app/lib/src/screens",     # UI
    "apps/personal_os_app/lib/src/controller",  # Controller
    "apps/personal_os_app/lib/src/navigation",  # Navigation
    "apps/personal_os_app/lib/src",             # App shell (app.dart, main.dart fallback)
    "packages/application/lib",                 # Application Use Case
    "packages/runtime/lib",                     # Boundary caller (ADR-0014 §5)
    "packages/recovery/lib",                    # Boundary caller (ADR-0014 §5)
    "packages/sync_engine/lib",                 # Boundary caller (ADR-0014 §5)
    "packages/blob_engine/lib",                 # Boundary caller
    "packages/sync_api/lib",                    # Boundary caller
    "packages/policy/lib",                      # Domain policy port
    "packages/domain/lib",                      # Domain model
    "packages/events/lib",                      # Event envelope
    "packages/model_gateway_api/lib",           # Model gateway port
)

# The ONLY directory that may import adapter packages.
COMPOSITION_ROOT = "apps/personal_os_app/lib/src/composition"

# Tests may import adapters directly to construct seams. A file counts
# as a test when its path (relative to repo root) traverses a ``test``
# directory segment — this covers ``apps/.../test/``, ``packages/.../
# test/``, and ``adapters/.../test/`` without over-matching production
# ``packages/.../lib/`` sources (the bug that listing the bare
# ``"packages"`` prefix would introduce). ``test_contract/`` is a
# top-level exception with no ``/test/`` segment of its own.
TEST_CONTRACT_PREFIX = "test_contract/"


def _is_in_test(path: Path, root: Path) -> bool:
    """Tests may import adapters directly to construct seams."""

    posix = path.relative_to(root).as_posix()
    if posix.startswith(TEST_CONTRACT_PREFIX):
        return True
    return "/test/" in posix

IMPORT_DIRECTIVE = re.compile(
    r"^\s*(?:import|export)\s+(['\"])(package:[^'\"]+)\1",
)

# Per-file allow-list: when a future Composition Root helper is shared
# across screens, add the absolute path here with a one-line comment.
_ALLOW_LIST: set[Path] = set()


@dataclass(frozen=True)
class Violation:
    file: Path
    line_number: int
    line: str
    package: str

    def __str__(self) -> str:
        try:
            location = str(self.file.relative_to(ROOT))
        except ValueError:
            # File lives outside the canonical repo root (e.g. a unit
            # test's temp directory); fall back to the absolute path so
            # the message stays actionable without leaking inner state.
            location = str(self.file)
        return (
            f"{location}:{self.line_number}: forbidden adapter import "
            f"({self.package}) — move to Composition Root or inject "
            f"via abstract interface (ADR-0013 §6 / ADR-0008)"
        )


def _is_in_composition_root(path: Path, root: Path) -> bool:
    posix = path.relative_to(root).as_posix()
    return posix.startswith(COMPOSITION_ROOT)


def _iter_forbidden_dart_files(root: Path) -> Iterable[Path]:
    seen: set[Path] = set()
    for layer in FORBIDDEN_LAYER_ROOTS:
        layer_root = root / layer
        if not layer_root.is_dir():
            continue
        for dart in layer_root.rglob("*.dart"):
            if dart in seen:
                continue
            seen.add(dart)
            if _is_in_test(dart, root):
                continue
            if _is_in_composition_root(dart, root):
                continue
            if dart in _ALLOW_LIST:
                continue
            yield dart


def audit_file(path: Path) -> list[Violation]:
    violations: list[Violation] = []
    for line_number, line in enumerate(
        path.read_text(encoding="utf-8").splitlines(), start=1
    ):
        match = IMPORT_DIRECTIVE.match(line)
        if match is None:
            continue
        package = match.group(2)
        if any(package.startswith(prefix)
               for prefix in ADAPTER_PACKAGE_PREFIXES):
            violations.append(Violation(
                file=path,
                line_number=line_number,
                line=line,
                package=package,
            ))
    return violations


def audit(root: Path | None = None) -> list[Violation]:
    target_root = root or ROOT
    all_violations: list[Violation] = []
    for dart in _iter_forbidden_dart_files(target_root):
        all_violations.extend(audit_file(dart))
    return all_violations


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.parse_args(argv)

    violations = audit()
    if not violations:
        print("persistence imports: PASS")
        return 0

    print("persistence imports: FAIL", file=sys.stderr)
    for violation in violations:
        print(str(violation), file=sys.stderr)
    print(
        f"\n{len(violations)} violation(s) across "
        f"{len({v.file for v in violations})} file(s)",
        file=sys.stderr,
    )
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
