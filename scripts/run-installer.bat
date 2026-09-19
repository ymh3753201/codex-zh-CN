@echo off
setlocal DisableDelayedExpansion
chcp 65001 >nul
title Codex Chinese Installer
set "PS_HOST=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
set "EARLY_LOG=%TEMP%\codex-zh-startup-%RANDOM%-%RANDOM%.log"
set "OUTPUT_LOG=%TEMP%\codex-zh-output-%RANDOM%-%RANDOM%.log"
if not exist "%PS_HOST%" goto missing_host
if not exist "%~dp0bootstrap.ps1" goto missing_bootstrap
echo Starting Codex Chinese installer...
"%PS_HOST%" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%~dp0bootstrap.ps1" -Action "%~1" -CodexPath "%~2" -AutoClose >"%OUTPUT_LOG%" 2>"%EARLY_LOG%"
set "EXIT_CODE=%ERRORLEVEL%"
if not "%EXIT_CODE%"=="0" goto failed
if exist "%OUTPUT_LOG%" type "%OUTPUT_LOG%"
if /i "%~1"=="status" pause
if /i "%~1"=="uninstall" pause
exit /b 0
:missing_host
echo [FAILED] Windows PowerShell is missing: "%PS_HOST%"
goto failed
:missing_bootstrap
echo [FAILED] Package files are missing. Extract the complete ZIP into a new folder.
goto failed
:failed
if exist "%OUTPUT_LOG%" type "%OUTPUT_LOG%"
if exist "%EARLY_LOG%" type "%EARLY_LOG%"
echo.
echo [FAILED] Installation did not complete. Keep this window or take a screenshot.
echo Logs: package diagnostics folder, or "%TEMP%\codex-zh-diagnostics"
echo PowerShell startup errors: "%EARLY_LOG%"
echo Installer output: "%OUTPUT_LOG%"
pause
exit /b 1
