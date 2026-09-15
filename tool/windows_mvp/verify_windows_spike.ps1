Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$appDir = Join-Path $repoRoot 'apps/personal_os_app'
$securityInstaller = Join-Path $repoRoot 'tool/windows_mvp/install_windows_security_channel.ps1'

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
  throw 'Flutter is required for the Windows portability spike.'
}
if (-not (Test-Path $securityInstaller)) {
  throw 'Windows native security installer is missing.'
}

Push-Location $appDir
try {
  flutter --version
  flutter config --enable-windows-desktop
  flutter pub get

  # Prove production dispatch and the shared security wire contract stay
  # fail-closed before generating a desktop host.
  flutter test test/app_composition_test.dart
  flutter test test/method_channel_platform_security_bridge_test.dart

  $generatedHost = -not (Test-Path (Join-Path $appDir 'windows'))
  if ($generatedHost) {
    flutter create --platforms=windows --project-name personal_os_app --org com.personalos .

    # Platform generation may add Windows/tooling files, but it must not
    # silently rewrite authored Dart application code, tests, or dependencies.
    git diff --exit-code -- pubspec.yaml lib test
  }

  if (-not (Test-Path (Join-Path $appDir 'windows'))) {
    throw 'Flutter did not provide a Windows runner.'
  }

  # Inject only the audited native user-presence channel into the generated
  # runner. Vault/key methods stay fail-closed in that native implementation.
  & $securityInstaller

  flutter analyze
  flutter build windows --debug

  $exe = Get-ChildItem -Path (Join-Path $appDir 'build/windows') `
    -Filter 'personal_os_app.exe' -File -Recurse | Select-Object -First 1
  if ($null -eq $exe -or $exe.Length -le 0) {
    throw 'Windows debug executable was not produced.'
  }

  $digest = Get-FileHash -Path $exe.FullName -Algorithm SHA256
  $hostMode = if ($generatedHost) { 'generated' } else { 'committed' }
  $exeSha256 = $digest.Hash.ToLowerInvariant()
  Write-Host ('WINDOWS_SPIKE_PASS host={0} exe={1} sha256={2}' -f `
      $hostMode, $exe.Name, $exeSha256)

  if (-not [string]::IsNullOrWhiteSpace($env:GITHUB_STEP_SUMMARY)) {
    $commit = if ([string]::IsNullOrWhiteSpace($env:GITHUB_SHA)) {
      'local-unbound'
    } else {
      $env:GITHUB_SHA
    }
    @(
      '## Windows portability spike',
      '',
      "- commit: $commit",
      "- runner_os: $env:RUNNER_OS",
      "- host: $hostMode",
      "- executable: $($exe.Name)",
      "- sha256: $exeSha256",
      '- security_wire_contract: PASS',
      '- native_user_presence_compile: PASS',
      '- result: PASS',
      '- limitation: Windows user-presence runtime behavior is not verified; key protection, SQLCipher Vault open/close, and controlled media remain unavailable.'
    ) | Add-Content -Path $env:GITHUB_STEP_SUMMARY -Encoding utf8
  }
}
finally {
  Pop-Location
}
