# Rosa v2.11.05 — MRZ merge and birth-name fallback

- Reconstructs Hungarian TD1 MRZ rows when OCR removes the line breaks. The three rows contain document number/check digit, birth date/sex/expiry/nationality, and the holder name.
- Keeps already captured front-side values authoritative when scanning the reverse; the reverse scan can fill missing values but cannot overwrite existing front-side fields with noisy MRZ output.
- If birth name is blank after merging, fills it from full name.
- Rejects implausible MRZ name candidates without a valid date.
- Fixed digit validation for name fields.

Validation: JavaScript syntax check and synthetic MRZ/parser regression tests passed. These tests do not validate OCR performance on a physical identity card or iPhone camera.

## Follow-up review: reverse-side OCR validation

- Fixed escaped digit checks that previously failed to reject digit-containing birth-name and mother's-birth-name values.
- Rejects a birthplace that contains no plausible letters, including a lone OCR digit.
- Correctly strips the `(MAGYARORSZAG)` / `(HUNGARY)` suffix from a recognized birthplace.
- Added regression cases for numeric name-field contamination and birthplace parsing.

Validation: JavaScript syntax checks and scanner/MRZ regression tests pass. This remains synthetic/source-level validation; physical-card OCR accuracy is not verified.
