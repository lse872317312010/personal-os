$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
$Apk = Join-Path $RepoRoot "apps/personal_os_app/build/app/outputs/flutter-apk/app-debug.apk"
$PackageName = "com.personalos.app"

if (-not (Get-Command adb -ErrorAction SilentlyContinue)) {
    throw "Android platform-tools (adb) are required."
}
if (-not (Test-Path $Apk)) {
    throw "Debug APK not found. Run tool/android_mvp/build_debug.ps1 first."
}

# ANDROID_SERIAL can select a device without putting its identifier in output.
adb get-state *> $null
if ($LASTEXITCODE -ne 0) { throw "No authorized Android device is available." }
adb install -r --no-streaming $Apk *> $null
if ($LASTEXITCODE -ne 0) { throw "APK installation failed." }
adb shell am force-stop $PackageName
adb shell monkey -p $PackageName -c android.intent.category.LAUNCHER 1 *> $null

Write-Host "Personal OS installed and launched. No device identifier or logcat was collected."
