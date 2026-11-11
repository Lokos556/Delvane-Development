# Rosa V2.6.2 test notes

Primary local-first routing checks:

- Exact Wi-Fi/property fact → `DATABASE`, OpenAI callback not invoked.
- Tomorrow/operations summary → `OPERATIONS`, OpenAI callback not invoked.
- Cleaning reassignment → `ACTION ENGINE`, OpenAI callback not invoked.
- Free-form ambiguous reasoning → `LUNA` only when OpenAI fallback is configured.
- Same free-form request without API configuration → `LOCAL FALLBACK`.
- Schema 2620 and `rosa_ai_routes` logging verified.
- Existing security, tenant-isolation, reservation sync, operations, maintenance, and V2.6 governed-action suites preserved.

Automated suite: 51/51 passed.
