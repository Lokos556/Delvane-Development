# Rosa v2.10.93 — Noise-resistant ID OCR field extraction

Based on v2.10.92. This revision changes the actual guest check-in parser and adds regression coverage for the five required fields.

## Changes

- **Full name:** normalizes OCR speckles, stray digits, punctuation, and isolated one-character fragments before accepting a name. Still requires a plausible multi-part alphabetic name and rejects common document headings/labels.
- **Date of birth:** broadens support for OCR-mangled Hungarian DOB labels while continuing to require a valid calendar date near a DOB label. Unlabelled dates are not guessed as DOB.
- **Sex:** supports a sex value printed on the next line after a bilingual label; Hungarian `NŐ` maps to `F`, `Férfi`/`Male` maps to `M`, and the known Hungarian `F/M` legend follows this check-in flow's existing `M` mapping.
- **Nationality:** extracts a recognized three-letter country code such as `HUN` even when OCR appends junk characters; unknown codes are not accepted as a nationality.
- **Document number:** supports OCR splitting a document number into adjacent alphanumeric groups, then strips spaces/punctuation and rejects short, overly long, non-numeric, or obvious heading/label values.
- **Form population:** regression test now checks that all five required fields are written into their existing form controls, not merely returned by the parser.

## Validation performed

- `node --check static/guest-checkin.js`
- All JavaScript tests under `tests/*.js`, including the new noisy-OCR regression test
- `pytest -q tests/test_guest_checkin.py`
- Tests use synthetic/redacted sample values. This validates parser behavior in the test environment; it does **not** prove the result on every phone camera or lighting setup.
