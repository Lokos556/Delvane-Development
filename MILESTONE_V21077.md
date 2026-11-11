# Rosa v2.10.77 — conservative whole-document OCR

- Changed capture input to the full camera frame so the guide crop cannot exclude visible fields.
- Tightened visible-field extraction: labels must begin a line and be followed by a delimiter; rejects document headings as names.
- Unknown three-letter nationality codes are no longer displayed as if they were recognized nationalities.
- MRZ-derived names containing document-heading terms are discarded.
- Preserves local OCR and no new paid dependencies.

Validation: JavaScript syntax and archive integrity checked. Not physically tested against an ID or phone.
