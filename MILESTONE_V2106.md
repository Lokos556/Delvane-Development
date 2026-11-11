# Rosa V2.10.6 — room types and complete Channex restrictions

- Added first-class local room types under each Rosa property.
- Existing properties are migrated safely to one default room type with inventory 1.
- Existing reservations and rate plans are attached to the migrated room type.
- Reservations can now select a room type and availability uses room-type inventory counts.
- Added Channex room-type mappings and automatic staging mapping for newly created room types.
- Added explicit Channex `min_stay_arrival`, `min_stay_through`, and `max_stay` support.
- Kept the legacy `min_stay` field as a backwards-compatible arrival-based alias.
- Added all three restrictions to single-date/range and bulk distribution controls.
- Full Sync now publishes availability per mapped room type and all three minimum/maximum stay restrictions.
- Channex booking routing now resolves incoming room types to Rosa room types; multi-room bookings spanning multiple room types are rejected rather than silently misclassified.
- Version: 2.10.6 / schema 3030.
