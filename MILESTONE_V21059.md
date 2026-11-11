# Rosa v2.10.59 — Automatic Guest Scanner

## Changes
- Scanner now starts automatic capture immediately after camera permission is granted; no separate "auto-capture" concept or manual "Scan now" button is shown.
- Stability and basic scene visibility are checked continuously before a capture is attempted.
- Image-quality heuristics are advisory rather than a hard stop: OCR is attempted even when the heuristic suspects poor exposure/contrast, avoiding rejection of readable cards based on a coarse whole-image score.
- Instructions specifically advise Hungarian ID users to try the reverse side with machine-readable lines where present, while keeping visual-text OCR/manual correction as fallback.
- Pause scanning control is available.
- Cache-busting versions bumped for guest scanner JS/CSS; app version bumped to 2.10.59.

## Privacy and limitations
- Captured image is still processed locally in the browser and is not sent to Rosa as an image.
- Automatic capture currently uses image stability and basic visibility/contrast heuristics; it is not a certified document-edge detector. It can still capture an unsuitable frame in some conditions, after which OCR can fail and the guest may retry or enter data manually.
- Hungarian ID recognition depends on card generation, side, OCR quality and available machine-readable lines. No universal support claim is made.

## Validation
- `node --check static/guest-checkin.js`: passed
- `node tests/test_guest_scanner_parser.js`: passed
- `pytest -q tests/test_guest_checkin.py tests/test_v21042.py tests/test_v21046.py`: 5 passed
