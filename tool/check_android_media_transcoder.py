#!/usr/bin/env python3
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parent.parent
TRANSCODER = ROOT / "apps/personal_os_app/android/app/src/main/kotlin/com/personalos/app/model/AndroidExternalMediaTranscoder.kt"
MODEL = ROOT / "apps/personal_os_app/android/app/src/main/kotlin/com/personalos/app/model/NativeAppearanceModel.kt"
MAIN = ROOT / "apps/personal_os_app/android/app/src/main/kotlin/com/personalos/app/MainActivity.kt"
GATEWAY = ROOT / "apps/personal_os_app/lib/src/composition/method_channel_appearance_analysis_gateway.dart"
CAPTURE_SCREEN = ROOT / "apps/personal_os_app/lib/src/screens/capture_screen.dart"
TEST = ROOT / "apps/personal_os_app/android/app/src/test/kotlin/com/personalos/app/model/AndroidExternalMediaTranscoderTest.kt"
ROBOLECTRIC_TEST = ROOT / "apps/personal_os_app/android/app/src/test/kotlin/com/personalos/app/model/AndroidExternalMediaTranscoderRobolectricTest.kt"

checks = {
    TRANSCODER: (
        'setOf("image/heif", "image/avif")',
        'MAXIMUM_ENCODED_INPUT_BYTES = 15 * 1024 * 1024',
        'MAXIMUM_DECODED_PIXELS = 12_000_000L',
        'MAXIMUM_EDGE_PIXELS = 4_096',
        'request.copy(mediaType = "image/jpeg")',
        'bitmap.recycle()',
        'buf.fill(0)',
        'MediaLimitExceededIOException',
        'NativeAppearanceModelFailureCode.MEDIA_TOO_LARGE',
        'NativeAppearanceModelFailureCode.MEDIA_TRANSCODE_UNAVAILABLE',
    ),
    MODEL: (
        'MEDIA_TOO_LARGE("model.media_too_large")',
        'MEDIA_TRANSCODE_UNAVAILABLE("model.media_transcode_unavailable")',
    ),
    MAIN: ('TranscodingExternalAppearanceModelClient(',),
    GATEWAY: (
        "'model.media_too_large'",
        "'model.media_transcode_unavailable'",
    ),
    CAPTURE_SCREEN: (
        "'model.media_too_large'",
        "'model.media_transcode_unavailable'",
        '已在设备内停止处理且未发送',
        '已在联网前停止',
    ),
    TEST: (
        'preservesAlreadySupportedStreamingMediaWithoutBuffering',
        'rejectsOversizeEncodedMediaBeforeDelegateOrCodec',
        'boundsLargeLandscapeByEdgeAndPixelBudget',
        'legacyDecoderUsesPowerOfTwoSampleLargeEnoughForBudget',
        'assertFalse(delegateCalled)',
    ),
    ROBOLECTRIC_TEST: (
        'RobolectricTestRunner',
        '@Config(sdk = [35])',
        'executesDecodeScaleEncodePipelineBeforeDelegate',
        'request("image/heif")',
        'assertEquals("image/jpeg", observedMediaType)',
        'decoded.width <= 64',
        'decoded.height <= 64',
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
