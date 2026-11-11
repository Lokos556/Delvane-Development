# Rosa v2.10.36 — certification reservation availability reconciliation

Fixes the legacy Channex certification availability state where effective availability
was incorrectly copied into `manual_availability`. That stale manual value could keep
an old reservation date at 0 after a reservation was modified or cancelled.

On startup, the migration repairs the dedicated Channex certification property only,
recomputes reservation-derived availability, and queues the corrective Channex delta.
Normal properties and explicit manual availability are not changed.
