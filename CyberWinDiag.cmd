@echo off
REM ===================================================================
REM  CyberWinDiagnostics launcher
REM  Self-elevates, then runs the collector with the execution policy
REM  bypassed for this process only.
REM ===================================================================
setlocal
set "SCRIPT=%~dp0Scripts\Invoke-CyberWinDiag.ps1"

if not exist "%SCRIPT%" (
    echo ERROR: Cannot find %SCRIPT%
    echo Make sure the whole CyberWinDiagnostics folder was copied to the stick.
    pause
    exit /b 1
)

REM --- Check for elevation ---
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Requesting administrator privileges...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

echo Running CyberWinDiagnostics collector...
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" %*

echo.
echo Collection finished. Read _SUMMARY.txt in the Reports folder.
pause
endlocal
