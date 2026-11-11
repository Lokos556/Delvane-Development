# Rosa V2.10.10 — Channex certification decimal-rate fix

- Version: 2.10.10.
- Fixed the certification workspace bulk ARI editor rejecting decimal USD prices with an `Object`/Pydantic error.
- Certification workspace now labels prices as USD and accepts two-decimal values such as 456.23.
- Decimal certification rates are converted to Channex minor units (456.23 -> 45623).
- Existing certification test rate state is normalized on upgrade.
- Improved API validation errors so structured FastAPI errors are shown as readable messages instead of `[object Object]`.
- Existing HUF integrations retain their previous rate handling.
