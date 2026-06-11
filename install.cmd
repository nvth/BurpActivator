@echo off
setlocal

set "SCRIPT_DIR=%~dp0"
set "INSTALL_PS1=%SCRIPT_DIR%install.ps1"

if not exist "%INSTALL_PS1%" (
    echo install.ps1 was not found next to this file.
    pause
    exit /b 1
)

net session >nul 2>&1
if not "%ERRORLEVEL%"=="0" (
    echo This installer must be run as Administrator.
    echo Right-click install.cmd and choose Run as administrator.
    pause
    exit /b 1
)

powershell.exe -NoProfile -Command "Set-ExecutionPolicy RemoteSigned -Scope LocalMachine -Force -ErrorAction Stop; Set-ExecutionPolicy Unrestricted -Scope LocalMachine -Force -ErrorAction Stop"
if not "%ERRORLEVEL%"=="0" (
    echo Failed to update ExecutionPolicy before installation.
    pause
    exit /b %ERRORLEVEL%
)

powershell.exe -NoProfile -File "%INSTALL_PS1%"
set "EXIT_CODE=%ERRORLEVEL%"

powershell.exe -NoProfile -Command "Write-Host 'Restoring ExecutionPolicy to Default...'; Set-ExecutionPolicy Default -Scope LocalMachine -Force -ErrorAction Stop"
if not "%ERRORLEVEL%"=="0" (
    echo Warning: failed to restore ExecutionPolicy to Default.
    echo Run this manually as Administrator:
    echo   Set-ExecutionPolicy Default -Scope LocalMachine -Force
)

if not "%EXIT_CODE%"=="0" (
    echo.
    echo Installation failed with exit code %EXIT_CODE%.
    pause
)

exit /b %EXIT_CODE%
