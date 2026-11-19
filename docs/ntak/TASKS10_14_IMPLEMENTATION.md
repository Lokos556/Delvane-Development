# Tasks 10-14 implementation checkpoint

Date: 2026-11-19. Normal financial operations, business-day closing and full source-derived reporting revisions are implemented. This is offline development evidence, not official certification. See [NTAK_HANDOFF.md](NTAK_HANDOFF.md) for the self-contained resume point and all 27 official cases.

## Resume and repository state

The interrupted work contained `financial_ledger.py`, two passing ledger tests, migration3081 and the table-only calendar/snapshot scaffold3082. That work was extended, not replaced. The first unsuccessful patch had applied no changes. Existing Tasks1-9 and unrelated changes were preserved.

Initial HEAD was main/9d0503a. During work an externally created save commit a5282b6 appeared; it was preserved. The agent did not commit, push, deploy, start the development launcher or access the persistent development database. Only repository pytest isolation was used. No government/Channex network call or real credential read/replacement occurred. Flutter/Dart toolchain versions were unchanged.

## Task 10: authoritative itemized ledger

`financial_ledger.py` stores append-only charges/payments with exact Decimal arithmetic, six decimal places for quantity/unit price, two decimal places for line/currency/HUF amounts and ROUND_HALF_UP after multiplication. Exchange rates retain eight decimal places. JSON monetary inputs and persisted amounts are strings, never binary floats. Nonfinite/negative/oversized values, invalid classifications and invalid associations are rejected. Non-HUF entries require an explicit evidenced conversion rate; no rate is downloaded or invented.

Official charge category/subcategory pairs come from interface9.07 appendix12.3 pp243-249; VAT and payment enums come from the unchanged embedded daily-close XSD. Quantity, gross unit price, package inclusion, VAT, IFA, business/document dates, booking/property/unit/guest links and actor/source/reason are retained individually. No official fixture data is in production logic. The test-only `tests/fixtures/ntak_official_charge_lines.json` retains worksheet rows2-70 and source cells: all69 lines total28467.00 HUF. Discretionary worksheet VAT/package choices are explicit in the fixture; mandatory IFA0%/outside and accommodation5%/inside are preserved.

The first normal posting activates a booking folio and retains the original quote separately. Once activated, reservation `total_huf` is a whole-HUF compatibility projection of the exact active ledger and payment status derives from the balance. Existing summary consumers therefore do not add booking totals and ledger charges twice. Legacy unitemized quotes remain usable but cannot masquerade as a complete closing ledger. Normal total/payment-status overrides are rejected on managed folios. Channex revisions retain their existing feed history and audit a quote conflict rather than overwrite posted finances; availability/allocation calculations are unchanged.

## Task 11: settlements and normal Flutter operations

All seven payment methods and the SZEP_KARTYA/SZALLASHELY subtype are supported. Partial payments, overpayments, refunds, reversals, replacement corrections and post-departure postings retain history. A refund can link its original payment; reporting reduces the original day's spending through a full source correction, never a fabricated negative current-day report. Unlinked legacy refund records remain operationally visible with a specific reporting blocker until corrected/linked. Linked refund limits and original-payment correction constraints are checked transactionally.

`financial_controls.dart` provides a reservation folio, totals, categorized charges, payment/refund recording, currency/conversion evidence, unit/guest links, audited correction/reversal confirmation and financial history. The reservation detail body opens the folio; Today/Operations expand the daily-closing panel. Other non-booking charges/payments use normal property financial operations from that panel. English and Hungarian copy use the existing localization mechanism. The interface states explicitly that recording a payment neither collects funds nor issues a legal invoice. It does not ask for XML or government-only payloads.

## Tasks 12-13: operating days and automatic snapshots

`business_days.py` owns explicit property operating/closed dates, local timezone, starting date, effective IFA rates, manual close and opt-in automatic close hour. Actual stay timestamps use that property timezone once configured; initializing a different timezone over existing actual events is rejected. Calendar boundaries freeze after the first snapshot. Only a past day whose predecessor is closed can close. No raw reopen erases accepted history: changes mark the closed day dirty and require an audited full revision.

