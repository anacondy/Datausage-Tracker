@echo off
rem Launch FindDataHog (double-click me, or call from cmd)
title Data Hog Finder
cd /d "%~dp0"
where powershell >nul 2>nul
if %errorlevel% neq 0 (
    echo ERROR: PowerShell not found. Please install Windows PowerShell or PowerShell 7+.
    pause
    exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0FindDataHog.ps1"
echo.
pause
