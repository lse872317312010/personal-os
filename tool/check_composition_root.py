#!/usr/bin/env python3
"""ADR-0008 §4 静态检查器 — Composition Root 边界守门员。

Golden Rule (ADR-0008):
  应用代码中只有 `AppComposition` 类与 3 个 launcher `main_*.dart` 有权
  `import` 具体 adapter 实现文件。任何其他 .dart 文件如果出现 adapter
  包名的 import 一律视为违规。

本脚本扫描以下"禁区"目录下的 .dart 文件：
  - apps/personal_os_app/lib/src/screens/
  - apps/personal_os_app/lib/src/controller/
  - apps/personal_os_app/lib/src/navigation/
  - apps/personal_os_app/lib/src/composition/   (允许，作为对照)

禁区中以下 adapter 包名出现次数必须 == 0：
  - personal_os_in_memory
  - personal_os_in_memory_policy
  - personal_os_in_memory_relay
  - personal_os_sqlite_vault
  - personal_os_sqlite_vault_driver
  - personal_os_blob_engine
  - personal_os_model_fixture
  - personal_os_policy_application
  - personal_os_device_security

允许出现这些 import 的目录仅：
  - apps/personal_os_app/lib/src/composition/
  - apps/personal_os_app/lib/main.dart / main_dev.dart / main_prod.dart
  - apps/personal_os_app/test/**         (ADR-0008 §负面影响：测试文件不受限)
  - apps/personal_os_app/integration_test/**

退出码:
  0  所有禁区干净
  1  发现违规 import
  2  脚本本身出错（路径不存在等）

用法:
  python3 tool/check_composition_root.py [--root REPO_ROOT] [--verbose]

Refs:
  - ADR-0008 §4（约束 4 — 可审计 CI grep 断言）
  - Wave 20c (I): 本脚本是 Wave B1.x 后续行动 #1 的落地
"""
from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

# ADR-0008 §4 列出的 adapter 包名。任何禁区 .dart 文件 import 这些包
# 之一即视为违规。注意：必须用精确前缀匹配，避免误伤 personal_os_in_memory_policy
# 被 personal_os_in_memory 命中（前者是独立包）。
ADAPTER_PACKAGE_PREFIXES: tuple[str, ...] = (
    "personal_os_in_memory/",
    "personal_os_in_memory_policy/",
    "personal_os_in_memory_relay/",
    "personal_os_sqlite_vault/",
    "personal_os_sqlite_vault_driver/",
    "personal_os_blob_engine/",
    "personal_os_model_fixture/",
    "personal_os_policy_application/",
    "personal_os_device_security/",
)

# 禁区目录（相对于 repo root）。这些目录下的 .dart 文件不允许
# import 任何 ADAPTER_PACKAGE_PREFIXES 中的包。
FORBIDDEN_DIRS: tuple[str, ...] = (
    "apps/personal_os_app/lib/src/screens",
    "apps/personal_os_app/lib/src/controller",
    "apps/personal_os_app/lib/src/navigation",
)

# 允许 import adapter 的目录（作为对照，本脚本不检查这些目录但会
# 在 verbose 模式下打印数量供审计员参考）。
ALLOWED_DIRS: tuple[str, ...] = (
    "apps/personal_os_app/lib/src/composition",
)

# 测试目录豁免（ADR-0008 §负面影响明确允许测试文件自由 import adapter）。
TEST_DIRS: tuple[str, ...] = (
    "apps/personal_os_app/test",
    "apps/personal_os_app/integration_test",
)

# 简单 import 行识别。Dart import 语法：
#   import 'package:personal_os_in_memory/in_memory.dart';
#   import 'package:personal_os_in_memory/in_memory.dart' deferred as foo;
# 我们只关心 package: 前缀 + adapter 包名。
_IMPORT_RE = re.compile(
    r"""^\s*import\s+['"]package:([^/'"]+/[^'"]+)['"]""",
    re.MULTILINE,
)


