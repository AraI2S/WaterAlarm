@echo off
setlocal
rem Run this manually to validate Config.json without launching the tray app.
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0WaterAlarm.ps1" -CheckOnly
echo.
pause
