# Rosa v2.10.91 — Name and date-of-birth label fix

Based on v2.10.90. Changes to `static/guest-checkin.js`:
- Broadened the noisy Hungarian/English name-label fallback to handle OCR output such as `Csaladi gs akong Fag. pane arid Gil nam`, then take the next plausible name line.
- Broadened date-of-birth label matching to tolerate OCR variants such as `Sailetesiido/Date o birth`, including a missing `f` in `of`.
- Updated the name fallback's stopping condition so it recognizes OCR-mangled date-of-birth labels rather than scanning past them.

Validation performed:
- `node --check static/guest-checkin.js`
- `node tests/test_v21091_noisy_name_dob.js` (synthetic OCR only)
- `node tests/test_mrz_parser.js`
- `pytest -q tests/test_guest_checkin.py`

Real-device camera OCR and actual form population remain unverified until tested on the user's phone.
