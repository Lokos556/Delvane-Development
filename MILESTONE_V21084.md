# Rosa v2.10.84 — ID OCR to form-field mapping

## Changes
- Visible-field OCR parser now handles common cases where a field label and its value are returned on separate OCR lines, including bilingual Hungarian/English labels.
- Expanded expiry-date labels and made the recognized expiry date visible in the guest check-in form.
- Includes `date_of_expiry` in the check-in form payload and stores it in the encrypted sensitive guest-data payload.
- Improved Hungarian `NŐ` sex parsing and added Hungarian identity-card wording to document-type detection.
- After the form re-renders with parsed values, the scan status is written to the new live status element rather than the detached pre-render element.
- Added regression tests that assert extracted values actually appear in rendered input values, not merely in the parser result or raw OCR diagnostics.
- Keeps OCR local to the phone and leaves visible-OCR results in manual-review status.

## Validation
- `node --check static/guest-checkin.js` — passed.
- `node tests/test_guest_scanner_parser.js` — passed, including separate-line Hungarian OCR and rendered-field assertions.
- `node tests/test_mrz_parser.js` — passed.
- `pytest -q tests/test_guest_checkin.py` — 1 passed.
- `python -m py_compile app.py` — passed.

Physical-device validation is still required to confirm results against the user's actual ID and phone camera. Do not treat OCR output as verified identity data without human review.
