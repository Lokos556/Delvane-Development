# Rosa v2.10.90 — Name and document-number extraction fix

## Root cause
The visible OCR parser was more dependent on clean bilingual labels than the raw OCR output warranted. A noisy label such as `Cala. sut6navIF ani pase and. Giver name` could fail the known-label matcher, leaving `full_name` empty. The document-number extraction could also be too broad when parsing flattened OCR, risking inclusion of adjacent text.

## Changes
- Added a cautious fallback for standalone OCR variants of `given name` / `full name`: inspect the next one or two lines and accept only a plausible multi-part person name.
- Prefer extracting the first token immediately following `Doc. No.` / OCR variant `Dac. No.` on the same line.
- Keep the existing form mapping unchanged: `applyParsed()` assigns `state.full_name` to `#full_name` and `state.document_number` to `#document_number`. The root cause was that the parser returned empty strings for these fields.
- Preserve the existing DOB, nationality, sex-legend, still-photo capture, and loading workflow.

## Validation
- `node --check static/guest-checkin.js`
- `node tests/test_v21090_name_doc_field_extraction.js` — synthetic noisy OCR regression test passed.
- `node tests/test_mrz_parser.js` — passed.
- `pytest -q tests/test_guest_checkin.py` — 1 passed.

These tests validate parser behavior on synthetic text, not a live phone-camera scan. Real-device verification remains necessary.
