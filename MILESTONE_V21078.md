# Rosa v2.10.78 — Conservative name validation

This build preserves the faster single-pass OCR path and tightens full-name validation. Visible OCR and MRZ-derived names must look like plausible person names; heading-like text and concatenated OCR noise are rejected. This intentionally prefers a blank field over a false name.

Validation performed: JavaScript syntax check and ZIP integrity check. No physical ID or phone performance test has been performed.
