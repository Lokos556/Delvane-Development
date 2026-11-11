# Rosa v2.10.53 — Local OCR fallback for non-MRZ identity cards

## Changes
- Retains ICAO TD1/TD2/TD3 MRZ parsing and check-digit validation.
- Adds a local OCR fallback for readable printed text on non-MRZ cards, with label-based extraction for Hungarian and English field labels.
- Attempts `eng+hun` recognition for the printed-text and MRZ passes.
- Extracted OCR suggestions are explicitly marked for manual review; they are not treated as verified identity.
- Guest-facing instructions now explain that printed text can be scanned and the image remains on the device.
- Bumped guest-check-in asset cache versions and Rosa runtime version to 2.10.53.

## Limitations
- This is an OCR-assisted fallback, not a validated document-template reader. Layouts vary by issuing country and card generation; all values must be checked by the guest and subsequently verified by the property owner.
- No image upload or persistent document-image storage was added.
