@echo off
setlocal DisableDelayedExpansion
if not exist "%~dp0scripts\run-installer.bat" (
  echo [FAILED] Missing package files. Extract the complete ZIP first.
  pause
  exit /b 1
)
"%~dp0scripts\run-installer.bat" repair-launcher
