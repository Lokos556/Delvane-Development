# Rosa AI v2.10.32 — atomic reservation-move availability sync

## Fix

When a Rosa reservation is moved to different dates, inventory changes on both sides of the move:
- the old stay must be reopened;
- the new stay must be consumed.

Previously Rosa queued those as two immediate Channex `/api/v1/availability` requests. That allowed a partial remote state where the new dates updated but the old dates remained closed.

V2.10.32 now:
- detects availability-affecting reservation changes;
- recalculates both the old and new stay windows;
- forces both transitions to be reconciled;
- merges the resulting availability values into one Channex availability request per integration;
- avoids sending availability updates for edits that cannot affect inventory (for example, a guest-name-only edit).

Cancellation reconciliation remains forced as in v2.10.29.

## Regression coverage

Added `tests/test_v21032.py`, which verifies that moving a Double Room reservation from 25–26 November to 27–28 November produces one Channex availability request containing:
- 25 November → 4 available;
- 27 November → 3 available.
