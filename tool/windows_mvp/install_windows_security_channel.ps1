Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$appDir = Join-Path $repoRoot 'apps/personal_os_app'
$runnerDir = Join-Path $appDir 'windows/runner'
$nativeDir = Join-Path $PSScriptRoot 'native'

if (-not (Test-Path $runnerDir)) {
  throw 'Windows runner must be generated before installing the security channel.'
}

$nativeFiles = @(
  'windows_security_channel.h',
  'windows_security_channel.cpp'
)
foreach ($name in $nativeFiles) {
  $source = Join-Path $nativeDir $name
  if (-not (Test-Path $source)) {
    throw "Missing Windows security source: $source"
  }
  Copy-Item -Path $source -Destination (Join-Path $runnerDir $name) -Force
}

function Read-Utf8File([string]$path) {
  if (-not (Test-Path $path)) {
    throw "Required generated runner file is missing: $path"
  }
  return [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
}

function Write-Utf8File([string]$path, [string]$content) {
  $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
  [System.IO.File]::WriteAllText($path, $content, $utf8NoBom)
}

function Detect-Newline([string]$content) {
  if ($content.Contains("`r`n")) {
    return "`r`n"
  }
  return "`n"
}

function Replace-Once(
  [string]$path,
  [string]$content,
  [string]$needle,
  [string]$replacement,
  [string]$alreadyPresent
) {
  if ($content.Contains($alreadyPresent)) {
    return $content
  }
  $first = $content.IndexOf($needle, [System.StringComparison]::Ordinal)
  if ($first -lt 0) {
    throw "Template drift in ${path}: missing expected anchor '$needle'"
  }
  $second = $content.IndexOf(
    $needle,
    $first + $needle.Length,
    [System.StringComparison]::Ordinal
  )
  if ($second -ge 0) {
    throw "Template drift in ${path}: anchor is not unique '$needle'"
  }
  return $content.Substring(0, $first) + $replacement +
    $content.Substring($first + $needle.Length)
}

$cmakePath = Join-Path $runnerDir 'CMakeLists.txt'
$cmake = Read-Utf8File $cmakePath
$cmakeNewline = Detect-Newline $cmake
$cmake = Replace-Once `
  $cmakePath `
  $cmake `
  '  "flutter_window.cpp"' `
  "  `"flutter_window.cpp`"${cmakeNewline}  `"windows_security_channel.cpp`"" `
  '  "windows_security_channel.cpp"'
$cmake = Replace-Once `
  $cmakePath `
  $cmake `
  'target_link_libraries(${BINARY_NAME} PRIVATE "dwmapi.lib")' `
  "target_link_libraries(`${BINARY_NAME} PRIVATE `"dwmapi.lib`")${cmakeNewline}target_link_libraries(`${BINARY_NAME} PRIVATE `"windowsapp.lib`" `"ole32.lib`")" `
  'target_link_libraries(${BINARY_NAME} PRIVATE "windowsapp.lib" "ole32.lib")'
Write-Utf8File $cmakePath $cmake

$windowPath = Join-Path $runnerDir 'flutter_window.cpp'
$window = Read-Utf8File $windowPath
$windowNewline = Detect-Newline $window
$window = Replace-Once `
  $windowPath `
  $window `
  '#include "flutter/generated_plugin_registrant.h"' `
  "#include `"flutter/generated_plugin_registrant.h`"${windowNewline}#include `"windows_security_channel.h`"" `
  '#include "windows_security_channel.h"'
$window = Replace-Once `
  $windowPath `
  $window `
  '  RegisterPlugins(flutter_controller_->engine());' `
  "  RegisterPlugins(flutter_controller_->engine());${windowNewline}  RegisterWindowsSecurityChannel(${windowNewline}      flutter_controller_->engine()->messenger(), GetHandle());" `
  '  RegisterWindowsSecurityChannel('
$destroyNeedle =
  "  if (flutter_controller_) {${windowNewline}    flutter_controller_ = nullptr;${windowNewline}  }"
$destroyReplacement =
  "  if (flutter_controller_) {${windowNewline}    UnregisterWindowsSecurityChannel(${windowNewline}        flutter_controller_->engine()->messenger());${windowNewline}    flutter_controller_ = nullptr;${windowNewline}  }"
$window = Replace-Once `
  $windowPath `
  $window `
  $destroyNeedle `
  $destroyReplacement `
  '    UnregisterWindowsSecurityChannel('
Write-Utf8File $windowPath $window

Write-Host 'WINDOWS_SECURITY_CHANNEL_INSTALLED'
