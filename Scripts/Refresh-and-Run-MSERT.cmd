@echo off
setlocal
set "SCRIPT=%~dp0Update-MicrosoftSafetyScanner.ps1"
set "SCANNER=%~dp0..\Tools\Scanners\MSERT.exe"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%"
if errorlevel 1 (
    echo Safety Scanner download or signature verification failed.
    pause
    exit /b 1
)
start "Microsoft Safety Scanner" "%SCANNER%"
endlocal
