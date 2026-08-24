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
requests no media/storage permission. The selected `Uri` stays native. Dart
receives a short-lived opaque token; consuming it streams through the native
Vault blob sink and returns only an opaque `blob://...` reference. The Dart
application then records the observation and calls the existing analysis use
case with that reference.

The source contract reports `photoPicker: true` and `camera: false` in the
current Android implementation. `capturePhoto` is deliberately unavailable;
there is no CameraX/FileProvider path. Native token lifetime, resolver access,
blob writing, deletion, and channel failures are fail-closed by stable codes,
but none of this has been compiled or exercised on a device in this workspace.

## Channel contract

`MainActivity` registers the private Flutter `MethodChannel`
`personal_os/internal/android_vault`. The supported method names are:

- `inspectCapabilities`
- `authenticate`
- `openVault`
- `appendEvents`
- `readEventsByProfile`
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
- `readEventsBySubject`: looks up the native subject index and returns the same
  complete `eventJson` rows. Dart performs the strict envelope decode and exact
  revision filtering.
- `readEventById`: returns one complete `eventJson` row or null.
- `closeVault`: closes the SQLCipher handle and invalidates the session.

The native table is intentionally a small stable bridge contract for the Dart
adapter. Schema version 2 stores complete envelopes and subject indexes. The
older split-column table is rejected; no lossy migration is attempted.

## Deliberate limitations

- Device credential fallback is intentionally unavailable before Android 11;
  AndroidX does not support a crypto-object prompt with that authenticator on
  earlier platform versions. Biometric-only authentication can use
  `BIOMETRIC_STRONG` where the platform reports it available.
- SQLCipher for Android Community Edition is declared as
  `net.zetetic:sqlcipher-android:4.18.0` with `androidx.sqlite:sqlite:2.7.0`.
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
- Keystore hardware backing, StrongBox, Redmi-device behavior, migration from
  any pre-existing plaintext file, rekey, deletion, export, and real-device
  evidence are unverified.
- Channel errors return only stable codes and fixed safe messages; `details` is
  always null. Raw exceptions, paths, aliases, and stack traces never cross
  the channel. Event-content conflicts use only the fixed conflict code and
  message; event IDs and JSON are never included in channel error details.

The native vault and controlled-source implementations must remain compatible
with their Dart contracts. Their presence in the Android composition is an
implementation claim only; it is not SQLCipher, Photo Picker, Redmi, or
production verification.
