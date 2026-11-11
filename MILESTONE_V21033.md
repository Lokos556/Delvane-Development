# Rosa AI v2.10.33 — stale availability queue reconciliation

## Fix

Reservation create/update/cancel actions can generate multiple availability outbox jobs. Previously, an older queued/retry job could be delivered after a newer reservation change and overwrite the newer Channex inventory state because Channex processes availability updates with last-write-wins semantics.

v2.10.33 now coalesces all queued/retry `/api/v1/availability` jobs for an integration immediately before delivery. Ranges are expanded per room/date, later queued changes win, and the resulting authoritative state is sent as one availability request. This prevents stale reservation transitions from reopening/closing the wrong dates at Channex.

## Regression coverage

Added a regression test proving that a queued 0-availability update followed by a newer queued 1-availability update for the same room/date results in one outbound request containing only the newer value.

The existing v2.10.32 reservation-move test remains green: moving Double Room from 25–26 November to 27–28 November produces one request that releases 25 November and consumes 27 November.
