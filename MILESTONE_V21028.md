# Rosa AI v2.10.28 — Channex availability delta diagnostics

## Changes

- Added explicit handling for an unchanged Channex ARI availability value.
- An unchanged availability value now returns `no_change: true` and does not create a duplicate `/api/v1/availability` request.
- The UI now shows **No update sent** instead of incorrectly presenting a successful “Update delivered” state when zero Channex requests were generated.
- The message explains how to create a real availability delta for certification testing.
- Added regression coverage for availability-only updates and unchanged-value no-ops.

## Channex Test 9

The certification scenario requires real availability transitions:
- Twin Room: 8 → 7 on 2026-11-21
- Double Room: 1 → 0 on 2026-11-25

If the requested value is already stored in Rosa, no API call should be emitted. Change the underlying PMS availability first, then perform the transition.
