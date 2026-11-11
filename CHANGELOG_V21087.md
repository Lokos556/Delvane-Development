# Rosa v2.10.87 — Hungarian ID label parser fix

- Added a tolerant fallback for the Hungarian ID name label when OCR badly mangles the bilingual heading, taking a plausible name from the following line.
- Added a direct parser for concatenated `Okmányazonosító` + `Doc. No.` labels, which can otherwise cause `Doc` to be misread as the document number.
- Preserved the existing capture-photo/loading workflow and existing date-of-birth and nationality parsing.
- The printed `Nem/Sex: F/M` legend remains intentionally unassigned: it lists possible values and does not identify the cardholder's sex.

Validation: JavaScript syntax check, synthetic parser test with noisy Hungarian label text, MRZ parser tests, and targeted Python tests passed. Real-device OCR and camera testing are still required.
