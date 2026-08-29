@echo off
rem Launch DataUsageTracker (double-click me, or call from cmd)
title Data Usage Tracker
cd /d "%~dp0"
where powershell >nul 2>nul
if %errorlevel% neq 0 (
    echo ERROR: PowerShell not found. Please install Windows PowerShell or PowerShell 7+.
    pause
    exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0DataUsageTracker.ps1" -Snapshot
echo.
pause
