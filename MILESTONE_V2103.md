# Rosa V2.10.3 — Channex bulk rate-plan UI redesign

- Rebuilt the owner-facing bulk rate & restriction editor for readability and practical use.
- Replaced the cramped multi-column/empty-control layout with clearly labeled rate-plan rows.
- Each row now exposes rate plan, date range, nightly price, minimum stay, stop sell, closed-to-arrival, and closed-to-departure controls.
- Added add/remove row controls, row count, validation, duplicate-rate-plan protection, and clear "Keep current" behavior.
- Preserved the existing Channex batch API and one-request-per-batch behavior.
- Responsive layout remains usable on narrower screens without forcing the entire modal to become a giant table.
