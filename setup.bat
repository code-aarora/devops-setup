@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup.ps1"
set "result=%errorlevel%"
echo.
echo Setup exit code: %result%
pause
exit /b %result%
