@echo off
setlocal EnableExtensions
cd /d "%~dp0"
set ROSA_APP_ENV=development
set ROSA_DEMO_MODE=1
set ROSA_SECURE_COOKIES=0
set ROSA_REQUIRE_COMPLETE_CHECKLIST=0
echo Starting Rosa server at http://127.0.0.1:8819
echo Folder: %CD%
python -m uvicorn app:app --host 127.0.0.1 --port 8819
echo.
echo Rosa server stopped or failed. Read the error above.
pause
