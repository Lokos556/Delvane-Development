# Tasks 6–9 implementation

Date: 2026-11-19. Implemented actual guest lifecycle, ordinary Flutter controls, audited corrections/transfers and explicit day-use stays. Existing uncommitted work preserved. No persistent development workspace access/reset, government/Channex call, deployment, replacement credentials, commit or push. Official network transmission remains disabled.

## Backend and persistence

- **3078**: `stay_events`, `stay_event_guests`, `guest_occupancy` and indexes. Events preserve request identity/digest, actor/source/reason, actual UTC timestamp, property-local business date/timezone, sequence, correction link and encrypted original reporting facts. Current occupancy is a transactional projection; event history is never deleted. Reporting exclusions/corrections and recovery checks are explicit metadata.
- **3079**: per-job predecessor reference and `ntak_job_predecessors` dependency edges. A group event waits for every affected guest's predecessor, not merely the last group member. Corrections/replacements cannot overtake originals. Schema setup is repeatable through normal `init_db`.
- **3080**: explicit `reservations.stay_type` (default overnight), planned local arrival/departure times, and `day_use_allocations`. Same-day allocations have equal business dates and explicit timestamp windows, rather than being stored as false overnight stays. Existing overnight rows/history remain unchanged. Original reservation/provider identities and revenue are retained.

New backend modules: `guest_stays.py` and `day_use.py`. Relevant hooks extend `app.py`, `reservation_allocations.py`, `ntak_reporting.py`. A minimal supporting guest-profile field, optional `nationality_country`, lets an authorized operator explicitly resolve ISO2 nationality separately from residence and raw scanned nationality; no ICAO3→ISO2 conversion is invented. Increasing guest count now creates the expected registration slots in the same normal reservation update, allowing individual stay management for all expected guests.

## Operations and state transitions

| API | Meaning |
|---|---|
| GET `/api/reservations/{id}/actual-stay` | Per-guest expected/arrived/departed state, independent registration state, visits, planned units, actual occupant count, event/correction/reporting history |
| POST same path | Explicit observed arrival/departure, erroneous-event reversal, real transfer or latest-event timestamp correction |
| POST `/api/reservations/{id}/actual-stay/reporting-recovery/{event_id}` | Retry deriving a report from saved factual event after prerequisites are resolved; never resubmit a business action |
| GET `/api/operations/actual-occupancy` | Tenant-scoped current-day booking/actual occupancy summary, including overstays |
| Existing reservation POST/PATCH | Explicit `stay_type=day_use`, same-day dates, `planned_arrival_time`, `planned_departure_time`, physical allocations and ordinary booking fields |

Stay command: UUID `request_id`, `kind`, selected `guest_ids`, offset-aware `occurred_at`, `reason`, optional `unit_id`, `correction_of`, `corrected_at`. Kinds: `arrive`, `depart`, `undo_arrival`, `undo_departure`, `transfer`, `correct_timestamp`. HTTP uses the authenticated owner/manager as actor and `owner_review` source; callers cannot spoof integration/guest origin. Internal service supports separately authorized future sources, but no self-confirmation/smart-lock endpoint or unattended inference is enabled. Future adapters must perform their own source authentication before entering the shared service.

Expected → arrived requires an explicit physical observation and valid planned unit. Arrived → departed closes that guest's visit. Guests within one reservation can arrive/depart on different dates. Group operations require a compatible unit context and are all-or-nothing. Online registration, identity scanning, scheduled time and planned allocation changes alone create no arrival.

Property-first locking serializes capacity/conflict checks and writes. Duplicate request IDs replay the original result; reusing an ID for different facts returns409. Unit/property ownership, active versions, OOO/OOS, actual capacity, current other-party occupancy and chronology are checked. Actual dates are offset-aware and stored in UTC; business dates use organization/property operating timezone. Invalid or future actual timestamps are rejected. A booking with actual occupancy history cannot silently move properties; actual departures are required before cancelling an occupied booking.

## Automatic reporting and blockers

Normal actual operations save business event, occupancy projection and NTAK outbox/job in one transaction when reporting is enabled. Original guest/profile/unit facts are encrypted with the existing vault helpers. No guest names, profile values, salts or canonical identity strings are added to audit metadata or general diagnostics.

Frozen legitimate reporting IDs are reused. Missing first-time normalization, profile or nationality mapping produces a durable blocker; the physical business action still succeeds. When reporting is not configured, the factual event records that blocker for later recovery. The existing worker fairly revisits pending events; once prerequisites become available it builds a successor job without replacing the original encrypted event facts. Effective historical profile corrections can fill originally unavailable fields with their existing source provenance. Dependency edges are rewired to recovered jobs. No temporary guest identifiers are generated.

Transmission gates for signing, information-query response and other unresolved contracts remain. No actual SOAP call or official validation was performed.

## Corrections and actual transfers

Official basis: supplied interface v9.07 section7.4 pp50–51 and section9.4 pp88–89 describe opposite arrival/departure events and paired old/new unit transfer facts. The ES_02/ES_05 validation sequence ambiguity is not hardcoded into production behavior.

Erroneous arrival voids the projected visit, preserving the original event and audited correction. Erroneous departure restores the original visit after validating capacity/conflicts. Only the latest affected guest event can be reversed; older chained history requires reversing later actions first. No historical row is deleted to change the current state.

For an original known to have been submitted/processed, compensating reports are captured with causal dependencies. An event corrected before first submission is suppressed from sending, with no false counter-message requirement. For a partial correction of an unsent group, the valid remaining guests receive a replacement report while the erroneous guest is excluded through explicit correction metadata; the original encrypted facts remain retained. An uncertain original result is not assumed accepted or absent; its unresolved dependency prevents unsafe execution.

