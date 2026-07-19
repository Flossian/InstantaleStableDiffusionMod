@echo off
rem Instantale SD MOD manager GUI launcher (install / switch / settings)
rem (keep this file ASCII / CRLF)
cd /d "%~dp0"
start "" powershell -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%~dp0mod_gui.ps1"
exit /b 0
