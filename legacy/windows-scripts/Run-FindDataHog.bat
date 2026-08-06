@echo off
rem Launch FindDataHog (double-click me, or call from cmd)
title Data Hog Finder
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0FindDataHog.ps1"
echo.
pause
