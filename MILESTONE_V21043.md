# Rosa v2.10.43 — Channex Test 9 remote-baseline fix

## Problem

Channex Test 9 can be prepared directly in the Channex staging UI by setting Double Room availability to `1` on 25 November while the room type remains configured with four units for other certification tests. Rosa previously calculated the reservation delta from its local four-unit inventory and could therefore send `3`, which Channex rejected when the current channel availability was `1`.

## Fix

- Certification-workspace reservation creation now reads the current Channex room availability for the affected stay dates.
- The returned channel availability is stored as the date-specific manual baseline in Rosa.
- The newly created reservation then consumes that baseline, producing `1 -> 0` on 25 November.
- The existing stale queued/retry cleanup remains in place, preventing an older `4` update from being merged into the fresh reservation update.
- Production integrations are unchanged: this remote-baseline read is scoped to the disposable certification workspace.

## Verification

- `tests/test_v21042.py`: 2 passed.
- The broader suite reaches existing legacy-version assertions unrelated to this change; the first such failure is `tests/test_v25.py`, which expects runtime version `2.10.27` while this release is already `2.10.42`.
