# Rosa AI v2.10.29 — reservation cancellation availability reconciliation

## Fix

Reservation cancellation now forces one Channex availability reconciliation for the affected stay window.

Previously, if Rosa's local effective availability had already been recalculated to the post-cancellation value, `_queue_reservation_availability()` treated the state as unchanged and emitted no outbound request. That could leave Channex stale after a missed/failed availability transition.

The fix is intentionally narrow:
- normal reservation creation/change keeps delta behavior;
- cancellation forces the recalculated availability through the durable Channex outbox;
- Channex delivery still uses the existing retry/throttle system;
- no duplicate requests are generated merely by normal local recalculation.

## Regression coverage

Added a test where the post-cancellation local availability already equals the expected value, and verified that cancellation still sends exactly one Channex availability request for the affected date.
