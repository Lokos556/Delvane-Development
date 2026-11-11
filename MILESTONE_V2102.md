# Rosa V2.10.2 — Channex certification readiness

- Added durable per-rate-plan Channex ARI state.
- Added real multi-rate batch updates from the PMS API, producing one `/api/v1/restrictions` request for multiple rate-plan changes.
- Channex 500-day Full Sync now uses per-rate-plan overrides and restrictions when present.
- Preserved the existing single-rate update path, booking feed/ACK, webhook path, 429 backoff, and 500-day full-sync workflow.
- Updated runtime/schema to 2.10.2 / 3020.
- Certification remains a real-PMS UI process; no standalone certification script or test-only transport was added.
