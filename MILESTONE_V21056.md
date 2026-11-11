# Rosa v2.10.56 — MRZ OCR tuning

## Changes
- Added an MRZ-specific browser OCR pass using the ICAO MRZ alphabet (`A-Z`, `0-9`, `<`).
- Disabled Tesseract dictionary bias for MRZ OCR and preserved inter-character spacing.
- Runs tuned OCR against the original capture, enhanced/upscaled image, and lower MRZ crop; generic English/Hungarian OCR remains available for visible-field fallback.
- Bumped guest check-in JS cache key and application version.
- Added an apples-to-apples benchmark comparison for default Tesseract settings versus MRZ-specific whitelist/dictionary settings across 18 synthetic TD1/TD2/TD3 image conditions.

## Benchmark
- Baseline: 0/18 exact reads; mean character error rate 10.34%.
- MRZ-tuned: 0/18 exact reads; mean character error rate 8.37%.
- This is a 19.0% relative reduction in character error rate on this synthetic text-strip benchmark, but no case reached a fully exact read.
- These results use the local Tesseract CLI and synthetic monospaced MRZ strips. They do not prove browser Tesseract.js accuracy or real document-layout accuracy.

## Validation
- `node --check static/guest-checkin.js`
- `node tests/test_guest_scanner_parser.js`
- `python -m py_compile app.py`
- Targeted pytest tests run separately; full repository suite not claimed.
