# Rosa v2.10.83 — multilingual visible-field parsing

- Parses bilingual field labels when they occur mid-line rather than only at line start.
- Adds tolerant Hungarian ID label handling for name, birth date, expiry date, document number, place of birth, birth name, mother's name, nationality and sex.
- Parses both DD MM YYYY and YYYY MM DD based on the field label.
- Rejects document-heading strings as names and keeps OCR-extracted values in manual-review status.
- No new paid dependencies.

Checks: JavaScript syntax and ZIP integrity. Not physically tested against an ID; the next test must confirm extraction on the same device.
