# Rosa v2.10.92 — Nationality and full-name parser fix

Based on v2.10.91. Changes:
- Nationality extraction now isolates a standalone three-letter country code (e.g. HUN) before normalization, so adjacent OCR noise such as "HUN Eis" does not make nationality normalization fail.
- Added a Hungarian-ID-layout fallback for a badly distorted bilingual name label like "Csaladi és E6navI Fam pate 3 d.Gilugn"; it inspects the following line and only accepts a plausible multi-part person name.
- Preserved existing date-of-birth, sex-legend, and document-number parsing.

Validation:
- JavaScript syntax check passed.
- Synthetic OCR regression test passed for name, nationality, DOB, document number, and sex.
- MRZ parser regression tests passed.
- Guest check-in backend test passed.
- ZIP integrity check passed.

Real-device camera OCR and DOM form population still require validation on the user's phone.
