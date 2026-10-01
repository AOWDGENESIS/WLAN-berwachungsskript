@echo off
REM WLAN Guardian UI Launcher
REM This batch file launches the Guardian UI from Windows explorer/shortcuts

setlocal enabledelayedexpansion
cd /d "%~dp0"

powershell -NoProfile -ExecutionPolicy Bypass -File "Start-Guardian-UI.ps1"
if errorlevel 1 (
    echo Guardian UI failed to start. Check config/guardian.example.json
    pause
    exit /b 1
)
