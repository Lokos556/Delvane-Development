# Rosa v2.10.98 — Scanner timeout recovery

## Changes
- Added a shared timeout helper for OCR operations.
- The main document OCR timeout now terminates the active Tesseract worker before allowing a retry, rather than leaving a timed-out worker running in the background.
- Added a 12-second timeout to the optional name-region OCR pass. If that pass stalls, Rosa keeps the full-frame result and resets the worker so the scan UI can recover.
- Preserved the current workflow: capture a still image immediately on tap, show progress, populate only the existing guest fields, and do not display document expiry in the guest form.
- Bumped guest check-in asset query versions to avoid stale browser cache.

## Validation scope
- JavaScript syntax and existing parser/scanner regression tests are run for this package.
- Timeout behavior is protected by explicit control flow but has not been verified on a physical phone/camera in this environment.
