# Android native vault boundary

This directory contains the Android-side secure local vault boundary.

## Verification status

The current environment has no Android SDK or Gradle installation, so this
change has not been compiled or run on an emulator/device. The code below has
only received static review in this workspace; no build or test pass is being
claimed.

## B1-06 static review (2026-08-24)

The review covered `NativeVaultChannel`, `NativeVaultDatabase`,
`KeystoreTicketCodec`, and `OpaqueVaultSessionRegistry`. No definite code
defect was found that justified a source change. The reviewed invariants are:

- authentication tickets are process-local, short-lived, and consumed before
  opening a vault; failed opens do not leave a reusable ticket;
- session expiry, explicit close, and channel teardown close native database
  handles; database operations are serialized and the database itself is
  synchronized;
- SQLCipher loading, cipher version, foreign keys, WAL, and the exact schema
  are required; missing or incompatible prerequisites fail closed;
- append batches are transactional, event retries are idempotent only when the
  complete event JSON matches, and divergent reuse returns a stable conflict;
- channel failures expose only fixed wire codes and safe messages.

No Android SDK, Gradle, Kotlin compiler, emulator, or device was available in
this workspace. Therefore this review did not claim JVM/Kotlin compilation,
SQLCipher runtime behavior, Keystore behavior, migration execution, or Redmi
device evidence.

## Controlled source channel

`MainActivity` also registers `personal_os/internal/controlled_source`. Its
Photo Picker capability uses Android's system `PickVisualMedia` contract and
requests no media/storage permission. Camera capture is wired separately and
requests `android.permission.CAMERA` explicitly at capture time. The native
capture allocates an app-private cache file under `camera_capture`, exposes it
to the camera through the non-exported Android `FileProvider`, and keeps the
`Uri`, file, and bytes native. Dart receives only a short-lived opaque source
token; consuming it streams through the native Vault blob sink and returns only
an opaque `blob://...` reference. The Dart application then records the
observation and calls the existing analysis use case with that reference.

The source contract reports `photoPicker: true` and `camera: true` in the
current Android implementation. `capturePhoto` requests permission before
launching the camera, and cancellation, denial, failed capture, invalid session,
token release/expiry, and channel teardown clean up the cache file. If cache
cleanup fails after native blob ingestion, the stored blob is deleted as a
rollback and a stable failure code is returned. These are implementation claims;
none has been compiled or exercised on an Android runtime, Redmi device, or
production environment here.

## Channel contract

`MainActivity` registers the private Flutter `MethodChannel`
`personal_os/internal/android_vault`. The supported method names are:

- `inspectCapabilities`
- `authenticate`
- `openVault`
- `appendEvents`
- `readEventsByProfile`
- `readEventsByProfilePage`
- `readEventsBySubject`
- `readEventById`
- `closeVault`

`authenticate` uses AndroidX `BiometricPrompt` with
`BIOMETRIC_STRONG`, optionally combined with `DEVICE_CREDENTIAL` on Android
11/API 30 and later. The prompt receives a Keystore-backed HMAC `Mac` as its
`CryptoObject`; only `onAuthenticationSucceeded` can use that Mac to issue a
short-lived opaque ticket and derive the SQLCipher database key. Authentication
is asynchronous and the native channel completes its Flutter callback from the
prompt callback.

The ticket id contains only a version, random nonce, and HMAC tag. It contains
no key bytes, database path, native alias, or exception text. The Android
Keystore key is user-authenticated for every HMAC operation and remains private
to `KeystoreTicketCodec`. Session identifiers are opaque and scoped to the
process.

The `authenticate` response returns `id` and `expiresAt` (Unix epoch
milliseconds). The ticket is single-use, process-local, and expires after five
minutes. `openVault` accepts only a ticket issued by the same native process
with the matching expiry, opens the app-private SQLCipher database, and returns
only an opaque session id. A process restart cannot reopen an old ticket.

The minimal native storage methods are:

