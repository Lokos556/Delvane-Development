# Testing Rosa V2.8.3 on a phone

1. Put the PC and phone on the same trusted home/private Wi-Fi.
2. Double-click `START_ROSA_PHONE.bat`.
3. The launcher prints both the PC URL and a phone URL such as `http://192.168.1.42:8819`.
4. Keep the black server window open.
5. If Windows Firewall prompts, allow Python on **Private networks only**.
6. Open the printed phone URL in Safari/Chrome on the phone.

If automatic IP detection fails, open Command Prompt on the PC, run `ipconfig`, and find **IPv4 Address** under the active Wi-Fi/Ethernet adapter. If it is `192.168.1.42`, open `http://192.168.1.42:8819` on the phone.

Do not use `127.0.0.1` on the phone; that address means the phone itself. Do not use the router's Default Gateway address. If a VPN is active and the phone cannot connect, temporarily disable the VPN for the LAN test.
