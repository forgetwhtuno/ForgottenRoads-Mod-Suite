@echo off
setlocal
set SCRIPT_DIR=%~dp0
echo ============================================================
echo FORGOTTEN ROADS FOR ERENSHOR RELEASE GATE
echo Clean source only. Deterministic tests + whitelist package.
echo ============================================================
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%RELEASE_GATE.ps1" %*
set EXITCODE=%ERRORLEVEL%
echo.
if "%EXITCODE%"=="0" (
  echo ======================== SUCCESS ==========================
) else (
  echo ======================== FAILURE ==========================
  echo Exit code: %EXITCODE%
)
echo.
pause
exit /b %EXITCODE%
