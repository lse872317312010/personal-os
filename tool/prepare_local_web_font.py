#!/usr/bin/env python3
"""Bundle a pinned, OFL-licensed CJK font; never fetch user data at runtime."""
from hashlib import sha1, sha256
from pathlib import Path
from urllib.request import urlopen

ROOT = Path(__file__).resolve().parent.parent
COMMIT = "f8d157532fbfaeda587e826d4cd5b21a49186f7c"
EXPECTED_BLOB = "5371a543be5fc670c7cdee9760c03554ee3e9b8e"
SOURCE = f"https://raw.githubusercontent.com/notofonts/noto-cjk/{COMMIT}/Sans/Variable/TTF/Subset/NotoSansSC-VF.ttf"
TARGET = ROOT / "apps/personal_os_app/web/fonts/NotoSansSC.ttf"


def main() -> None:
    with urlopen(SOURCE, timeout=90) as response:
        content = response.read()
    digest = sha1(f"blob {len(content)}\0".encode() + content).hexdigest()
    if digest != EXPECTED_BLOB:
        raise RuntimeError("Bundled font did not match the pinned upstream blob")
    TARGET.parent.mkdir(parents=True, exist_ok=True)
    TARGET.write_bytes(content)
    print(f"Bundled Noto Sans SC: {len(content)} bytes, sha256:{sha256(content).hexdigest()}")


if __name__ == "__main__":
    main()
