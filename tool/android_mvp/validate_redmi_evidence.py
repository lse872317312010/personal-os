#!/usr/bin/env python3
"""Compatibility CLI for the canonical Redmi evidence validator."""

from __future__ import annotations

import argparse
import importlib.util
import json
import sys
from pathlib import Path

CANONICAL_PATH = (
    Path(__file__).resolve().parents[2]
    / "evidence"
    / "android"
    / "tool"
    / "validate_evidence.py"
)
SPEC = importlib.util.spec_from_file_location(
    "canonical_redmi_evidence",
    CANONICAL_PATH,
)
CANONICAL = importlib.util.module_from_spec(SPEC)
assert SPEC.loader
SPEC.loader.exec_module(CANONICAL)


def validate(data: object, require_ready: bool = False) -> bool:
    ready = CANONICAL.validate(data)
    if require_ready and not ready:
        raise ValueError(
            "evidence is structurally valid but device scenarios are not all ready"
        )
    return ready


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("evidence", type=Path)
    parser.add_argument("--require-ready", action="store_true")
    args = parser.parse_args()
    try:
        data = json.loads(args.evidence.read_text(encoding="utf-8"))
        ready = validate(data, require_ready=args.require_ready)
    except (OSError, json.JSONDecodeError, ValueError, TypeError) as error:
        print(f"INVALID_EVIDENCE: {error}", file=sys.stderr)
        return 2
    print("DEVICE_VERIFIED" if ready else "VALID_NOT_READY")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