Automatic scheduling derives due work durably from configuration and closed rows, so restarts do not lose timers. It only closes explicitly confirmed, consistent dates, stops at missing/blocked/dirty dates, and never auto-approves historical corrections. Manual close and automatic close call the same transaction service. Duplicate/concurrent closing produces one logical snapshot/job.

Calculations use effective physical versions and OOO/OOS, actual occupancy segments and transfers, effective guest profiles, itemized charges and payments. Scheduled reservations or online registration create no occupancy. Night boundaries use local dates: departing rooms and true same-day visits are excluded from sold overnight units; same-day revenue is retained. Unreviewed expected stays, missing physical reconciliation, maintenance contradictions, unitemized folios and missing tax/profile facts block inconsistent closing. Fixed/percentage IFA obligation and taxable/exempt guest nights derive from source facts; a percentage tax needs its net accommodation base. The IFA rate is distinct from total tax due.

Closing saves an encrypted immutable factual snapshot, fingerprint, revision, provenance, closure/history and reporting capture in one transaction. The daily serializer creates the official room/bed/guest-night/day-use/checkout/other/post-stay blocks and validates through existing schema infrastructure. Post-stay charge date is the actual departure date; post-stay payment date requires the explicitly recorded invoice issue date (interface pp70-71). Missing identity or unresolved protocol gates preserve the closed business operation and durable report blocker. Recovery uses saved facts; it may resolve the frozen identity prerequisite but does not silently replace profiles or source history. Old snapshots and jobs remain retained; only reporting metadata advances. Recovery rotates pending checks fairly.

The previous dictionary endpoint remains legacy compatibility for unconfigured calendars. Once an operational calendar exists, it rejects override and its legacy scheduler is bypassed. Normal Flutter closing never uses it.

## Task 14: outcome-aware historical corrections

Normal financial replacements/reversals, guest DOB/residence/IFA corrections, effective rate corrections and physical/stay history changes mark affected closed days for review. Regeneration reads corrected authoritative records and preserves previous encrypted snapshots and frozen guest IDs. A corrected effective tax rate adds a separate revision; the original rate row is retained.

Final rejected initial reporting permits UJ (EU_01B). A fully processed successful or VIZSGALANDO/review result requires MODOSITO, a unique25-character protocol ID and an official reason (NZ_04B VENDEG_VAGY_IFA_JAVITAS; EU_02B TECH_HIBA_ADATJAVITAS). Synchronous receipt/accepted, sending, uncertain and unresolved processing states do not establish final acceptance: the correction is retained with a pending-outcome blocker. Recovery resolves classification only after a known outcome. A rejected correction does not erase an older accepted initial report. Obsolete versions known never transmitted are superseded; historical facts are not deleted.

## Migrations and API

All schema operations are repeatable, additive and preserve existing rows; no operational migration was executed in this task.

| Version | Change |
|---|---|
| 3081 | `financial_folios`, immutable `financial_entries`, indexes and original quote retention |
| 3082 | `business_day_settings`, `business_days`, `business_day_history`, encrypted `daily_snapshots` and effective `property_ifa_rates`; recovery-check metadata |
| 3083 | `property_ifa_rate_corrections`, preserving original effective rates |
| 3084 | Nullable original-payment `refund_of` link for refunds |

| API | Operation |
|---|---|
| GET/POST `/api/reservations/{id}/folio` | Read folio/catalog/history or post charge/payment/correction/reversal |
| GET `/api/properties/{id}/financial-entries?business_date=...` | Other financial entries and official catalog |
| POST same property path | Non-booking financial posting |
| PUT `/api/properties/{id}/business-calendar` | Explicit operating-calendar start/timezone/automatic closing policy |
| PUT `/api/properties/{id}/ifa-rates` | Effective tax rate or append-only correction |
| GET/PUT `/api/properties/{id}/business-days/{date}` | Read readiness/history or confirm/change operating status |
| POST same day path `/close` | Normal manual close or full source-derived revision |
| POST same day path `/reporting-recovery` | Recheck saved reporting prerequisites without repeating the business operation |

