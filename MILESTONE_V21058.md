# Milestone v2.10.58 — Guest scanner capture UX

- Added step-by-step framing, lighting, and glare guidance to the guest scanner.
- Renamed manual capture to **Scan now** and added opt-in auto-capture when the camera image remains stable for about 1.5 seconds.
- Auto-capture can be cancelled; manual capture remains available. Image quality checks and manual-entry fallback remain in place.
- Added a practical local and phone testing guide, including the secure-context limitation for browser camera access.
- Kept document image handling local to the browser; no image upload/storage path added.

Validation: `node --check static/guest-checkin.js`, `python -m py_compile app.py`, and targeted tests `tests/test_guest_checkin.py tests/test_v21042.py tests/test_v21046.py` passed (5 tests).
