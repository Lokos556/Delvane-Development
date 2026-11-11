@echo off
cd /d "%~dp0"
set PORT=8819

echo.
echo ================================================
echo   ROSA V2.10.27 - Future Reservation Calendar
echo ================================================
echo.
echo Checking Rosa requirements...
python -c "import fastapi,uvicorn,pydantic,cryptography" >nul 2>&1
if errorlevel 1 (
  echo Installing required Python packages. This normally happens only once...
  python -m pip install -r requirements.txt
  if errorlevel 1 (
    echo.
    echo Rosa could not install its requirements.
    pause
    exit /b 1
  )
)
set ROSA_APP_ENV=development
set ROSA_DEMO_MODE=1
set ROSA_SECURE_COOKIES=0
set ROSA_REQUIRE_COMPLETE_CHECKLIST=0

echo Starting Rosa at http://127.0.0.1:%PORT%
echo Keep this window open while Rosa is running.
echo.
start "" cmd /c "timeout /t 2 >nul & start http://127.0.0.1:%PORT%"
python -m uvicorn app:app --host 127.0.0.1 --port %PORT%
pause
