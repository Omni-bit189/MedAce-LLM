@echo off
setlocal
TITLE MedAce Stopper
echo =================================================
echo   Stopping MedAce Environment... 🛑
echo =================================================

:: 1. Stop Tailscale Funnel for MedAce (port 443)
echo [1/3] 📡 Stopping Tailscale Funnel...
tailscale funnel --https=443 off
timeout /t 2 /nobreak >nul
echo     Done.

:: 2. Stop Uvicorn on port 8000 (MedAce only)
echo [2/3] 🐍 Stopping MedAce Backend on port 8000...
for /f "tokens=5" %%a in ('netstat -ano ^| findstr ":8000" ^| findstr "LISTENING"') do (
    echo     Found process on port 8000 with PID %%a
    taskkill /PID %%a /F /T
)

:: Fallback — kill by process name if port method missed it
wmic process where "commandline like '%%port 8000%%'" delete >nul 2>&1
wmic process where "commandline like '%%--port=8000%%'" delete >nul 2>&1
echo     Done.

:: 3. Stop Caddy only if SchoolTrack is also not running
echo [3/3] 🚦 Checking if Caddy is still needed...
netstat -ano | findstr ":8001" | findstr "LISTENING" >nul
if "%ERRORLEVEL%"=="1" (
    echo     SchoolTrack is not running, stopping Caddy...
    taskkill /IM caddy.exe /F
    echo     Caddy stopped.
) else (
    echo     SchoolTrack is still running, leaving Caddy alive...
)

echo.
echo ✅ MedAce fully stopped.
echo    - Uvicorn on port 8000: stopped
echo    - Tailscale Funnel: off
echo.
echo Press any key to close this window...
pause >nul
