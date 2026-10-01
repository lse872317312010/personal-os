@echo off
cd /d "%~dp0"
set PERSONAL_OS_OPEN_BROWSER=1
if exist runtime\node.exe (
  runtime\node.exe server.mjs
) else (
  node server.mjs
)
if errorlevel 1 pause
