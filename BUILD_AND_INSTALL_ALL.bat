@echo off
REM One-click entry point: build + test + install every enabled suite mod.
REM Pass through any BUILD_ALL.ps1 switch, e.g.:
REM   BUILD_AND_INSTALL_ALL.bat -Mod PvP -Mod DeepSims
REM   BUILD_AND_INSTALL_ALL.bat -BuildOnly
REM   BUILD_AND_INSTALL_ALL.bat -RunTests:$false
setlocal
set SCRIPT_DIR=%~dp0
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%BUILD_ALL.ps1" %*
set EXITCODE=%ERRORLEVEL%
echo.
pause
exit /b %EXITCODE%
