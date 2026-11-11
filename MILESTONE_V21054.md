# Rosa v2.10.54 — Scanner OCR robustness

## Changes
- Added a local OCR preprocessing pass that upscales the captured image and applies grayscale/contrast enhancement before recognition.
- Retained the original-image pass and added a lower-image MRZ-focused pass; MRZ parsing is preferred over visual-text suggestions.
- Fixed scan provenance so visual OCR suggestions are recorded as `camera_ocr`, not incorrectly labelled as `camera_mrz`.
- Added strict calendar-date validation to the YYMMDD parser so impossible dates are rejected.
- Added a Node parser regression test covering sample ICAO TD3 passport and TD1 identity-card MRZs, Hungarian-labelled visual OCR fields, date validation, and scan-method provenance.
- Bumped the Rosa runtime version to 2.10.54. Existing guest-check-in asset cache busting remains at v3.

## Validation
- `pytest -q tests/test_guest_checkin.py tests/test_v21042.py tests/test_v21046.py`: 5 passed.
- `node tests/test_guest_scanner_parser.js`: passed.
- `node --check static/guest-checkin.js`: passed.
- `python -m py_compile app.py`: passed.

## Limitations
- Parser regression tests use standard synthetic/sample MRZ text and a labelled OCR text fixture; they are not a real-world image benchmark.
- Broad support for specific Hungarian ID-card generations and other EU document designs remains unverified until tested with non-sensitive specimen images.
- No document-image upload or persistent image storage was added.
