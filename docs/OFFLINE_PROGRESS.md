# Offline progress baseline

This file records work performed locally while GitHub Actions are unavailable.
It is evidence of local implementation only, not CI or device verification.

## Upstream baseline

- Upstream commit: `8eda400471e51a3137ddde3160073db402e2da5d`
- Last verified rolling Android artifact: `android-latest`
- APK SHA-256: `4ebcc8df0d1285294bda887db6b4dd4a256be713ee61064ca75e15b3616ae580`

## Locally integrated

- Android Vault lifecycle hardening and JVM tests from PR #66.
- Redmi dogfood runbook, evidence validator, preflight, and integration test
  assets from PR #68.
- Fixed the dogfood asset verifier so its documented cold-start limitation is
  checked against text that actually exists in the Chinese runbook.
- Extended the provider-neutral appearance model contract with prompt/model
  audit metadata, observable versus inferred findings, bounded seven-day
  actions, stable risk codes, and human-confirmation codes.
- Persist only stable risk/confirmation codes. Risk statements and confirmation
  prompts remain outside the event log.
- Reject a model response when its prompt version does not match the request.
- Added a native-only model media port guarded by the active Vault session;
  decrypted photo bytes do not cross Flutter.
- Added a provider-neutral native model transport/coordinator contract with
  bounded structured output and stable redacted failures.
- Zeroize the full-image ingestion buffer, the 32 KiB read buffer, the backing
  output buffer, and model-read buffers on both success and failure.
- Added a strict asynchronous native/Flutter MethodChannel codec with bounded
  result collections and stable redacted errors. The default secure transport
  is unavailable and fails before opening the encrypted photo.
- Added an explicit processing boundary. External processing requires a second,
  distinct, revision-pinned `external_processing / portrait / transmit / D3`
  consent before the model or Blob reader is called.
- Consent history now projects grants independently by consent ID, so revoking
  external processing cannot revoke or overwrite local analysis consent.
- Added runtime credential ownership contracts for external transports. A
  credential is scoped to one callback and zeroed after success or failure;
  it never enters a channel value, event, exception, or log.
- Propagated multiple analysis consent references through both source-token and
  raw-byte ingestion paths.
- Fixed raw-byte ingestion compensation: a Blob is deleted only before analysis
  events commit, never after a committed event references it.
- Added redacted model capability discovery. Secure mode now rejects an
  unconfigured model before acquiring, importing, or reading a photo; fixture
  mode advertises only its on-device synthetic capability.
- Added a capability-gated external-processing switch in secure mode. The
  separate consent is persisted and revoked independently, selects the external
  boundary only while active, restores from the event read model after a local
  restart, and remains visible for revocation if provider capability later
  disappears.
- Added controller regressions proving an external-only provider is rejected
  before model access without the second consent, while an authorized external
  request carries both revision-pinned consent references.
- Replaced the native model channel's manually supplied credential-ready flag
  with live adapter metadata. External capability now follows the one-call
  credential provider and fails before Vault media access after consumption.
- Added a process-memory-only credential provider with ownership transfer,
  single-use consumption, and zeroization on success, failure, replacement,
  explicit clearing, and native channel teardown.
- Added a provider-neutral external transport with a 15 MiB media ceiling,
  complete-stream consumption enforcement, strict structured response parsing,
  bounded collections, and rejection of raw provider-specific response fields.
- Added native media-signature validation and trusted MIME derivation for JPEG,
  PNG, WebP, HEIF, and AVIF. The 16-byte inspection buffers are zeroized, and
  empty or unknown media are rejected before provider invocation.
- Added a fixed `appearance-v1` native prompt contract and
  `appearance-result-v1` response contract. Unsupported versions fail before
  Blob or credential access; provider clients receive a synchronous 45-second
  call budget without moving credentials onto an unmanaged timeout thread.
- Split external transport configuration from runtime credential readiness in
  the capability projection. Secure UI now explains whether no model exists,
  an external transport lacks its one-call credential, or a usable model is
  ready, without exposing provider details.
- Added an Android-native runtime credential prompt and configure/clear channel
  methods. Credential characters never cross Flutter; the UI receives only
  accepted/cancelled state. Vault lock, session invalidation, use, replacement,
  explicit clear, and channel teardown all trigger native zeroization.
- Refresh external capability after every one-call analysis so UI state cannot
  continue claiming that a consumed credential is ready.
- Corrected the Android boundary README to match the locally pinned SQLCipher
  `4.17.0` dependency.
- Added the first concrete external provider client for the OpenAI Responses
  API. It is explicitly build-gated and disabled by default, accepts no build-
  time credential, fixes the HTTPS endpoint to the official host, disables
  redirects and storage, streams Base64 media, bounds time and response bytes,
  and converts only a completed strict-schema response into the provider-neutral
  result.
- Restricted the OpenAI client itself to JPEG, PNG, and WebP. HEIF/AVIF now pass
  through an Android-only compatibility wrapper that performs bounded in-memory
  decode/downscale/re-encode to JPEG before the provider client is invoked. No
  plaintext temporary file is used.
- Bound HEIF/AVIF preprocessing to 15 MiB encoded input, 12 million decoded
  pixels, a 4096-pixel maximum edge, and 15 MiB JPEG output. Sensitive encoded
  and JPEG byte arrays plus owned output buffers are explicitly cleared.