- `appendEvents`: accepts one `sessionId` and an ordered batch of records with
  `profileId`, `eventId`, complete `eventJson`, and subject-reference index
  values; the entire batch is one native transaction. Repeating an existing
  `eventId` with identical complete `eventJson` is a no-op. Reusing an
  `eventId` with different `eventJson` fails with the stable native code
  `security.vault_event_conflict`; the batch is rolled back atomically.
- `readEventsByProfile`: accepts `sessionId`, `profileId`, and an optional
  `limit` (1–1000, default 100); it returns ordered rows containing the
  complete opaque `eventJson`.
- `readEventsByProfilePage`: accepts an exclusive `afterSequence` cursor and
  returns the next ordered page. Dart repeats this call until a short page and
  rejects cursor regression or duplicate event IDs; backup must use this path
  so histories above 1000 events cannot be silently truncated.
- `readEventsBySubject`: looks up the native subject index and returns the same
  complete `eventJson` rows. Dart performs the strict envelope decode and exact
  revision filtering.
- `readEventById`: returns one complete `eventJson` row or null.
- `closeVault`: closes the SQLCipher handle and invalidates the session.

The native table is intentionally a small stable bridge contract for the Dart
adapter. Schema version 2 stores complete envelopes and subject indexes. The
older split-column table is rejected; no lossy migration is attempted.

`MainActivity` also registers `personal_os/internal/appearance_model`. A model
adapter advertises its processing boundary and reads runtime credential
readiness directly from its credential provider. The channel does not accept a
separate readiness flag, so capability discovery cannot claim external
processing is ready after a one-call credential has been consumed. Requests are
rejected before Vault media access when the configured external adapter has no
live credential. The production ephemeral provider takes ownership of a native
`CharArray`; successful use, failed use, replacement, explicit clearing, and
channel teardown all zeroize it. A concrete HTTP stack may still require a
short-lived immutable authorization-header `String`; such copies must remain
inside the provider call, must never be logged or persisted, and must be
released with the connection.

The provider-neutral external transport passes only bounded request metadata,
the native media stream, and the one-call credential to a provider client. The
client must synchronously consume the complete stream. The transport enforces a
15 MiB ceiling, disables skip/reset semantics, rejects partial consumption, and
accepts only the exact structured result schema with bounded collections. Raw
HTTP bodies, provider-specific fields, and provider exceptions are not allowed
to cross this boundary.

The first concrete client uses the OpenAI Responses API. Dogfood APKs produced
by `tool/android_mvp/build_debug.sh` include the adapter and currently pin
`gpt-5.4-mini`; ad-hoc Gradle builds remain disabled unless enabled with
`-PpersonalOsOpenAiEnabled=true -PpersonalOsOpenAiModel=<model-id>`. The API key
is never a Gradle property, BuildConfig value, repository value, or Flutter
value; the user enters it into the native one-call credential dialog. The
client accepts only `https://api.openai.com/v1/responses`, disables redirects,
sets connect/read timeouts, streams the encrypted-Vault image as Base64 without
building a complete plaintext image copy, requests `store=false`, caps response
bytes, and rejects non-JSON, refusal, incomplete, or schema-invalid responses.
OpenAI currently receives only validated JPEG, PNG, or WebP media. The generic
transport can identify HEIF and AVIF, but this client rejects them before
opening a connection; native private-memory transcoding remains a separate
milestone.

Provider cancellation is part of the native boundary. Explicit credential
clearing, Vault session invalidation, and channel teardown disconnect an active
request in addition to clearing any unused credential. Cancellation is
best-effort at the platform socket boundary; the 45-second network timeout
remains the final upper bound.

Before invoking a provider, the transport validates a zeroized 16-byte media
signature and derives a trusted MIME type for JPEG, PNG, WebP, HEIF, or AVIF.
Unknown and empty media are rejected before the client is called. Signature
validation is an input boundary check, not a claim that the complete image has
already been decoded successfully.

