@echo off
title JARVIS SYSTEM CONTROLLER
echo ==============================================
echo   LAUNCHING JARVIS LOCAL TELEMETRY CHANNEL
echo ==============================================
echo.
echo [*] Starting PowerShell backend (Port 9000)...
start /b powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File "%~dp0server.ps1"
echo [*] Waiting 2 seconds for server initialization...
timeout /t 2 >nul
echo [*] Launching holographic dashboard in desktop mode...
start msedge.exe --app="http://localhost:9000"
echo.
echo ==============================================
echo   JARVIS SYSTEM ONLINE. CLOSE THIS WINDOW.
echo ==============================================
exit
