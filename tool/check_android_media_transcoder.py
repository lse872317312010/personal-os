#!/usr/bin/env python3
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parent.parent
TRANSCODER = ROOT / "apps/personal_os_app/android/app/src/main/kotlin/com/personalos/app/model/AndroidExternalMediaTranscoder.kt"
TRANSPORT = ROOT / "apps/personal_os_app/android/app/src/main/kotlin/com/personalos/app/model/StructuredExternalAppearanceModelTransport.kt"
CREDENTIAL = ROOT / "apps/personal_os_app/android/app/src/main/kotlin/com/personalos/app/model/NativeModelCredential.kt"
MEDIA_ACCESS = ROOT / "apps/personal_os_app/android/app/src/main/kotlin/com/personalos/app/security/NativeModelMediaAccess.kt"
MODEL = ROOT / "apps/personal_os_app/android/app/src/main/kotlin/com/personalos/app/model/NativeAppearanceModel.kt"
MAIN = ROOT / "apps/personal_os_app/android/app/src/main/kotlin/com/personalos/app/MainActivity.kt"
GATEWAY = ROOT / "apps/personal_os_app/lib/src/composition/method_channel_appearance_analysis_gateway.dart"
CONTROLLER = ROOT / "apps/personal_os_app/lib/src/controller/app_controller.dart"
CAPTURE_SCREEN = ROOT / "apps/personal_os_app/lib/src/screens/capture_screen.dart"
BUILD = ROOT / "apps/personal_os_app/android/app/build.gradle.kts"
TEST = ROOT / "apps/personal_os_app/android/app/src/test/kotlin/com/personalos/app/model/AndroidExternalMediaTranscoderTest.kt"
TRANSPORT_TEST = ROOT / "apps/personal_os_app/android/app/src/test/kotlin/com/personalos/app/model/StructuredExternalAppearanceModelTransportTest.kt"
MEDIA_ACCESS_TEST = ROOT / "apps/personal_os_app/android/app/src/test/kotlin/com/personalos/app/security/NativeBlobSourceContractTest.kt"
ROBOLECTRIC_TEST = ROOT / "apps/personal_os_app/android/app/src/test/kotlin/com/personalos/app/model/AndroidExternalMediaTranscoderRobolectricTest.kt"
DEVICE_TEST = ROOT / "apps/personal_os_app/android/app/src/androidTest/kotlin/com/personalos/app/model/AndroidExternalMediaTranscoderDeviceTest.kt"
DEVICE_RUNNER = ROOT / "tool/android_mvp/run_media_codec_device_tests.sh"

