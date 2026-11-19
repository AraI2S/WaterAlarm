@echo off
setlocal
rem Console-compatible fallback. It may flash a console while Launcher.ps1 runs.
rem The long-lived worker always starts with CreateNoWindow=true.
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -STA -File "%~dp0Launcher.ps1"
exit /b %errorlevel%
