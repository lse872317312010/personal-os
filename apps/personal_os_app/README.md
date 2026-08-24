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
- fail-before-model checks for locked Vault, missing consent, and non-`blob://`
  inputs;
- shared `FixtureAppearanceAnalysisGateway.syntheticSuccess` behavior for
  reviewing the full UI flow. Its conclusions and actions are explicitly
  synthetic and are not defined by the UI app.
- real task completion/skip and review create/accept/reject commands through
  `ActionFeedbackUseCase`, sharing the analysis event store;
- stable success/failure codes rendered by Task and Review screens.

The capture UI accepts a `blob://` reference. It does not request file bytes,
open a filesystem path, call SQLite, or persist an original photograph. A later
Vault adapter owns encrypted blob ingestion and returns the reference.

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
7. `adapters/model_fixture` is a deterministic demo/test adapter. It does not
   open the blob, inspect a person, or provide production AI analysis.

The composition root exposes `AppExperienceMode`. Android uses `secureVault` at
runtime; `syntheticDemo` remains available through an explicit factory for
tests/previews and for platforms without an equivalent secure adapter. The
secure path must still pass compilation, integration, and device evidence gates
before being treated as production-ready. This app does not claim Redmi,
GitHub Actions, or SQLCipher production verification.

## Android MVP build and Redmi Turbo install

The checked-in Android host contains its Gradle settings, application module,
Kotlin activity, themes, and a restrictive manifest. It intentionally declares
no internet, camera, microphone, location, contacts, or shared-storage
permission. Android backup and cleartext traffic are disabled.

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

## Verification status

Flutter, Dart, and Android SDK/Gradle tooling were unavailable in the authoring
environment. The files and dependency directions were statically reviewed, but
`flutter pub get`, `flutter analyze`, tests, APK assembly, Redmi Turbo
installation, biometric unlock, SQLCipher production behavior, crash/cold-start
recovery, and camera/photo-picker integration are **not verified**.

When a Flutter SDK is available, use the scripts above or run:

```sh
cd apps/personal_os_app
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

