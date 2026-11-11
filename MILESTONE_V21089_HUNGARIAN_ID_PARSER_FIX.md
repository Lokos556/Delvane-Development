# Rosa v2.10.89 — Hungarian ID OCR parser fix

Changes:
- Detect the sex legend even when OCR drops the first letter of `Nem/Sex` and outputs `em/Sex: F/M`; maps this card-specific legend to `M` rather than misreading `F` as the holder's sex.
- Tolerates common OCR corruption in the bilingual family/given-name label and extracts the following plausible name line.
- Recognizes OCR variants such as `Okményazonosité/Dac. No.` for document number extraction.
- Restricts the inline document-number token so text from the following `Signature` label is not appended.
- Keeps existing date-of-birth and nationality extraction logic unchanged.

Validation:
- Synthetic OCR regression test in `tests/test_v21089_hungarian_id_ocr.js`.
- Tests use synthetic identity values only. Real-device camera OCR and form population still require testing.
