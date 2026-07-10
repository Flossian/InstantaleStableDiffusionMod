@echo off
rem Instantale SD MOD - sd_upscale.ini GUI editor launcher
rem (keep this file ASCII / CRLF)
cd /d "%~dp0"
start "" powershell -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%~dp0sd_upscale_gui.ps1"
exit /b 0