@dataclass(frozen=True)
class Violation:
    """单条违规记录。"""

    file: Path
    line_number: int
    line: str
    matched_prefix: str

    def format(self, repo_root: Path) -> str:
        rel = self.file.relative_to(repo_root)
        return (
            f"  ✗ {rel}:{self.line_number}\n"
            f"    {self.line.strip()}\n"
            f"    matched adapter prefix: {self.matched_prefix}"
        )


def _iter_dart_files(root: Path, subdirs: tuple[str, ...]) -> Iterable[Path]:
    """枚举 subdirs 下所有 .dart 文件（递归）。"""
    for sub in subdirs:
        base = root / sub
        if not base.exists():
            continue
        if base.is_file() and base.suffix == ".dart":
            yield base
            continue
        for path in base.rglob("*.dart"):
            if path.is_file():
                yield path


def _scan_file(path: Path) -> list[tuple[int, str, str]]:
    """扫描单个 .dart 文件，返回 [(line_number, line, matched_prefix), ...]。"""
    violations: list[tuple[int, str, str]] = []
    try:
        text = path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        # 用 errors='replace' 重读一遍，至少不崩
        text = path.read_text(encoding="utf-8", errors="replace")

    # 按行扫描，便于报错时给出行号
    for lineno, raw in enumerate(text.splitlines(), start=1):
        stripped = raw.strip()
        if not stripped.startswith("import "):
            continue
        for prefix in ADAPTER_PACKAGE_PREFIXES:
            needle = f"package:{prefix}"
            if needle in stripped:
                violations.append((lineno, raw, prefix))
                break  # 一行只算一条违规（多 adapter import 不太可能挤一行）
    return violations


def scan(root: Path, verbose: bool = False) -> list[Violation]:
    """扫描全部禁区目录，返回违规列表。"""
    all_violations: list[Violation] = []
    for path in _iter_dart_files(root, FORBIDDEN_DIRS):
        for lineno, line, prefix in _scan_file(path):
            all_violations.append(
                Violation(
                    file=path,
                    line_number=lineno,
                    line=line,
                    matched_prefix=prefix,
                )
            )

    if verbose:
        # 在 verbose 模式下打印 ALLOWED_DIRS 和 TEST_DIRS 中的 import
        # 计数，方便审计员一眼看到 adapter 包当前被谁合法使用。
        for label, dirs in (("ALLOWED", ALLOWED_DIRS), ("TEST", TEST_DIRS)):
            for path in _iter_dart_files(root, dirs):
                hits = _scan_file(path)
                if hits:
                    rel = path.relative_to(root)
                    print(f"  [.{label}] {rel}: {len(hits)} adapter import(s)")

    return all_violations


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="ADR-0008 §4 composition root boundary checker.",
    )
    parser.add_argument(
        "--root",
        type=Path,
        default=Path(__file__).resolve().parent.parent,
        help="Repository root (default: parent of tool/).",
    )
    parser.add_argument(
        "--verbose",
        action="store_true",
        help="Also print adapter imports in ALLOWED / TEST directories.",
    )
    args = parser.parse_args(argv)

    root: Path = args.root.resolve()
    if not root.is_dir():
        print(f"ERROR: repository root does not exist or is not a directory: {root}",
              file=sys.stderr)
        return 2

    # 简单 sanity check：禁区目录至少应该存在（如果整个 screens/
    # 都没有，可能是 repo 结构变了，需要人工检查）。
    missing = [d for d in FORBIDDEN_DIRS if not (root / d).exists()]
    if missing:
        print(
            f"WARNING: forbidden directories missing (repo structure changed?): "
            f"{missing}",
            file=sys.stderr,
        )

    violations = scan(root, verbose=args.verbose)

    if not violations:
        print("composition-root audit: PASS (0 violations)")
        return 0

    print(
        f"composition-root audit: FAIL ({len(violations)} violation(s))\n"
        f"ADR-0008 §4 forbids importing adapter packages from screens / "
        f"controller / navigation directories.\n"
        f"Violations:",
        file=sys.stderr,
    )
    for v in violations:
        print(v.format(root), file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
