# Task 2 reservation physical allocations

Implemented 2026-11-19. Scope is planned overnight reservation allocations, not actual stays or NTAK transfers. Existing uncommitted work preserved. No Flutter changes, SOAP, guest events, day-use or ledger implementation.

## Database and API

Migration **3075** creates `reservation_unit_allocations`, conflict/reservation indexes and a migration marker through normal `init_db`. Each record stores stable reservation, property/tenant, physical unit and local room-type IDs; half-open overnight interval `[date_from,date_to)`; original booking date snapshot; active/superseded/cancelled state; actor/time/reason and retirement provenance. No legacy/imported reservation is automatically assigned a physical room; no booking/provider references change. Repeat migration does not erase history.

- `GET /api/reservations/{reservation_id}/allocations`: active assignments and complete superseded/cancelled history.
- `PUT /api/reservations/{reservation_id}/allocations`: replace the complete planned allocation set transactionally. Body: `allocations: [{unit_id,date_from,date_to}, ...]`, `reason`. Empty list removes assignments. Repeating the same set is idempotent. Reassignment uses the same endpoint and preserves the previous records.
- Existing reservation PATCH automatically resizes full-stay allocations when dates change, validating the new interval first. Split-date assignments must be removed before changing booking dates; no guessed redistribution. Guest-count changes use assigned physical sleeping capacity when assigned.
- Existing cancellation/status transitions retire active records. Date/property/type revalidation also runs during the existing availability queue path used by provider changes; unallocated imports retain normal behavior. Assigned property/primary-type changes require explicit unassignment first.

Owners/managers use existing reservation permissions and CSRF. Every allocation unit must belong to the booking's property and organization. Property locks precede reservation locks, matching physical-unit write serialization. All validation, retirement/new rows, reservation mutations and ARI queue work occur in the same database transaction. Physical-unit detail/OOO/OOS edits also revalidate active allocations and roll back incompatible changes. No actual room-transfer event is emitted.

## Capacity and inventory rules

Each allocation must be inside the booking's overnight interval. Effective physical versions must remain active and have a consistent room type throughout each allocation (split at a type-change boundary). Both OOO and OOS nights block assignments; inclusive Task1 maintenance dates intersect half-open occupied nights, so maintenance on checkout date alone does not block the preceding stay. Duplicate overlapping rows and conflicts with other confirmed bookings are rejected. Sleeping capacity includes the explicit regular and extra places available on each assigned night.

**One shared aggregate demand calculation** now backs `_reservation_availability`: on each night, a booking with assignments consumes the number of assigned units in each local room type; on an unassigned night it consumes its legacy one-unit primary-type demand. The assignments replace the default; they are not added to an already deducted reservation. Allocation removal restores default demand. Same-type unit reassignment leaves quantity unchanged. Legacy/imported unallocated reservations remain one unit and need no physical identities.

Multi-type allocation changes queue recalculated availability through `_queue_reservation_availability` and the existing durable ARI outbox. Date/cancel reconciliation includes historical allocation room-type windows so released secondary types reopen. The allocation API never changes provider mappings or aggregate inventory_count, and never sends external requests itself. Normal reservation routes retain their existing delivery behavior. No test contacted any provider.

Aggregate capacity limits and operational physical availability are both checked when assigning: outstanding unallocated booking demand cannot silently disappear to make a physical assignment fit. Mismatched inventory needs explicit reconciliation; physical units are not added to aggregate stock. A primary type may be replaced by other allocated types, but all must be valid active types for the same property, and each quantity is checked against its own stock. No arbitrary cross-property fallback.

## Verification

Commands from repository root:

```powershell
.\.venv\Scripts\python -B -m pytest tests/test_reservation_allocations.py -q
.\.venv\Scripts\python -B -m pytest tests/test_reservation_allocations.py tests/test_physical_units.py tests/test_flutter_reservation_reception.py tests/test_flutter_distribution.py tests/test_persistent_development.py tests/test_v3000.py -q
```

Tests cover fictional 101–104 inventory, one booking with103+104, quantity accounting, mixed-type reconciliation, sleeping capacity, reassignment history, same-date conflict, adjacent stays, OOO/OOS and inverse maintenance guard, failed multi-row/date updates rolling back, split intervals, cancellation/restart persistence, repeat migration, cross-property/role/CSRF checks and two simultaneous claims for one unit (one saved, one409). Database/network guards remain enabled.

Results: **50 passed** in the focused allocation/physical/reservation/distribution/persistent-workspace/v3000 regression command, including **8 allocation tests**. Final allocation suite rerun after the last validation refinement: **8 passed**. Diff whitespace check clean. An additional legacy Channex suite `tests/test_v293.py` produced one failure in `test_modification_preserves_manual_fields_and_cancellation_updates_cleaning`: registration expected complete but returned incomplete. The identical failure was reproduced using the untouched committed `app.py`/test in an isolated baseline copy, establishing that it predates Task2. It was not hidden or changed to pass. The rest of that broader run passed52 tests before the final two allocation tests were added. Two existing FastAPI/Starlette dependency deprecation warnings remain.

## Limits and readiness

- No physical assignment is mandatory; aggregate booking operations remain valid without it. Assignment is a normal backend reservation operation; Flutter controls are outside this task.
- OOO/OOS do not independently change published channel stock in this task. They block physical assignments and expose contradictions; publication remains driven by existing aggregate stock plus quantity-aware reservations. A later explicit inventory reconciliation policy is still needed for automatic maintenance-based channel closures.
- An assigned booking whose provider change cannot be reconciled is rejected/rolled back for operator review; no arbitrary reassignment or silent loss of physical history. Full import behavior is unchanged for unallocated bookings.
- No automatic downgrade/reallocation on unit deactivation, type or sleeping-capacity reduction. Conflicting physical edits are rejected.
- Split-date reallocation sequences are planned reservation history only, not real room-transfer/arrival evidence.
- SQL uses the existing SQLite/PostgreSQL adapter; concurrent SQLite writes tested. No PostgreSQL service or physical device tested.
- Historical type/capacity changes preserve Task1 version records; history links to those dated identities. No per-guest unit occupancy yet.

Task3 can add ordinary reservation reporting fields to create/edit/import capture using the same booking identity. It must derive reportable unit data from the allocation set where present and explicitly block missing facts; it must not require manual reporting-only payloads or infer actual guest arrivals.

Task2 changed: `reservation_allocations.py`, `app.py` (migration/router, locking, quantity-aware overlap/ARI and booking lifecycle hooks), `physical_units.py` (inverse validation), `tests/test_reservation_allocations.py`, `VALIDATION_READINESS.md`, this report. Persistent development workspace not accessed/reset; no credentials, external endpoints, deployment, commits or pushes.
