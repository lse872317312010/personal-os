#!/usr/bin/env python3
"""Verify a downloaded APK, checksum sidecar, and provenance as one candidate."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path


SHA40 = re.compile(r"^[0-9a-f]{40}$")
SHA256 = re.compile(r"^[0-9a-f]{64}$")


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def verify(apk: Path, checksum: Path, provenance_path: Path) -> dict[str, str]:
    if not apk.is_file() or apk.stat().st_size <= 0:
        raise ValueError("APK must be a non-empty file")
    checksum_lines = [
        line.strip() for line in checksum.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]
    if len(checksum_lines) != 1:
        raise ValueError("checksum sidecar must contain exactly one record")
    checksum_parts = checksum_lines[0].split(maxsplit=1)
    if len(checksum_parts) != 2 or not SHA256.fullmatch(checksum_parts[0]):
        raise ValueError("checksum sidecar must contain SHA-256 and filename")

    actual_sha = file_sha256(apk)
    if checksum_parts[0] != actual_sha:
        raise ValueError("checksum sidecar does not match APK")

    provenance = json.loads(provenance_path.read_text(encoding="utf-8"))
    if not isinstance(provenance, dict) or provenance.get("schema_version") != 1:
        raise ValueError("unsupported provenance schema")
    if provenance.get("apk_sha256") != actual_sha:
        raise ValueError("provenance does not match APK")
    commit = provenance.get("github_sha")
    if not isinstance(commit, str) or not SHA40.fullmatch(commit):
        raise ValueError("provenance github_sha must be lowercase SHA-1")
    app_version = provenance.get("app_version")
    if not isinstance(app_version, str) or not app_version.strip():
        raise ValueError("provenance app_version is required")
    run_id = provenance.get("run_id")
    if not isinstance(run_id, str) or not run_id.isdigit():
        raise ValueError("provenance run_id must be numeric")

    return {
        "commit_sha": commit,
        "apk_sha256": actual_sha,
        "app_version": app_version,
        "workflow_run_id": run_id,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--apk", type=Path, required=True)
    parser.add_argument("--checksum", type=Path, required=True)
    parser.add_argument("--provenance", type=Path, required=True)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    try:
        result = verify(args.apk, args.checksum, args.provenance)
    except (OSError, json.JSONDecodeError, ValueError) as error:
        print(f"INVALID_RELEASE_CANDIDATE: {error}", file=sys.stderr)
        return 2
    rendered = json.dumps(result, indent=2, sort_keys=True) + "\n"
    if args.output:
        args.output.write_text(rendered, encoding="utf-8")
    else:
        print(rendered, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
