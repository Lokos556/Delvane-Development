# Rosa v2.11.01 — Field-isolated Hungarian ID OCR

## Algorithm changes
- Crops the pixels inside the on-screen document guide before the main OCR pass, rather than OCR-ing the full camera scene.
- Stops trusting the whole-frame OCR for full name and sex. Those fields are cleared before targeted recognition.
- Reads the printed name-value row as a dedicated normalized crop, enlarged 3x and processed as grayscale/contrast-stretched and Otsu-binarized variants.
- Uses a narrow character whitelist and single-line page segmentation for field crops.
- Accepts the name only if it is structurally plausible and not a country/header/label fragment; otherwise leaves it blank for manual correction.
- Reads the Hungarian Nem/Sex region independently, using the card's N/F (female) and F/M (male) convention. Sex is accepted only on variant agreement or high OCR confidence.
- Existing date of birth, nationality and document-number extraction is retained from the guide-cropped full-document OCR.
- No document image or recognized personal data is uploaded by this change; field diagnostics record confidence/acceptance only.

## Validation scope
- Run the existing parser regression tests and JavaScript syntax checks.
- OCR accuracy must still be verified on a physical phone/camera with real captures; the synthetic parser tests do not establish camera OCR accuracy.