Owner/manager authorization, organization/property scope and existing cookie/CSRF protection apply. Source mutation and closing use property-first serialization; request digests prevent duplicate financial actions. Exact source facts containing profiles stay encrypted; no new salt/key/canonical identity fields are exposed.

## Verification

Final guarded backend regression run: **131 passed, 2 dependency warnings**,216.11s. Following final property-history/idempotent-calendar refinements, all **17 focused financial/closing tests passed** (46.54s). Full Flutter suite: **284 passed**. Final Flutter analysis: **No issues found**. Separate known legacy registration check: **1 failed**, as detailed below and in NTAK_HANDOFF.md. Logs are under `build/tasks10_14` and `apps/delvane_business/build/tasks1014-*` (ignored diagnostic artifacts, not required runtime inputs).

Focused sequence: interrupted Task10 tests2 passed; ledger/payment/concurrency4 passed; initial calendar3 passed; extended snapshot/outcome/day-use13 combined financial checks passed; property timezone/frozen identity/correction checks subsequently passed. Official offline facts cover NZ_01; NZ_02 three nights/two units,400 HUF tax RATE, OOO103/OOS104, four other charges/card21400; NZ_03 all69 lines/seven payments/28467; NZ_04A/B two nights/one unit, original DOB1986-01-01/taxable then1987-02-11/im5 and frozen identity; NZ_05 zero nights,28000/34500 and10000 post-stay. EU_01/02 outcome semantics are mocked, not a completed official multi-warning/evidence rehearsal.

Failures found and fixed: seeded test reservations contradicted the isolated closing property (fixtures now cancel them via ordinary APIs); invalid concurrent-test actor ID; identical A-B-A reservation reporting snapshots collided with the older outbox dedup index (outbox wrapper now includes logical identity, while NTAK payload/XML remains unchanged); test request bodies were Maps and language/timer cleanup was missing; a new panel accessed unloaded property data; a new header button overflowed. Assertions were retained. Encoding damage from a Windows default-decoding edit was reversed before final verification; source files are written explicitly as UTF-8.

The independently documented legacy `test_v293.py::test_modification_preserves_manual_fields_and_cancellation_updates_cleaning` still fails: it expects manual registration `complete`, while the current verified lifecycle derives `incomplete`. It was reproduced again separately, not hidden or changed. The earlier scanner failure recorded in the historical documentation review is not current evidence: selected test_v3000 scanner regressions pass.

## Limits and next boundary

Official transmission remains disabled by `UnresolvedOfficialTransport`. First identity normalization, information-query response/interval, signing reference policy, country-code discrepancy and imported missing timestamps remain gated as previously documented. Legacy unitemized bookings need deliberate itemization; no charges or collected payments are invented. Multi-unit money needs an explicit unit association if not unambiguous. Refunds need a traceable original payment/original-day correction; missing document dates or prohibited charge contexts remain recoverable blockers. No live FX, invoice issuer, payment processor, PostgreSQL execution, physical device or Android/Windows build result is claimed for this batch. Day-use Channex stock remains conservative as documented in Tasks6-9.

Tasks15-17 may build detailed source-linked errors, resend/evidence persistence and evidence export on these retained versions. They were not started. Tasks18-20 and VIZA implementation were not started. NTAK work can now be paused at [NTAK_HANDOFF.md](NTAK_HANDOFF.md), with all contract gates intact.

## Local checkpoint after implementation

The user subsequently authorized a local Git checkpoint tagged `ntak-pre-viza-checkpoint`. It preserves the completed tree through3084, including earlier committed work and the final reviewed refinements/documents. The no-commit statements above describe the implementation batch; they do not prohibit this later authorized local checkpoint. No application/business logic was changed during checkpoint preparation. No push, deployment, official request or credential replacement is part of the checkpoint.
