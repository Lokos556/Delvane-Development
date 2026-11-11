# Rosa v2.10.86 — Reject invalid sex markers and preserve visible OCR fields

## Changes
- Treat `I` as an invalid sex marker from an OCR-read MRZ. Only ICAO `M` and `F` are accepted; `<`/unknown remains blank. Rosa no longer puts `I` into the sex field.
- Treat `Nem/Sex: F/M` as a printed bilingual legend, not the cardholder's sex. The parser only accepts an unambiguous value such as `Sex: F`, `Nem: Nő`, or a supported MRZ `F`/`M` marker.
- Prevent blank or invalid MRZ fields from overwriting values recognized from the visible text. Valid non-empty MRZ values may still supplement/override visible OCR where appropriate.
- Added regression tests for the `F/M` legend and an MRZ with an invalid `I` sex marker.
- Preserved the still-photo capture workflow, loading overlay, and in-place form-field assignment from v2.10.85.

## Validation
- `node tests/test_guest_scanner_parser.js` — passed.
- `python -m py_compile app.py` — passed.
- `pytest -q tests/test_guest_checkin.py` — run during packaging.

## Manual device test still required
These tests validate parser behavior and field mapping in a simulated DOM. Real-device camera/OCR behavior and the user's specific card still need confirmation. Check the date of birth and every populated field before confirming.
