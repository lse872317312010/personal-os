# Android MVP local runbook

These commands build and install the current offline demo shell. They do not
upload an APK, inspect device logs, take screenshots, or collect device IDs.

## Prerequisites

- Flutter stable with Android support and JDK 17;
- Android SDK Platform Tools (`adb`);
- Redmi Turbo with Developer options and USB debugging enabled;
- one authorized Android device, or `ANDROID_SERIAL` set locally when several
  devices are attached.

On Windows PowerShell:

```powershell
./tool/android_mvp/build_debug.ps1
./tool/android_mvp/install_redmi_turbo.ps1
```

On WSL/Linux/macOS:

```sh
./tool/android_mvp/build_debug.sh
./tool/android_mvp/install_redmi_turbo.sh
```

Each build script bootstraps only the ignored Gradle wrapper launcher and JAR
from the locally installed Flutter template. It does not replace the checked-in
Android project.

The first build normally downloads public Flutter/Gradle dependencies. Review
your network policy before running it. No application permission is granted by
the build or install scripts.

## Redmi/HyperOS check

Accept the USB-debugging fingerprint on the phone. Some HyperOS versions also
require enabling **Install via USB**. The install script replaces only the
debug package `com.personalos.app`, then opens it. It deliberately does not use
`adb logcat`, `adb bugreport`, screenshot, pull, or filesystem commands.

The current MVP has no network, camera, microphone, location, contacts, or
shared-storage permission. Its `blob://` field is a synthetic reference entry;
it is not a photo picker.

Only the debug APK flow is prepared. Release signing is deliberately not
configured; no signing key or password belongs in this repository.
