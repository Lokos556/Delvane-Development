# Rosa V2.10.25 — Channex delivery diagnostics

## Purpose
Operator-focused follow-up to V2.10.24 after a durable Channex ARI job remained in retry.

## Changes
- Adds a safe Channex ARI outbox status endpoint showing endpoint, status, attempt count, retry timing, and last provider error without exposing credentials or payloads.
- Adds an owner/manager “retry pending now” action that requeues pending ARI jobs and drains them immediately.
- Adds a Delivery Diagnostics panel to the Channex distribution modal.
- Distinguishes the pending queue state from successful delivery instead of relying on the generic activity log.
- Bumps the visible/application version to 2.10.25.
- Retains the V2.10.24 Channex date serialization fix.

## Verification
- `python -m py_compile app.py` passed.
- Channex-related regression tests: 7 passed.
