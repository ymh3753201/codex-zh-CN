@echo off
setlocal DisableDelayedExpansion
if not exist "%~dp0install-windows.bat" (
  echo [FAILED] Missing install-windows.bat. Extract the complete ZIP first.
  pause
  exit /b 1
)
"%~dp0install-windows.bat" "%~1"
