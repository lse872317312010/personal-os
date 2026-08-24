#!/usr/bin/env python3
"""Write the non-sensitive provenance manifest for a successfully built APK."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
from datetime import datetime, timezone
from pathlib import Path


VERSION_RE = re.compile(r"^version:\s*([^\s#]+)\s*$", re.MULTILINE)
SHA_RE = re.compile(r"^[0-9a-f]{40}$")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--app-dir", type=Path, required=True)
    parser.add_argument("--apk", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    return parser.parse_args()


def app_version(app_dir: Path) -> str:
    pubspec = (app_dir / "pubspec.yaml").read_text(encoding="utf-8")
    match = VERSION_RE.search(pubspec)
    if not match:
        raise ValueError("pubspec.yaml does not contain a version")
    return match.group(1)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as apk:
        for chunk in iter(lambda: apk.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def required_ci_value(name: str, fallback: str) -> str:
    value = os.environ.get(name, fallback)
    if not value or any(char in value for char in "\r\n"):
        raise ValueError(f"{name} must be a non-empty single-line value")
    return value


def main() -> None:
    args = parse_args()
    if not args.apk.is_file():
        raise FileNotFoundError(f"APK not found: {args.apk}")

    github_sha = required_ci_value("GITHUB_SHA", "local")
    if github_sha != "local" and not SHA_RE.fullmatch(github_sha):
        raise ValueError("GITHUB_SHA must be a 40-character lowercase commit SHA")
    run_id = required_ci_value("GITHUB_RUN_ID", "local")
    workflow = required_ci_value("GITHUB_WORKFLOW", "local")
    if run_id != "local" and not run_id.isdigit():
        raise ValueError("GITHUB_RUN_ID must be numeric")

    manifest = {
        "schema_version": 1,
        "github_sha": github_sha,
        "workflow": workflow,
        "run_id": run_id,
        "app_version": app_version(args.app_dir),
        "apk_sha256": sha256(args.apk),
        "built_at": datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )


if __name__ == "__main__":
    main()
