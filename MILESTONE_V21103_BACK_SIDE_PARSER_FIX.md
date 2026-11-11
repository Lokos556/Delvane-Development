# Rosa v2.11.03 — Reverse-side parser correction

- Fixed a side-state bug: front-specific clearing of `full_name` and `sex` and front-only field crops now run only on the front side, not on the reverse.
- Broadened Hungarian OCR label matching for place of birth and mother's birth name to tolerate common OCR substitutions and extra bilingual fragments.
- Rejects digit-containing / X-only values for mother's birth name instead of populating a visibly invalid value.
- Removes the trailing `(MAGYARORSZAG)` / `(HUNGARY)` from parsed place-of-birth values.

Validation: source-level syntax check and archive integrity check required; real-device OCR still needs testing. No claim of guaranteed recognition.
