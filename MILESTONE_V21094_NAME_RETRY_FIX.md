# Rosa v2.10.94 — Name-region OCR and retry recovery

- Wrapped canvas capture/encoding and OCR setup in the capture try/finally path so early failures still restore the capture button.
- Added a 60-second OCR timeout with a retry message.
- Prevented the finally block from overwriting the meaningful error/status message.
- Added a separate enlarged OCR pass over the expected Hungarian ID name area; it replaces the full-frame name only when it yields a plausible name.
- Kept the existing full-frame parser and successful extraction logic for DOB, sex, nationality, and document number.

Validation: JavaScript syntax check, synthetic noisy OCR regression, MRZ parser regression, guest check-in backend test, and capture/name retry assertions pass. The separate name-region pass has not been validated against live phone-camera captures; real-device verification is still required.
