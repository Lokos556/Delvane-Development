# Rosa AI v2.10.34 — cancellation historical-window reconciliation

## Fix

A reservation move can leave a stale Channex availability value on the old dates if an earlier
outbox delivery was missed or overwritten. Cancelling the reservation normally only knows its
current arrival/departure dates, so it could restore the current stay while leaving the old
dates stuck at 0.

Cancellation now reads the reservation's `updated` event snapshots and recalculates every
historical stay window recorded for that reservation, in addition to the current window.
This makes cancellation self-healing for missed reservation moves.

## Expected behavior

For a reservation moved from 25–26 Nov to 27–28 Nov, then cancelled:
- 25 Nov is restored to the room's real availability.
- 26 Nov is restored to the room's real availability.
- 27 Nov is restored.
- 28 Nov is restored.
