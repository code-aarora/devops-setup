@echo off
rem Keep batch variables local to this launcher.
setlocal
rem Run setup from this folder even when launched from another drive.
cd /d "%~dp0"
rem Launch the installer using the supplied local script without profile side effects.
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup.ps1"
rem Preserve the PowerShell installer exit code.
set "result=%errorlevel%"
rem Separate the final result visually from installer output.
echo.
rem Show the installer result on screen.
echo Setup exit code: %result%
rem Keep the window open so the operator can read the result.
pause
rem Return the installer exit code to the calling process.
exit /b %result%
