@echo off
TITLE MedAce Launcher 🚀
echo =================================================
echo   Starting MedAce Environment... 🩺💻
echo =================================================

:: 1. Start Tailscale Funnel
echo [1/3] 📡 Waking up Tailscale...
start "" cmd /k "tailscale funnel --https=443 http://localhost:8080"
timeout /t 3 /nobreak >nul

:: 2. Start Uvicorn for MedAce on port 8000
echo [2/3] 🐍 Firing up Uvicorn Backend...
start "" cmd /k "cd C:\Users\omair\OneDrive\Desktop\MedicalDataset && uvicorn api:app --reload --host 127.0.0.1 --port 8000"

:: 3. Start Caddy only if it's not already running
echo [3/3] 🚦 Checking Caddy Server...
tasklist /FI "IMAGENAME eq caddy.exe" 2>NUL | find /I /N "caddy.exe">NUL
if "%ERRORLEVEL%"=="1" (
    echo     Caddy not running, starting it now...
    start "" cmd /k "cd C:\Users\omair\OneDrive\Desktop\Caddy_Server && caddy run --config Caddyfile"
) else (
    echo     Caddy already running, skipping...
)

echo.
echo ✅ MedAce is GO!
echo    - MedAce API running on port 8000
echo    - Caddy proxying on port 8080 via Tailscale Funnel
echo    - SchoolTrack will also be routed on port 8090 if running
echo.
pause
