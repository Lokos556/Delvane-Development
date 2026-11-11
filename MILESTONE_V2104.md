# Rosa V2.10.4 — Channex bulk rate-plan editor usability fix

- Replaced the legacy compressed grid behavior with an explicit stacked rate-plan card layout.
- Rate plan selection and remove action are grouped in a dedicated header.
- Date and pricing fields use a two-column layout; restrictions use a separate three-column layout.
- Explicitly resets the legacy `.ari-bulk-row` grid rule that caused controls to overlap.
- Preserves the existing Channex batch payload and validation behavior.
- 17 Channex/government regression tests pass.
