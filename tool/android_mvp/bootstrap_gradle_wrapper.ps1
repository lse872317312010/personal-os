$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
$AndroidDir = Join-Path $RepoRoot "apps/personal_os_app/android"
$WrapperJar = Join-Path $AndroidDir "gradle/wrapper/gradle-wrapper.jar"
$Gradlew = Join-Path $AndroidDir "gradlew"

if ((Test-Path $WrapperJar) -and (Test-Path $Gradlew)) { exit 0 }
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    throw "Flutter SDK is required and must be on PATH."
}

$ScratchDir = Join-Path ([System.IO.Path]::GetTempPath()) ("personal-os-" + [guid]::NewGuid())
try {
    flutter create --platforms=android --org com.personalos --project-name personal_os_app $ScratchDir *> $null
    if ($LASTEXITCODE -ne 0) { throw "Flutter wrapper template generation failed." }

    Copy-Item (Join-Path $ScratchDir "android/gradlew") (Join-Path $AndroidDir "gradlew")
    Copy-Item (Join-Path $ScratchDir "android/gradlew.bat") (Join-Path $AndroidDir "gradlew.bat")
    Copy-Item (Join-Path $ScratchDir "android/gradle/wrapper/gradle-wrapper.jar") $WrapperJar
} finally {
    if (Test-Path $ScratchDir) { Remove-Item -LiteralPath $ScratchDir -Recurse -Force }
}

Write-Host "Gradle wrapper bootstrapped from the installed Flutter SDK template."
