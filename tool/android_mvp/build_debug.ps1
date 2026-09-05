$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
$AppDir = Join-Path $RepoRoot "apps/personal_os_app"

# Include the real provider adapter in dogfood APKs without embedding a key.
if (-not $env:ORG_GRADLE_PROJECT_personalOsOpenAiEnabled) {
    $env:ORG_GRADLE_PROJECT_personalOsOpenAiEnabled = "true"
}
if (-not $env:ORG_GRADLE_PROJECT_personalOsOpenAiModel) {
    $env:ORG_GRADLE_PROJECT_personalOsOpenAiModel = "gpt-5.4-mini"
}

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    throw "Flutter SDK is required and must be on PATH."
}

& (Join-Path $PSScriptRoot "bootstrap_gradle_wrapper.ps1")

Push-Location $AppDir
try {
    flutter pub get
    if ($LASTEXITCODE -ne 0) { throw "flutter pub get failed" }
    flutter analyze
    if ($LASTEXITCODE -ne 0) { throw "flutter analyze failed" }
    flutter test
    if ($LASTEXITCODE -ne 0) { throw "flutter test failed" }
    flutter build apk --debug
    if ($LASTEXITCODE -ne 0) { throw "flutter build apk failed" }
} finally {
    Pop-Location
}

Write-Host "Debug APK: $AppDir/build/app/outputs/flutter-apk/app-debug.apk"
