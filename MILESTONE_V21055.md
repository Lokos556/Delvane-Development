# Rosa v2.10.55 — Synthetic MRZ OCR Benchmark

## Purpose
Adds a repeatable, privacy-safe image-level OCR benchmark using synthetic MRZ text strips only. This is a diagnostic baseline, not a claim of production-ready document recognition.

## Included
- `tests/generate_synthetic_mrz_benchmark.py`: deterministic generator and local Tesseract benchmark.
- `tests/synthetic_mrz_benchmark/images/`: 18 synthetic image fixtures covering TD1, TD2, TD3 and clean, low-contrast, blur, reduced-size, glare, and skew scenarios.
- `tests/synthetic_mrz_benchmark/results.json`: raw per-case OCR output and metrics.
- `tests/synthetic_mrz_benchmark/README.md`: readable benchmark summary.
- Bumped runtime version to 2.10.55 and guest-check-in asset cache versions to v4.

## Current benchmark baseline
- OCR engine: Tesseract 5.5.0 in the build environment.
- Cases: 18.
- Exact full text reads: 0/18 (0%).
- Mean character error rate: 10.3%.

This poor exact-match result is intentionally retained as a baseline rather than hidden. Most errors include ambiguous MRZ glyphs such as `O`/`0` and filler `<` characters. The benchmark uses DejaVu Sans Mono rather than an ICAO OCR-B font and does not evaluate card localization, perspective correction, or the browser's Tesseract.js runtime. It is therefore useful for tracking regressions and exposing weakness, but not a production accuracy metric.

## Validation
- `pytest -q tests/test_guest_checkin.py tests/test_v21042.py tests/test_v21046.py`: 5 passed.
- `node tests/test_guest_scanner_parser.js`: passed.
- `node --check static/guest-checkin.js`: passed.
- `python -m py_compile app.py`: passed.
- Synthetic benchmark generation: 18 cases completed.

## Limitations
- No actual Hungarian or EU identity-card template is represented.
- No real identity documents or personal data are used.
- Broad document support remains unverified. Do not claim production-ready Hungarian ID-card OCR from these results.
- No document image upload or persistent image storage was added.
