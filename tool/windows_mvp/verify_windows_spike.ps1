Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$appDir = Join-Path $repoRoot 'apps/personal_os_app'

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
  throw 'Flutter is required for the Windows portability spike.'
}

Push-Location $appDir
try {
  flutter --version
  flutter config --enable-windows-desktop
  flutter pub get

  # Prove the production composition remains fail-closed before generating a
  # desktop host. This is intentionally narrower than the full Android suite.
  flutter test test/app_composition_test.dart

  $generatedHost = -not (Test-Path (Join-Path $appDir 'windows'))
  if ($generatedHost) {
    flutter create --platforms=windows --project-name personal_os_app --org com.personalos .

    # Platform generation is allowed to add Windows/tooling files, but it must
    # not silently rewrite the authored application or dependency contract.
    git diff --exit-code -- pubspec.yaml lib test/app_composition_test.dart
  }

  if (-not (Test-Path (Join-Path $appDir 'windows'))) {
    throw 'Flutter did not provide a Windows runner.'
  }

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
      '- result: PASS',
      '- limitation: fail-closed shell build only; Windows secure adapter and Vault open/close are not verified.'
    ) | Add-Content -Path $env:GITHUB_STEP_SUMMARY -Encoding utf8
  }
}
finally {
  Pop-Location
}