Latest original arrival/departure timestamps can be corrected through an audited counter/replacement pair. Older chained events and repeated corrections of replacement events are deliberately rejected rather than silently rewriting history. Corrections cannot create future times, reorder earlier guest events or place departure before arrival. These are error-correction operations, not new physical arrivals. Where no original was sent, only corrected valid facts need reporting.

A real transfer preserves source/destination occupancy segments and reports `lakoegysegetCserelt`. Moving all current occupants splits/replaces the source planned allocation; partial moves retain the source and add destination capacity as needed. The original booking remains one reservation. Task2 allocation checks and existing ARI queue reconciliation run transactionally; failures roll back the move, allocation history and reporting together. A planned allocation change emits no actual transfer.

## Day-use, channel inventory and cleaning

Official day-use basis: section9.2.11 pp75–76, `nappaliHasznalat`, and validation ES_06A/B and NZ_05. Actual history exposes guest-night differences using local dates; same-day completed visits have zero nights. A day-use visit crossing an actual night is flagged as a booking/fact mismatch; it is not silently forced to zero.

Day-use requires equal booking dates, explicit physical units, and a positive same-day local time window. Ambiguous/nonexistent local times at DST transitions are rejected. Timed physical and aggregate checks allow adjacent use and valid day-use-before-overnight coexistence, while rejecting overlaps and actual overstayers. OOO/OOS remains dated whole-business-day unavailability.

Direct booking conflict checks use actual planned windows. External room-type availability conservatively reserves day-use units for the business date through the existing quantity-aware ARI calculation; allocation demand replaces default booking demand, without double deduction. Multiple nonoverlapping day-use uses may therefore reduce published channel stock more than their direct peak occupancy. That conservative limitation is explicit in Flutter. No equivalent Channex same-day booking representation is asserted or pushed. Existing import parsers continue validating overnight semantics; unsupported same-day provider data is rejected/staged through their existing validation paths rather than converted to an invented overnight stay.

Day-use creates stable, per-reservation/unit cleaning tasks, earliest start at planned departure (or later actual departure), and a same-day next-stay deadline when known. Changed/cancelled allocations retain/cancel derived tasks appropriately; existing completed tasks remain history. A cleaner cannot start a day-use unit task while a guest still physically occupies it. This batch prepares facts only; no charge ledger, payment ledger or full daily closing was implemented.

## Flutter

`ActualStayDialog` provides individual/group arrival and departure, physical unit visibility, separate expected/registered/actual states, UTC event timestamps/local business dates, history, correction confirmations/reasons, real-transfer destination selection and specific reporting blockers. A single planned apartment is selected automatically. Forms use existing Delvane components/theme, required indicators and vertical responsive layouts.

The dialog is accessible from the normal reservation and identity-review screens. Expandable actual-occupancy panels are available in reception, Today and Operations, opening those same normal workflows. Reservation editor has explicit overnight/day-use selection and time fields; calendar includes same-day stays without extending their departure date. Hungarian copy and English source strings are provided. No reporting-payload editor was added.

## Verification

Task6 focused checks:3 passed before Task7. Task7 mobile/desktop explicit-arrival tests:2 passed before Task8. Task8 correction/transfer/timestamp suite:5 passed before Task9. Additional concurrency, rollback, group/partial-party, unsent-group correction and DST tests were then added.

Final verification: the selected backend regression command below passed **95 tests**. After the final reporting-order safeguards, the focused actual-stay/day-use/NTAK suite passed **28 tests**, including the additional uncertain-predecessor/processed-warning case (37.78s). Both runs reported two dependency deprecation warnings. Full Flutter tests passed **279 tests**, including three new mobile/desktop/day-use workflow tests; `flutter analyze` reported no issues. Final focused checks had no failures. Counts overlap and must not be added together.

Tests use fictional rooms101–104 and ordinary PMS operations. The combined offline case sequence covers ES_01A/B/C, ES_02/03/04A/04B/05; same-day two-unit tests cover ES_06A/B. Frozen hashes and processed responses used in those tests are explicitly offline fixtures; the genuine first-identity blocker is tested separately. No production logic contains validation guest names or booking IDs.

A new concurrency test initially exposed missing guest-slot creation when guest count increased; the normal update was fixed rather than weakening the test. The new same-day Flutter test required explicit mock responses for the new read endpoints and the editor's actual Save changes label; those fixture issues were corrected. Existing assertions were retained. The pre-existing test_v293 registration-status failure remains documented in Task2; it was not modified and was not included in this batch's selected regression command.

```powershell
Set-Location C:\Delvane\Delvane-Development
.\.venv\Scripts\python -B -m pytest tests/test_actual_stays.py tests/test_day_use.py tests/test_guest_reporting_profile.py tests/test_reservation_allocations.py tests/test_physical_units.py tests/test_normal_reporting.py tests/test_flutter_reservation_reception.py tests/test_flutter_distribution.py tests/test_guest_checkin.py tests/test_guest_checkin_lifecycle.py tests/test_persistent_development.py tests/test_ntak_reporting.py tests/test_v3000.py -q
Set-Location apps\delvane_business
flutter analyze
flutter test
```

No physical-device, Android build, Windows release build, PostgreSQL execution or genuine external acceptance result is claimed. SQLite concurrent claims and isolated restart persistence are tested. Tasks10–14 can now build ledgers and closing snapshots from the retained booking, allocation, effective guest profile and actual occupancy facts; official normalization/security contracts still gate affected reporting operations.
