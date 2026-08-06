@echo off
rem Launch DataUsageTracker (double-click me, or call from cmd)
title Data Usage Tracker
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0DataUsageTracker.ps1" -Snapshot
echo.
pause
