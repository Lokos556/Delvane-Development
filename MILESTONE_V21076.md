# Rosa v2.10.76 — Faster single-pass OCR and partial MRZ extraction

Changes:
- Removed automatic second OCR pass over an enhanced copy of the same capture.
- Removed automatic full-frame OCR fallback after the guided whole-document capture; retry is explicit.
- Switched general page segmentation from sparse-text mode (PSM 11) to block-text mode (PSM 6) for document captures.
- Structurally plausible TD1/TD2/TD3 candidates can populate fields for user review even when not all MRZ check digits validate.
- Date of birth is only populated from MRZ when its own check digit validates; document number is only populated when its own check digit validates.
- Exhaustive character-correction search no longer runs when a structurally plausible MRZ candidate exists, avoiding expensive mobile computation.
- Diagnostic messages include OCR pass timings; no recognized personal data is logged.

Validation performed: JavaScript syntax and ZIP integrity. Not physically tested on a phone or against a real identity document.
