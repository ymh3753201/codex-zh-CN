@echo off
chcp 65001 >nul
setlocal
cd /d "%~dp0"
title Restore Codex English
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\install_windows.ps1" -Action uninstall
set "EXIT_CODE=%ERRORLEVEL%"
echo.
if "%EXIT_CODE%"=="0" (
  echo Restored. You can close this window.
) else (
  echo Failed. Please keep this window and report the message above.
)
pause >nul
exit /b %EXIT_CODE%
