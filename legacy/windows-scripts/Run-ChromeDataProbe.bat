@echo off
rem Launch ChromeDataProbe (double-click me)
title Chrome Data Probe
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0ChromeDataProbe.ps1"
echo.
pause
