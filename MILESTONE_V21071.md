# Rosa v2.10.51 — Guest Scanner Reliability Upgrade

Implemented on top of v2.10.50 Guest Check-in Foundation.

## Scanner improvements

- Added ICAO MRZ parsing for TD3 passports.
- Added ICAO MRZ parsing for TD1 identity cards.
- Added ICAO MRZ parsing for TD2 documents.
- Added ICAO 9303 check-digit validation for document number, birth date, expiry and composite fields where applicable.
- Added confidence state: `verified` when all available MRZ checks pass; `high` when the MRZ is readable but not every check passes.
- Added local image-quality gate for lighting, contrast and blur/edge quality before OCR.
- Added a second local OCR pass focused on the lower MRZ area when the first pass fails.
- Camera images remain browser-local and are never uploaded as document images.
- Manual field correction remains available when scanning is unsuccessful or a required field is not present in the MRZ.

## Compliance architecture

The scanner produces structured guest data for the existing Rosa guest record and VIZA outbox architecture. Document images are not persisted.

## Verification

- `python -m py_compile app.py` — PASS
- `node --check static/guest-checkin.js` — PASS
- TD3 sample MRZ parse + all check digits — PASS
- TD1 sample MRZ parse + all check digits — PASS
- `pytest -q tests/test_guest_checkin.py tests/test_v21042.py tests/test_v21046.py` — PASS (5 tests)
- Full repository pytest run started but exceeded the 120-second execution limit; no conclusion is drawn from the incomplete run.

## Version

Rosa runtime bumped from 2.10.43 to 2.10.51. Database schema unchanged.
