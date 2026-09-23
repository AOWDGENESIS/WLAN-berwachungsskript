@echo off
setlocal
cd /d "%~dp0"
set "PS=powershell.exe"
where pwsh.exe >nul 2>&1 && set "PS=pwsh.exe"
%PS% -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Start-Guardian.ps1" %*
set "EXITCODE=%ERRORLEVEL%"
if not "%EXITCODE%"=="0" pause
exit /b %EXITCODE%
