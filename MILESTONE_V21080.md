# Rosa v2.10.80 — OCR diagnosis without personal data

This build corrects the previous ZIP's project-folder naming and adds useful on-device diagnostics to the single-pass OCR path.

The diagnostic summary reports OCR duration, count of text lines, candidate MRZ line lengths, MRZ check status, and which field types the parser extracted. It does not display or log recognized personal data.

This is a diagnostic build, not a claim that extraction accuracy has been fixed. It is intended to identify whether the OCR engine is failing to read text or whether the field parser is rejecting text it did read.

Validation performed: JavaScript syntax check and ZIP integrity. Not tested on a physical identity document or phone.
