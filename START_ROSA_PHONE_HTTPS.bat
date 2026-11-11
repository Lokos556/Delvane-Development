@echo off
setlocal EnableExtensions
cd /d "%~dp0"
set PORT=8819
set "CLOUDFLARED="
if exist "%~dp0cloudflared.exe" set "CLOUDFLARED=%~dp0cloudflared.exe"
if exist "C:\cloudflared\cloudflared-windows-amd64.exe" set "CLOUDFLARED=C:\cloudflared\cloudflared-windows-amd64.exe"
if exist "C:\cloudflared\cloudflared.exe" set "CLOUDFLARED=C:\cloudflared\cloudflared.exe"
echo.
echo ====================================================
echo ROSA PHONE CAMERA TEST - HTTPS TUNNEL
echo ====================================================
echo Temporary testing only. Use demo data only; never use real guest identity documents.
echo.
if not defined CLOUDFLARED (
  echo cloudflared.exe was not found. Put it in C:\cloudflared\ or beside this BAT file.
  pause
  exit /b 1
)
python -c "import fastapi,uvicorn,pydantic,cryptography" >nul 2>&1
if errorlevel 1 (
  echo Required Python packages are missing. Installing from requirements.txt...
  python -m pip install -r requirements.txt
  if errorlevel 1 (echo Package installation failed.& pause & exit /b 1)
)
echo Starting Rosa server in a separate window...
start "Rosa local server" /D "%~dp0" cmd /k call START_ROSA_SERVER_FOR_HTTPS.bat
echo Waiting for Rosa to listen on 127.0.0.1:%PORT%...
set "ROSA_READY="
for /L %%N in (1,1,30) do (
  powershell -NoProfile -Command "try { $r = Invoke-WebRequest -UseBasicParsing http://127.0.0.1:%PORT%/ -TimeoutSec 1; if ($r.StatusCode -ge 200) { exit 0 } else { exit 1 } } catch { exit 1 }" >nul 2>&1
  if not errorlevel 1 (set ROSA_READY=1& goto :ready)
  timeout /t 1 /nobreak >nul
)
:ready
if not defined ROSA_READY (
  echo.
  echo ERROR: Rosa did not respond on 127.0.0.1:%PORT%. The tunnel was NOT started.
  echo Check the separate Rosa local server window for the Python error.
  pause
  exit /b 1
)
echo Rosa is responding locally. Starting the HTTPS tunnel now.
echo Keep both windows open. Stop with Ctrl+C when finished.
"%CLOUDFLARED%" tunnel --url http://127.0.0.1:%PORT%
pause
