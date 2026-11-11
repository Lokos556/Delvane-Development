@echo off
setlocal EnableExtensions
cd /d "%~dp0"
set PORT=8819

echo.
echo ====================================================
echo   ROSA V2.10.0 - PHONE / LAN TEST MODE
 echo ====================================================
echo.
echo This exposes Rosa only to devices on your local network.
echo Use it on a trusted home/private Wi-Fi.
echo.

python -c "import fastapi,uvicorn,pydantic,cryptography" >nul 2>&1
if errorlevel 1 (
  echo Installing required Python packages...
  python -m pip install -r requirements.txt
  if errorlevel 1 pause & exit /b 1
)

set ROSA_APP_ENV=development
set ROSA_DEMO_MODE=1
set ROSA_SECURE_COOKIES=0
set ROSA_REQUIRE_COMPLETE_CHECKLIST=0

rem Detect the IPv4 address Windows is actually using for its default network route.
rem This avoids localized ipconfig output and the older PowerShell adapter-selection bug.
set "LAN_IP="
for /f "usebackq delims=" %%I in (`python -c "import socket; s=socket.socket(socket.AF_INET,socket.SOCK_DGRAM); s.connect(('1.1.1.1',80)); print(s.getsockname()[0]); s.close()" 2^>nul`) do set "LAN_IP=%%I"

if not defined LAN_IP (
  for /f "usebackq delims=" %%I in (`python -c "import socket,ipaddress; xs=[]; [xs.append(x[4][0]) for x in socket.getaddrinfo(socket.gethostname(),0,socket.AF_INET,socket.SOCK_DGRAM) if x[4][0] not in xs]; xs=[x for x in xs if not ipaddress.ip_address(x).is_loopback and not ipaddress.ip_address(x).is_link_local]; print(next((x for x in xs if ipaddress.ip_address(x).is_private), xs[0] if xs else ''))" 2^>nul`) do set "LAN_IP=%%I"
)

echo PC browser: http://127.0.0.1:%PORT%
if defined LAN_IP (
  echo PHONE URL : http://%LAN_IP%:%PORT%
) else (
  echo PHONE URL : [could not detect automatically]
  echo.
  echo Run ^"ipconfig^" in another Command Prompt and find the IPv4 Address
  echo under the active Wi-Fi or Ethernet adapter. Then use:
  echo     http://YOUR-IP:%PORT%
)
echo.
echo 1. Keep this window open.
echo 2. Put the phone and PC on the same Wi-Fi.
echo 3. If Windows Firewall asks, allow Private networks only.
echo 4. Open the PHONE URL above in Safari/Chrome on your phone.
echo 5. If you use a VPN, temporarily disable it if the phone cannot connect.
echo.
start "" cmd /c "timeout /t 2 >nul & start http://127.0.0.1:%PORT%"
python -m uvicorn app:app --host 0.0.0.0 --port %PORT%
pause
