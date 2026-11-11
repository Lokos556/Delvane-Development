# Rosa v2.10.79 — preserve safe partial OCR results

- Preserve nationality and sex results when other fields cannot be confidently extracted.
- Keep implausible OCR name strings blank instead of inserting document headings into the name field.
- Do not report the entire side as unreadable solely because name extraction failed.
- Bumped guest-check-in JavaScript cache version to v22.

Validation performed: JavaScript syntax check and ZIP integrity. Not tested against a physical identity document or phone.
