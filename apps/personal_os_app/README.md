# Personal OS mobile shell

Android-first Flutter shell for the Redmi Turbo Primary Vault. The same UI and
application composition boundaries are intended to support Windows and iOS.

## Implemented review surface

- explicit Vault lock gate; Android selects the secure composition by default,
  while the synthetic in-memory composition remains explicit for tests and
  previews;
- Home → observation capture → Claim review → Plan → Task → Review navigation;
- `AnalyzeAppearanceUseCase` wired through application ports;
- real `AppearancePolicyAdapter` authorization against an exact-revision
  `ConsentGrant`, with consent grant/revoke events overlaid by
  `EventBackedConsentRevisionRepository`;
- `InMemoryEventStore` remains the disposable synthetic-demo adapter;
- secure composition now includes native SQLCipher database/event JSON storage,
  a Dart event store, and a session coordinator; this path is implemented but
  is not compiled or runtime-verified in the current environment;
- observation history is rendered from profile-scoped stored events in the
  mobile shell;
- secure Android composition exposes a controlled system Photo Picker. The
  native side keeps the selected `Uri`, reads it into the native Vault blob
  sink, and returns only an opaque token/`BlobRef` across the channel;
- fail-before-model checks for locked Vault, missing consent, and non-`blob://`
  inputs;
- shared `FixtureAppearanceAnalysisGateway.syntheticSuccess` behavior for
  reviewing the full UI flow. Its conclusions and actions are explicitly
  synthetic and are not defined by the UI app.
- real task completion/skip and review create/accept/reject commands through
  `ActionFeedbackUseCase`, sharing the analysis event store;
- stable success/failure codes rendered by Task and Review screens.

The capture UI has two distinct paths. The legacy/reference path accepts a
manually supplied opaque `blob://` reference and never reads bytes. On Android
secure composition, the user-visible Photo Picker path is:

`Photo Picker Uri → native opaque source token → native Vault blob sink → opaque BlobRef → RecordObservation → AnalyzeAppearanceUseCase`

The Uri, stream, paths, provider metadata, and blob bytes remain native; Dart
receives only opaque values. Camera capture is also wired through an explicit
capture-time camera permission request, an app-private cache file exposed only
through Android `FileProvider`, an opaque native source token, and the native
Vault blob sink. Cancellation, permission denial, capture failure, token
release/expiry, cache cleanup failure, and post-ingest cleanup failure use
stable fail-closed outcomes; if cleanup fails after a blob is written, the
stored blob is rolled back. These are implemented contract and wiring claims,
not Android compile/runtime, Redmi, production, or real-model proof.

## Boundary rules

1. Widgets talk to `AppController`, never storage or model implementations.
2. `AppController` invokes application commands/use cases only.
3. Adapters are selected in `AppComposition`.
4. SQLite/SQLCipher and Android Keystore access belong in adapter packages, not
   this UI shell.
5. The UI consent switch writes a consent event through
   `ConsentLifecycleUseCase`; `AppearancePolicyAdapter` independently checks
   subject, actor, scope, D3 ceiling, status, revision, and validity.
6. The non-Android/demo event store is in-memory. The Android runtime
   composition persists event JSON through the native SQLCipher Vault, but
   native compilation,
   integration tests, SQLCipher production behavior, and crash/cold-start
   recovery are not verified here. Consent events in the demo prove the
   lifecycle contract only.
7. `adapters/model_fixture` is still the model gateway in the current
   composition. It is deterministic synthetic behavior; it does not open the
   blob, inspect a person, or provide production AI analysis. The native blob
   path therefore proves boundary wiring only, not real photo understanding.

The composition root exposes `AppExperienceMode`. Android uses `secureVault` at
runtime; `syntheticDemo` remains available through an explicit factory for
tests/previews and for platforms without an equivalent secure adapter. The
secure path must still pass compilation, integration, and device evidence gates
before being treated as production-ready. This app does not claim Redmi,
GitHub Actions, or SQLCipher production verification.

## Android MVP build and Redmi Turbo install

The checked-in Android host contains its Gradle settings, application module,
Kotlin activity, themes, and a restrictive manifest. It declares no internet,
microphone, location, contacts, or shared-storage permission; Camera permission
is requested explicitly only when capture starts. Camera output is staged in an
app-private cache directory exposed through `FileProvider`. Android backup and
cleartext traffic are disabled.

The Gradle wrapper launcher/JAR is generated locally from the installed Flutter
SDK template and ignored by Git. This avoids checking a generated binary into
the repository while keeping the checked-in Gradle configuration reviewable.

From Windows PowerShell:

```powershell
./tool/android_mvp/build_debug.ps1
./tool/android_mvp/install_redmi_turbo.ps1
```

From WSL/Linux/macOS:

```sh
./tool/android_mvp/build_debug.sh
./tool/android_mvp/install_redmi_turbo.sh
```

See `tool/android_mvp/README.md` for the USB-debugging and HyperOS checklist.
The scripts do not collect device IDs, logcat, bug reports, screenshots, or
phone files.

The controlled source path is not a Camera implementation and has no claim of
Redmi or production behavior until the corresponding evidence is recorded.

## Verification status

Flutter, Dart, and Android SDK/Gradle tooling were unavailable in the authoring
environment. The files and dependency directions were statically reviewed, but
`flutter pub get`, `flutter analyze`, tests, APK assembly, Redmi Turbo
installation, biometric unlock, SQLCipher production behavior, crash/cold-start
recovery, Camera/Photo Picker integration, and real-model behavior are **not
verified**.

When a Flutter SDK is available, use the scripts above or run:

```sh
cd apps/personal_os_app
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```
