# Rosa V2.10.1 — Channex Certification Readiness

## Delivered

- Added an owner/manager-triggered Channex Full Sync endpoint and UI action.
- Full Sync covers exactly 500 future days and produces two durable outbound jobs:
  - `/api/v1/availability`
  - `/api/v1/restrictions`
- Full Sync uses the current Rosa base price, date overrides, availability, and restrictions instead of hardcoded certification values.
- Channex task IDs remain stored in `channel_ari_outbox` for certification evidence.
- Added explicit HTTP 429 handling with `Retry-After` support.
- Added a persisted minimum 60-second rate-limit pause for affected Channex property mappings.
- Preserved the existing incremental ARI queue and six-second endpoint pacing.
- Added regression tests for Full Sync and 429 handling.
- Fixed the stale webhook test expectation and the V2.9.7 migration test's raw-SQLite row handling.

## Verification

Full automated test suite:

`130 passed (full suite)`

## Not yet production

- Channex production certification has not been submitted.
- Booking.com production authorization has not been enabled.
- NTAK/VIZA transport certification remains a separate workstream.
