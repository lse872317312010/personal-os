# External media boundary offline checkpoint

This checkpoint records source-level work on the secure external appearance-model media path. It does not claim a Gradle, Robolectric, Android device, or end-to-end provider run.

## Production path now established

- The native Vault remains the owner of decrypted media. Photo bytes and model credentials do not cross Flutter.
- Vault-backed model media is exposed through a native-only `NativeExactLengthMediaStream`. The exact plaintext length comes from the already-owned decrypted `ByteArray`; no second media scan or plaintext copy is required.
- `CredentialedNativeAppearanceModelTransport` now runs a metadata-only `preflightBeforeCredentialUse(...)` hook before consuming the one-call credential.
- `StructuredExternalAppearanceModelTransport` uses that hook to reject known media larger than 15 MiB with `model.media_too_large` before provider client invocation and before consuming the credential.
- The existing `CompleteBoundedInputStream` remains a defense-in-depth fallback for streams without exact native length metadata. Its overflow now also maps to `model.media_too_large` instead of `model.invalid_request`.
- The production Vault path therefore gives the secure UI a concrete basis for the "not sent" statement on known oversize media, while the fallback stream bound remains conservative for non-Vault/direct test callers.
- `AppController` refreshes native model capabilities in `finally` after every external attempt. A local size-preflight rejection therefore keeps the credential-ready UI state, while a real provider attempt reflects the consumed one-call credential.

## HEIF / AVIF compatibility layer

- JPEG, PNG, and WebP remain streaming passthrough formats.
- HEIF and AVIF use an Android-only bounded in-memory transcode path before the provider client:
  - encoded input: <= 15 MiB
  - JPEG output: <= 15 MiB
  - decoded pixels: <= 12,000,000
  - maximum edge: <= 4096 px
  - JPEG quality: 92
- HEIF fails before reading media on Android API < 26; AVIF fails before reading media on API < 31.
- ImageDecoder requests a software mutable bitmap; the BitmapFactory fallback sets `inMutable=true`.
- An unexpected immutable decoded bitmap fails closed.
- Decoded pixels are overwritten with zero via `eraseColor(0)` before recycling.
- Encoded input, JPEG output, owned stream buffers, and transcode backing buffers are explicitly zeroized where the platform exposes writable storage.
- Decoder code catches recoverable `Exception` failures but deliberately does not swallow VM-fatal `Throwable` values such as `OutOfMemoryError`.

## Stable failure semantics

- `model.media_too_large`: media exceeded the bounded processing/send contract.
- `model.media_transcode_unavailable`: the platform cannot safely decode/re-encode the selected HEIF/AVIF media.
- Native `PlatformException` codes are first restricted by the MethodChannel gateway to a fixed set of redacted model codes.
- `model_gateway_api` now owns `AppearanceModelGatewayFailure` and the enumerated `AppearanceModelGatewayFailureCode` set. Unknown codes are sanitized to `model.adapter_unavailable` rather than crossing the application boundary.
- `AnalyzeAppearanceUseCase` preserves only `AppearanceModelGatewayFailure` codes. Arbitrary adapter exceptions are still collapsed to `analysis_failed`, so provider text, paths, credentials, and raw diagnostics remain blocked.
- This closes an earlier application-layer gap where `model.media_too_large` and `model.media_transcode_unavailable` were correctly produced by native/Flutter gateway code but then swallowed by the use case into generic `analysis_failed`, making the dedicated secure UI messages unreachable.
- Secure UI distinguishes pre-provider failures from HTTP/provider failures, where a failed response cannot prove that no bytes reached the provider.
- The external-send confirmation text now matches credential lifecycle: a credential is cleared once the actual model call begins, but remains ready when a local preflight rejects the media before credential consumption.

## Regression coverage added

- Pure JVM source tests cover streaming passthrough, media bounds, dimension math, SDK codec gates, and OpenAI HTTP framing.
- `StructuredExternalAppearanceModelTransportTest` now proves that known oversize Vault media:
  - returns `MEDIA_TOO_LARGE`,
  - never calls the external client,
  - leaves the one-call credential ready,
  - still zeroizes the owned media buffer.
- `NativeBlobSourceContractTest` proves the Vault-owned model stream exposes exact native length and zeroizes its backing bytes after success/failure.
- Robolectric source tests cover the decode/downscale/JPEG wrapper mechanics and old-SDK fail-before-read behavior.
- Android instrumentation source includes an in-house generated 337-byte 8-bit YUV420 AVIF fixture on API 31+ and verifies the production wrapper reaches the delegate as an 8x6 JPEG.
- `MethodChannelAppearanceAnalysisGatewayTest` proves enumerated native media failures survive as redacted shared gateway failures while arbitrary platform error details remain hidden.
- `model_gateway_failure_passthrough_test.dart` proves the application use case preserves a stable `model.media_too_large` code, redacts arbitrary adapter failures to `analysis_failed`, and sanitizes unknown gateway failure codes.
- `tool/android_mvp/run_media_codec_device_tests.sh` runs only the focused codec instrumentation class on exactly one attached device/emulator.
- `tool/check_android_media_transcoder.py` statically locks codec gates, pixel erasure, fatal-error policy, exact-length Vault metadata, pre-credential size gating, capability refresh, credential retention, the device fixture, and the focused runner.
- `tool/check_model_failure_passthrough.py` statically locks the redacted failure chain from gateway API through MethodChannel, application use case, controller, and secure UI.

## Verification status

- A minimal isolated `kotlinc` compile using Android/API stubs passed for the new transcode source shape. This is only a Kotlin syntax/interface sanity check and is not an Android build.
- Full Android Gradle/JVM tests: not run in the current execution environment.
- Dart/Flutter tests for the new gateway/use-case failure contract: source added, not run in the current execution environment.
- Robolectric tests: source added, not run in the current execution environment.
- Real AVIF instrumentation test: source and in-house fixture added, not run on a device yet.
- Real HEIF fixture: not added because the available local libheif installation has no HEVC encoder plugin; no third-party binary fixture with unclear provenance was imported.
- Orientation metadata regression: not added because the available ffmpeg AVIF path either rotates pixels or drops the intended transform metadata, so it cannot produce a trustworthy orientation fixture here.

## Next concentrated milestone

1. Run repository contracts plus Dart/Flutter, Android JVM, and Robolectric suites under the integration toolchain.
2. Fix compile/test failures without broadening scope.
3. Run `tool/android_mvp/run_media_codec_device_tests.sh` on an API 31+ device/emulator when a device-capable environment is available.
4. Add real HEIF/orientation coverage only from a reproducible, provenance-safe fixture path.
5. Assemble one dogfood APK from the verified branch.
6. At this point one concentrated GitHub Actions run is justified because the current execution environment lacks Flutter/Android SDK tooling and the branch has reached an integration checkpoint.