checks = {
    TRANSCODER: (
        'setOf("image/heif", "image/avif")',
        'MAXIMUM_ENCODED_INPUT_BYTES = 15 * 1024 * 1024',
        'MAXIMUM_DECODED_PIXELS = 12_000_000L',
        'MAXIMUM_EDGE_PIXELS = 4_096',
        'private val platformSdkInt: Int = Build.VERSION.SDK_INT',
        'platformCanDecodeTranscodedMedia(request.mediaType, platformSdkInt)',
        '"image/heif" -> sdkInt >= Build.VERSION_CODES.O',
        '"image/avif" -> sdkInt >= Build.VERSION_CODES.S',
        'request.copy(mediaType = "image/jpeg")',
        'decoder.setMutableRequired(true)',
        'inMutable = true',
        'if (!bitmap.isMutable)',
        'bitmap.eraseColor(0)',
        'bitmap.recycle()',
        'buf.fill(0)',
        'catch (_: Exception)',
        'MediaLimitExceededIOException',
        'NativeAppearanceModelFailureCode.MEDIA_TOO_LARGE',
        'NativeAppearanceModelFailureCode.MEDIA_TRANSCODE_UNAVAILABLE',
    ),
    TRANSPORT: (
        'import com.personalos.app.security.NativeExactLengthMediaStream',
        'override fun preflightBeforeCredentialUse(',
        '(media as? NativeExactLengthMediaStream)?.exactLengthBytes',
        'exactLength > maximumMediaBytes',
        'class CompleteBoundedInputStream(',
        'if (consumed == maximumBytes)',
        'NativeAppearanceModelFailureCode.MEDIA_TOO_LARGE',
    ),
    CREDENTIAL: (
        'preflightBeforeCredentialUse(request, media)',
        'return credentials.useCredential',
        'protected open fun preflightBeforeCredentialUse(',
        'Metadata-only, synchronous validation before consuming the one-call credential.',
    ),
    MEDIA_ACCESS: (
        'NativeExactLengthMediaStream',
        'exactLengthBytes',
        'OwnedBlobInputStream',
        'ownedBytes.size.toLong()',
        'OwnedBlobInputStream(ownedBytes).use',
        'ownedBytes.fill(0)',
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
    CONTROLLER: (
        'final usedExternalCredential =',
        '_processingBoundary == AppearanceProcessingBoundary.externalProcessor;',
        'if (usedExternalCredential &&',
        'await _refreshModelCapabilities();',
    ),
    CAPTURE_SCREEN: (
        "'model.media_too_large'",
        "'model.media_transcode_unavailable'",
        '已在设备内停止处理且未发送',
        '已在联网前停止',
    ),
    BUILD: (
        'testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"',
        'androidTestImplementation("androidx.test.ext:junit:1.3.0")',
        'androidTestImplementation("androidx.test:runner:1.7.0")',
    ),
    TEST: (
        'preservesAlreadySupportedStreamingMediaWithoutBuffering',
        'rejectsOversizeEncodedMediaBeforeDelegateOrCodec',
        'platformSdkInt = 35',
        'codecAvailabilityMatchesAndroidPlatformIntroductionLevels',
        'platformCanDecodeTranscodedMedia("image/heif", 25)',
        'platformCanDecodeTranscodedMedia("image/avif", 31)',
        'boundsLargeLandscapeByEdgeAndPixelBudget',
        'legacyDecoderUsesPowerOfTwoSampleLargeEnoughForBudget',
        'assertFalse(delegateCalled)',
    ),
    TRANSPORT_TEST: (
        'rejectsKnownOversizeVaultMediaBeforeClientCallAndKeepsCredential',
        'consumeOwnedBlobBytes',
        'assertFalse(clientCalled)',
        'assertTrue(transport.runtimeCredentialReady)',
        'rejectsUnknownLengthMediaAboveConfiguredLimitAsMediaTooLarge',
        'NativeAppearanceModelFailureCode.MEDIA_TOO_LARGE',
    ),
    MEDIA_ACCESS_TEST: (
        'modelMediaStreamExposesExactNativeLengthAndZeroesAfterSuccess',
        'stream is NativeExactLengthMediaStream',
        'exactLengthBytes',
        'assertArrayEquals(byteArrayOf(0, 0, 0), owned)',
    ),
    ROBOLECTRIC_TEST: (
        'RobolectricTestRunner',
        '@Config(sdk = [35])',
        'executesDecodeScaleEncodePipelineBeforeDelegate',
        'request("image/heif")',
        'assertEquals("image/jpeg", observedMediaType)',
        'decoded.width <= 64',
        'decoded.height <= 64',
        '@Config(sdk = [30])',
        'rejectsAvifBeforeReadingMediaWhenPlatformIsTooOld',
        '@Config(sdk = [25])',
        'rejectsHeifBeforeReadingMediaWhenPlatformIsTooOld',
        'assertFalse(media.readAttempted)',
        'assertFalse(delegateCalled)',
    ),
    DEVICE_TEST: (
        'AndroidJUnit4',
        '@SdkSuppress(minSdkVersion = 31)',
        'realAvifFixtureDecodesAndReachesDelegateAsJpeg',
        '-pix_fmt yuv420p pattern.avif',
        'AVIF_FIXTURE_BASE64',
        'assertEquals("avif", String(avif, 8, 4, Charsets.US_ASCII))',
        'assertEquals("image/jpeg", request.mediaType)',
        'assertEquals(8, decoded.width)',
        'assertEquals(6, decoded.height)',
        "credential.fill('\\u0000')",
        'avif.fill(0)',
    ),
    DEVICE_RUNNER: (
        'connectedDebugAndroidTest',
        'AndroidExternalMediaTranscoderDeviceTest',
        'android.testInstrumentationRunnerArguments.class',
        'No authorized Android device or emulator is connected.',
        'Multiple Android devices are connected',
    ),
}

forbidden = {
    TRANSCODER: (
        'catch (_: Throwable)',
        'catch (failure: Throwable)',
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
    for token in forbidden.get(path, ()):
        if token in text:
            errors.append(f"{path.relative_to(ROOT)}: forbidden {token!r}")

if errors:
    print("android-media-transcoder audit: FAIL", file=sys.stderr)
    for error in errors:
        print(error, file=sys.stderr)
    raise SystemExit(1)

print("android-media-transcoder audit: PASS")
