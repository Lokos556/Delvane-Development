# Rosa v2.10.60 — Mobile reservation sheet and brand system

- Fixed reservation details modal on small screens as a bottom sheet with viewport-aware height, internal scrolling, and safe-area padding.
- Reservation stats and detail panels collapse into readable mobile grids; tabs scroll horizontally and buttons have touch-friendly target height.
- Introduced a restrained muted-rose accent (`#B85C78`) with deep rose (`#93425D`) and soft rose (`#F7E9EE`), retaining evergreen for operational/success states.
- Applied accent to guest check-in and core UI action styling.
- Added `START_ROSA_PHONE_HTTPS.bat` to launch a local demo server and a Cloudflare Quick Tunnel for phone camera testing. It requires cloudflared in the project folder or `C:\cloudflared\`. This is for temporary demo data only; do not expose production data or process real identity documents through a public tunnel.
