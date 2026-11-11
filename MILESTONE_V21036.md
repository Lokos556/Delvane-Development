# Rosa AI v2.10.36 — reservation consumes manual availability

Fixes Channex/PMS availability reconciliation when a room has multiple physical units but a date-specific manual availability override is lower than capacity.

Example: capacity 4 + manual availability 1 + one confirmed reservation now produces effective availability 0 (1 -> 0), instead of incorrectly keeping 1 via `min(manual, reservation_availability)`.

The same calculation is used when setting availability while a reservation already exists.
