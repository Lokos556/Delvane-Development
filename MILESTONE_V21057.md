# Rosa v2.10.57 — Check-digit-guided MRZ OCR correction

## Changes
- Added conservative OCR-confusion correction for MRZ fields protected by ICAO check digits.
- Only modifies eligible characters in document number, date, expiry, and applicable optional-data fields; names, nationality, document type, and check digits themselves are never edited.
- Prefers a unique single-character repair, tries two-character repairs only if no unique single-character repair exists, and refuses ambiguous corrections.
- A correction is only returned when every available MRZ check digit passes and the corrected birth date/document number parse successfully.
- Corrected reads are explicitly marked `corrected_verified`; guest UI asks the guest to review every field. Owner verification remains a separate requirement.
- Bumped guest scanner cache key and application version.

## Validation
- `node --check static/guest-checkin.js`
- `node tests/test_guest_scanner_parser.js` (TD3/TD1 parsing, unique check-digit-supported OCR correction, date validation, Hungarian visible OCR, scan-method provenance)
- `python -m py_compile app.py`
- Targeted pytest suite run separately; full repository suite is not claimed.

## Limitation
Check digits detect many OCR errors but are not cryptographic proof of identity or document authenticity. All values remain subject to guest review and accommodation-provider identity verification.