External requests currently allow only the native `appearance-v1` prompt
contract and `appearance-result-v1` response schema. The fixed system contract
separates observable facts from uncertain inference, forbids identity,
protected-trait, diagnosis, and intent inference, and bounds actions to seven
days. Unsupported prompt versions are rejected before Vault media or the
one-call credential is accessed. A 45-second call budget is passed to the
provider client; the concrete network client must enforce it synchronously in
its own connect/read timeout configuration.

Runtime credentials are entered in an Android-native password dialog and never
become a Flutter value. The dialog limits input to 512 characters, disables
personalized keyboard learning and autofill, rejects obscured touches, and sets
`FLAG_SECURE`. Flutter receives only accepted/cancelled state. Replacement,
explicit clear, model use, Vault lock, session invalidation, channel teardown,
and failed acknowledgement all clear the owned native credential.

## Deliberate limitations

- Device credential fallback is intentionally unavailable before Android 11;
  AndroidX does not support a crypto-object prompt with that authenticator on
  earlier platform versions. Biometric-only authentication can use
  `BIOMETRIC_STRONG` where the platform reports it available.
- SQLCipher for Android Community Edition is declared as
  `net.zetetic:sqlcipher-android:4.17.0` with `androidx.sqlite:sqlite:2.7.0`.
  Native loading, `PRAGMA cipher_version`, foreign keys, WAL, and the
  app-private database open must all succeed or the operation fails closed.
- There is no plaintext SQLite fallback and no in-memory replacement for the
  vault.
- The derived database key is a Kotlin-only `ByteArray`; it is wiped after
  SQLCipher open, on ticket expiry/teardown, and on open failure. The session
  registry never stores it, and it never enters a MethodChannel result.
- Session expiry is scheduled natively and closes the database handle. Channel
  teardown and `MainActivity.onDestroy` cancel prompts, wipe pending ticket
  keys, close all database handles, and stop worker executors.
- Keystore hardware backing, StrongBox, Camera/Photo Picker runtime behavior,
  Redmi-device behavior, migration from any pre-existing plaintext file, rekey,
  deletion, encrypted-backup behavior, real-model behavior, and real-device
  evidence are unverified.
- Channel errors return only stable codes and fixed safe messages; `details` is
  always null. Raw exceptions, paths, aliases, and stack traces never cross
  the channel. Event-content conflicts use only the fixed conflict code and
  message; event IDs and JSON are never included in channel error details.

## Encrypted event backup

`MainActivity` registers `personal_os/internal/event_backup` for portable
event-history backup and restore. Export reads the complete profile history via
the paged Vault API, applies the D3 export ceiling and forbidden-field policy,
then creates the deterministic `personal-os.events` archive. The Android
adapter prompts for a passphrase in a `FLAG_SECURE` native dialog, derives a
256-bit key with PBKDF2-HMAC-SHA256 (210,000 iterations and a random 16-byte
salt), and authenticates/encrypts the archive with AES-256-GCM and a random
12-byte nonce. Only the encrypted `.posb` envelope is written through
Android's system document picker.

Import selects a document through the system picker, obtains the passphrase in
native UI, bounds the encrypted input to 16 MiB plus envelope overhead, and
authenticates before returning the in-memory archive to the Dart restore
service. The restore service verifies the archive format, event count,
checksum, duplicate IDs, and every event envelope before one atomic Vault
append. Existing identical events remain idempotent; any divergent event ID
conflict rolls back the complete restore. A successful restore locks the Vault,
clears volatile controllers, and requires a new authenticated unlock so all
views replay the restored history.

Passphrase character arrays, derived key bytes, plaintext byte arrays, and
ciphertext work buffers are cleared on success, failure, cancellation, Vault
invalidation, and channel teardown where the platform representation permits.
The passphrase never enters a MethodChannel, Flutter value, file name, log, or
persistent store. Cancellation and failures cross Flutter only as fixed status
or stable `backup.*` codes without paths or exception text.

The native vault and controlled-source implementations must remain compatible
with their Dart contracts. Their presence in the Android composition is an
implementation claim only; it is not Android compile/runtime, SQLCipher,
Camera/Photo Picker, Redmi, real-model, or production verification.
