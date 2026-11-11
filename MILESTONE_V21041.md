# Rosa v2.10.41 — Channex Test 9 date-specific availability fix

The Channex Test 9 regression is now explicitly covered in the release build.

- Room configuration remains independent from per-date availability.
- A manual availability override is treated as the number of units available before confirmed reservations consume inventory.
- A reservation therefore decrements the existing date-specific value instead of rebuilding availability from `inventory_count`.
- For the certification case, Double Room inventory is 4, Nov 25 is manually set to 1, and one reservation changes it to 0.
- The existing regression suite passes this scenario.