- Require decoded HEIF/AVIF Bitmaps to be mutable. ImageDecoder requests a
  software mutable bitmap and the BitmapFactory fallback sets `inMutable`; an
  unexpected immutable bitmap fails closed. Successful and failed provider calls
  overwrite decoded pixels with zero before the bitmap is recycled.
- Added stable `model.media_too_large` and
  `model.media_transcode_unavailable` failures. They are preserved through the
  native channel and Flutter gateway, and secure UI explicitly states that these
  preprocessing failures occur before provider transmission.
- Added platform fail-fast gates before sensitive media is read: HEIF requires
  Android 8.0 / API 26 or newer, and AVIF requires Android 12 / API 31 or newer.
  Unsupported platforms return the stable transcode-unavailable error without
  consuming the media stream or invoking the provider delegate.
- Added pure JVM regressions for provider HTTP framing, media size/dimension
  bounds, codec SDK thresholds, and streaming passthrough. Added Robolectric
  regressions for the Android decode/downscale/JPEG pipeline and for proving old
  platforms reject AVIF/HEIF before any InputStream read or provider call.
- The Robolectric pipeline test intentionally uses generated PNG bytes while
  forcing the HEIF compatibility path; it validates wrapper mechanics rather
  than claiming host-side HEIF codec coverage.
- Added a separate Android instrumentation test with an in-house generated,
  embedded 337-byte, 8-bit YUV420 AVIF fixture. On API 31+ it exercises the real
  platform AVIF decoder through the production wrapper and verifies the provider
  delegate receives an 8x6 JPEG. The fixture generation command is recorded in
  the test, avoiding external image licensing and opaque binary assets; YUV420
  is pinned in the static audit to keep the fixture on a baseline chroma path.
- Added `tool/android_mvp/run_media_codec_device_tests.sh` to run only the codec
  instrumentation class on one attached authorized device/emulator. It is not
  part of the default unit/build path and does not require a GitHub Actions run.
- Documented the unavoidable immutable authorization-header copy required by
  `HttpsURLConnection`; it remains inside the synchronous call and is neither
  persisted nor logged. The owned native credential array is still zeroized
  after every call.
- Added cancellation to the provider boundary. Explicit credential clearing,
  native Vault session invalidation, and channel teardown now disconnect an
  in-flight OpenAI request as well as zeroizing any unconsumed credential.
- Replaced Android's Base64 stream wrapper with a small provider-owned streaming
  encoder whose carry and encoded scratch buffers are explicitly zeroized. Added
  JVM regression cases for padding, mixed chunk sizes, single-byte writes, and
  non-closing delegate behavior; the tests are committed but remain unexecuted
  until a Kotlin/Gradle toolchain is available.
- Extracted OpenAI envelope validation and trusted audit-metadata injection into
  a pure Kotlin protocol layer. It rejects incomplete responses, refusals,
  duplicate output text, unknown envelope parts, and semantic attempts to inject
  reserved metadata before locally derived fields are added. Added JVM
  regression source for each rejection path.
- Added a controller-enforced, one-attempt external transmission confirmation on
  top of persisted external-processing consent. Secure UI now discloses that the
  photo and observation text leave the device, provider API charges may apply,
  and the one-call credential is cleared after success or failure. Missing fresh
  confirmation fails before source acquisition, Blob reads, observation writes,
  or model access.
- Fixed controlled-source cancellation mapping. Cancelling the Android picker is
  now reported as the stable `source_cancelled` outcome through acquisition and
  Blob-ingestion boundaries instead of being mislabeled as provider
  unavailability; analysis and ingestion remain untouched.
- Closed a processing-boundary time-of-check/time-of-use gap: model capability
  refresh now completes before the per-send confirmation is validated, and the
  controller enters its busy state immediately afterward without another await.
  A concurrent consent change therefore cannot silently turn a previously local
  attempt into an unconfirmed external transmission.

## Local verification

- `bash tool/check_contracts.sh`: last known PASS before the current media-codec
  commits; the audit source has been extended for codec gates, decoded-pixel
  erasure, device instrumentation, the YUV420 fixture, and the focused runner,
  and must be re-run at the next Android/Kotlin toolchain milestone.
- `bash tool/verify_dogfood_assets.sh`: PASS
- Evidence validator rejects the unchanged template: PASS
- Evidence validator accepts a synthetically valid `BLOCKED` record: PASS
- Dart/Flutter tests: NOT RUN (SDK unavailable in the local environment)
- Android JVM/Gradle tests: NOT RUN (Android SDK and Gradle wrapper unavailable)
- Robolectric tests: SOURCE ADDED, NOT RUN in this environment
- Real AVIF device test: SOURCE + IN-HOUSE YUV420 FIXTURE ADDED, NOT RUN
- Real HEIF fixture decode: NOT RUN; reproducible fixture source still pending
- Redmi device flow: NOT RUN

## Next local milestone

Run the contract, JVM, and Robolectric suites under an Android/Gradle toolchain,
then run `tool/android_mvp/run_media_codec_device_tests.sh` on an API 31+ device
or emulator to validate the real AVIF decoder and decoded-pixel cleanup path.
After that, add a reproducible real HEIF fixture and orientation regression,
assemble one dogfood APK, and spend a GitHub Actions run only if the concentrated
local/device milestone cannot cover the build.
