# Web preview

This is a browser-test surface for the existing Flutter UI and platform-neutral Dart application core. It is not a production Personal OS Vault.

## Run locally

```sh
cd apps/personal_os_app
flutter pub get
flutter run -d chrome --target lib/main_web_preview.dart
```

The preview uses `AppComposition.inMemoryDemo()`. It has no secure-storage adapter, server persistence, real photo input, or real model. Data exists only in memory and disappears when the tab is refreshed or closed. Use synthetic values only.

## Verify

```sh
cd apps/personal_os_app
flutter test
flutter test --platform chrome test/mvp_journey_test.dart
flutter build web --release --base-href /personal-os/ --target lib/main_web_preview.dart
```

The Chrome test exercises the same synthetic UI flow used by the preview. The Pages workflow publishes only the static build after the Chrome tests pass on `main`.

## Boundary

`lib/main.dart` remains the Android-authoritative entrypoint. Its production composition fails closed on platforms without a trusted secure adapter. The web preview does not claim Android Keystore, SQLCipher, photo-picker/camera permission, Android process-death, reboot, HyperOS battery, or encrypted backup behavior. Those remain part of the exact-APK Redmi G3 gate.
