# Rosa v2.10.75 — safer field mapping and faster scan loop

- Nationality is a selector with broad ISO alpha-3 country-code mapping and human-readable nationality labels; HUN maps to Hungarian, BRA to Brazilian, KOR to South Korean.
- Visible OCR no longer fills date of birth from an unlabeled date elsewhere on the card. A DOB must be explicitly labelled in visible text or come from a validated MRZ.
- Removed duplicate MRZ OCR pass on the same image; general OCR output is checked for a validated MRZ as part of that pass.
- Removed the third OCR pass over the same enhanced frame. At most two full-document recognition passes per captured image.
- Failed scans no longer automatically trigger repeated OCR every few seconds. Camera preview remains available and user can explicitly retry after adjusting/turning over the document.
- Checks: JavaScript syntax and ZIP integrity. Real-device scan accuracy/performance not verified here.
