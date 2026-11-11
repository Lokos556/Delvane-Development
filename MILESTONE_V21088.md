# Rosa v2.10.88 — Hungarian ID sex legend and document-number fallback

- Treat the visible Hungarian ID legend `Nem/Sex: F/M` as `Férfi/Male` and map it to the male code `M`, never female `F`.
- Continue to prefer an explicit sex value if OCR provides one outside the legend.
- Added a more tolerant fallback for document-number labels and cases where the number appears on the following OCR line.
- Kept existing date-of-birth, nationality, still-photo capture, and loading behavior unchanged.

Validation performed:
- `node --check static/guest-checkin.js`
- `node tests/test_mrz_parser.js`

Real-device OCR and form-population behavior still require testing on the user's phone.
