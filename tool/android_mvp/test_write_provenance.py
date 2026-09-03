#!/usr/bin/env python3
"""Static smoke test for the APK provenance manifest writer."""

import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
WRITER = ROOT / "tool/android_mvp/write_provenance.py"


def main() -> None:
    with tempfile.TemporaryDirectory() as temporary:
        root = Path(temporary)
        app_dir = root / "app"
        app_dir.mkdir()
        (app_dir / "pubspec.yaml").write_text("name: test\nversion: 1.2.3+4\n", encoding="utf-8")
        apk = root / "app-debug.apk"
        apk.write_bytes(b"test apk")
        manifest_path = root / "app-debug.provenance.json"
        environment = {
            **os.environ,
            "GITHUB_SHA": "a" * 40,
            "GITHUB_RUN_ID": "12345",
            "GITHUB_WORKFLOW": "Flutter Android",
            "PERSONAL_OS_BUILD_NUMBER": "321",
        }
        subprocess.run(
            [sys.executable, str(WRITER), "--app-dir", str(app_dir), "--apk", str(apk), "--output", str(manifest_path)],
            check=True,
            env=environment,
        )
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        assert manifest["github_sha"] == "a" * 40
        assert manifest["run_id"] == "12345"
        assert manifest["workflow"] == "Flutter Android"
        assert manifest["app_version"] == "1.2.3+321"
        assert len(manifest["apk_sha256"]) == 64
        assert manifest["built_at"].endswith("Z")


if __name__ == "__main__":
    main()
