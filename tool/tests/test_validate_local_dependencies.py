"""Tests for tool/validate_local_dependencies.py."""

from __future__ import annotations

import subprocess
import sys
import textwrap
from pathlib import Path

import pytest

SCRIPT = Path(__file__).resolve().parents[1] / "validate_local_dependencies.py"


def _make_pubspec(dir_path: Path, name: str, deps: dict[str, str] | None = None) -> None:
    """Create a minimal pubspec.yaml."""
    dir_path.mkdir(parents=True, exist_ok=True)
    content = f"name: {name}\n"
    if deps:
        content += "dependencies:\n"
        for dep_name, dep_path in deps.items():
            content += f"  {dep_name}:\n"
            content += f"    path: {dep_path}\n"
    (dir_path / "pubspec.yaml").write_text(content, encoding="utf-8")


def test_valid_local_dependency_passes(tmp_path: Path) -> None:
    """A valid local path dependency should pass validation."""
    _make_pubspec(tmp_path / "packages" / "a", "a")
    _make_pubspec(tmp_path / "packages" / "b", "b", deps={"a": "../a"})

    # Copy script to tmp_path so ROOT resolves to tmp_path
    script_copy = tmp_path / "tool" / "validate_local_dependencies.py"
    script_copy.parent.mkdir(parents=True)
    script_copy.write_text(SCRIPT.read_text(encoding="utf-8"), encoding="utf-8")

    result = subprocess.run(
        [sys.executable, str(script_copy)],
        capture_output=True,
        text=True,
        cwd=str(tmp_path),
    )
    assert result.returncode == 0, result.stderr
    assert "PASS" in result.stdout


def test_dependency_escaping_repo_fails(tmp_path: Path) -> None:
    """A path dependency that escapes the repository should fail."""
    _make_pubspec(tmp_path / "packages" / "a", "a")
    _make_pubspec(tmp_path / "packages" / "b", "b", deps={"external": "../../../outside"})

    script_copy = tmp_path / "tool" / "validate_local_dependencies.py"
    script_copy.parent.mkdir(parents=True)
    script_copy.write_text(SCRIPT.read_text(encoding="utf-8"), encoding="utf-8")

    result = subprocess.run(
        [sys.executable, str(script_copy)],
        capture_output=True,
        text=True,
        cwd=str(tmp_path),
    )
    assert result.returncode == 1
    assert "escapes repository" in result.stderr


def test_missing_local_package_fails(tmp_path: Path) -> None:
    """A path dependency pointing to a missing package should fail."""
    _make_pubspec(tmp_path / "packages" / "b", "b", deps={"missing": "./nonexistent"})

    script_copy = tmp_path / "tool" / "validate_local_dependencies.py"
    script_copy.parent.mkdir(parents=True)
    script_copy.write_text(SCRIPT.read_text(encoding="utf-8"), encoding="utf-8")

    result = subprocess.run(
        [sys.executable, str(script_copy)],
        capture_output=True,
        text=True,
        cwd=str(tmp_path),
    )
    assert result.returncode == 1
    assert "missing local package" in result.stderr


def test_no_path_dependencies_passes(tmp_path: Path) -> None:
    """Packages without path dependencies should pass."""
    _make_pubspec(tmp_path / "packages" / "a", "a")
    _make_pubspec(tmp_path / "packages" / "b", "b")

    script_copy = tmp_path / "tool" / "validate_local_dependencies.py"
    script_copy.parent.mkdir(parents=True)
    script_copy.write_text(SCRIPT.read_text(encoding="utf-8"), encoding="utf-8")

    result = subprocess.run(
        [sys.executable, str(script_copy)],
        capture_output=True,
        text=True,
        cwd=str(tmp_path),
    )
    assert result.returncode == 0, result.stderr
    assert "0 path dependencies" in result.stdout
