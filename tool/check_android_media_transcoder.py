#!/usr/bin/env python3
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parent.parent
TRANSCODER = ROOT / "apps/personal_os_app/android/app/src/main/kotlin/com/personalos/app/model/AndroidExternalMediaTranscoder.kt"
MAIN = ROOT / "apps/personal_os_app/android/app/src/main/kotlin/com/personalos/app/MainActivity.kt"
TEST = ROOT / "apps/personal_os_app/android/app/src/test/kotlin/com/personalos/app/model/AndroidExternalMediaTranscoderTest.kt"

checks = {
    TRANSCODER: (
        'setOf("image/heif", "image/avif")',
        'MAXIMUM_ENCODED_INPUT_BYTES = 15 * 1024 * 1024',
        'MAXIMUM_DECODED_PIXELS = 12_000_000L',
        'MAXIMUM_EDGE_PIXELS = 4_096',
        'request.copy(mediaType = "image/jpeg")',
        'bitmap.recycle()',
        'buf.fill(0)',
    ),
    MAIN: ('TranscodingExternalAppearanceModelClient(',),
    TEST: (
        'preservesAlreadySupportedStreamingMediaWithoutBuffering',
        'boundsLargeLandscapeByEdgeAndPixelBudget',
        'legacyDecoderUsesPowerOfTwoSampleLargeEnoughForBudget',
    ),
}

errors = []
for path, tokens in checks.items():
    try:
        text = path.read_text(encoding="utf-8")
    except OSError as exc:
        errors.append(f"{path.relative_to(ROOT)}: {exc}")
        continue
    for token in tokens:
        if token not in text:
            errors.append(f"{path.relative_to(ROOT)}: missing {token!r}")

if errors:
    print("android-media-transcoder audit: FAIL", file=sys.stderr)
    for error in errors:
        print(error, file=sys.stderr)
    raise SystemExit(1)

print("android-media-transcoder audit: PASS")
