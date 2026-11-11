# Rosa V2.10.13 — Reservation availability delivery visibility

- Version: 2.10.13.
- Reservation-triggered Channex availability now waits briefly for durable outbox delivery and surfaces the actual Channex task ID even when the endpoint throttle temporarily queues the update.
- Added a reservation-specific delivery status endpoint for recovering sent/pending availability task IDs from the real PMS outbox.
- Clarified reservation room selector labels as inventory capacity, avoiding confusion with date-specific available inventory.
- Removed a duplicate reservation DELETE call.
