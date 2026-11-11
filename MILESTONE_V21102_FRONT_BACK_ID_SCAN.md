# Rosa v2.11.02 — Front/back identity scan flow

- Adds a two-stage capture flow: front first, then explicitly prompts the guest to flip and capture the back.
- The camera stays active between sides, avoiding a second camera-permission prompt.
- Parsed fields from the second side merge into the existing form; blank OCR results do not overwrite non-empty visible inputs because `applyParsed` only writes non-empty values to controls.
- Existing visible-text parsers already include place-of-birth and mother's-name label patterns, and MRZ parsers include TD1 three-line support. The reverse scan now gives those parsers the reverse-side image to work on.
- If the front cannot be read, the workflow still proceeds to the back and allows manual correction.
- No document photos are uploaded by this UI; OCR remains local in the browser as in the previous version.

Validation: syntax and archive checks only. Recognition of a specific Hungarian ID's reverse-side layout still needs real-device testing; field crops and MRZ detection may need tuning based on redacted OCR diagnostics.
