# Rosa v2.10.85 — Still-photo ID scanning and real field population

## Changes
- Replaced the 2.5-second automatic steady-frame wait with a deliberate still-photo workflow: open the camera, frame the document, tap **Capture ID photo**, then let local OCR run while the loading overlay is visible.
- Kept the captured image local to the phone; no document image upload was added.
- Changed OCR application to write recognized values into the existing form controls instead of re-rendering the entire check-in page. This preserves the live status/camera DOM and makes actual field assignment explicit.
- Added a bilingual-label-aware date finder so a Hungarian/English date-of-birth label can still find its date when OCR recognizes only the first half of the label.
- Removed the expiry-date field from the guest-facing form and from the guest check-in submission payload. Expiry may be recognized internally but is not requested from the guest.
- Kept uncertain results editable for guest review; no OCR result is silently treated as verified identity data.

## Validation
- `node tests/test_guest_scanner_parser.js` — passed.
- `pytest -q tests/test_guest_checkin.py` — passed.
- `python -m py_compile app.py` — passed.

## Manual device test still required
Automated tests do not prove camera behavior or OCR accuracy on a real Hungarian identity card. Confirm on the phone that tapping Capture ID photo immediately captures the frame, the loading overlay appears, and recognized values populate the visible fields. Verify date of birth carefully before guest confirmation.
