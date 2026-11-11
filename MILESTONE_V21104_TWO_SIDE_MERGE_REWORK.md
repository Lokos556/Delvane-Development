# Rosa v2.11.04 — Two-side merge rework

- Added explicit field-priority merge between front and reverse scans.
- Front is preferred for full name, sex, nationality, DOB, expiry, and document number.
- Reverse is preferred for birthplace, birth name, and mother's birth name.
- Blank back-side fields no longer overwrite existing front-side fields.
- Added a dedicated enlarged reverse-side field OCR pass and separate enlarged MRZ pass.
- MRZ fields are only merged when relevant check digits validate.
- Expanded Hungarian label matching for "Anyja születési neve" and birthplace label OCR variants.
- Rejects digit-only/X-only maternal-name output.

Validation: JavaScript syntax check and archive integrity check. This is not a claim of verified OCR accuracy on a physical ID.
