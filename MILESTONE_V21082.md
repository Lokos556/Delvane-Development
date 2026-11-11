# Rosa v2.10.82 — Raw OCR diagnostic

Purpose: determine whether Tesseract recognizes usable text from the camera image before Rosa's parser handles it.

- Displays the exact text returned by the existing local Tesseract worker in a developer diagnostic panel after a scan.
- Displays OCR elapsed time and line count.
- Raw OCR text is held in browser memory and rendered locally only. This code does not send the raw text to the server or log it to the console.
- The output may contain sensitive identity data. Do not share it unredacted; remove names, document numbers, dates, nationality and other personal details before sending diagnostics.
- Does not change field parsing or recognition strategy.

Checks to run: `node --check static/guest-checkin.js`, verify ZIP integrity. Physical-device OCR accuracy is not established by these checks.
