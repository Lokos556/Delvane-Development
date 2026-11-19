# NTAK development handoff

Checkpoint: 2026-11-19, after Tasks10-14. **Not ready for official validation. Official transmission is disabled.** NTAK work is to pause here while the user prioritizes VIZA; this batch did not begin VIZA or Tasks15-20. This file is intended to work without the previous chat.

## Authorized local Git checkpoint

NTAK development is paused until VIZA integration and validation are completed. The local annotated tag `ntak-pre-viza-checkpoint` identifies the commit preserving this complete tree through Task14/migration3084, including Task5's unresolved first-identity normalization gate. Resolve the exact commit with `git rev-parse ntak-pre-viza-checkpoint^{commit}`. This checkpoint is local only; it grants no permission to push, deploy, transmit, begin Tasks15-20 or start VIZA in this session.

The implementation reports below are historical records of their named batches; their earlier next-task recommendations and no-commit statements describe those batches. The current state is this handoff plus the latest readiness update. Pre-checkpoint HEAD was a5282b6; the authorized checkpoint commit descends from it. Source, fictional regression fixtures and documentation are included. Local environments, secrets/certificates, operational storage, builds and diagnostic artifacts remain excluded. Recorded test results are from the completed implementation verification; checkpoint preparation does not claim new application test/build/device execution.

## Repository and safety boundary

- Repository: `C:\Delvane\Delvane-Development`; Flutter app: `apps/delvane_business`; existing Python/FastAPI entry point: `app.py`.
- Branch: `main`. Initial HEAD during the interrupted/resumed batch was 9d0503a. Before checkpoint preparation, HEAD was a5282b6 (`save`), created externally during implementation. No commit/push was made by the implementation agent in that batch; the separately authorized local checkpoint is identified by the tag above. Preserve this checkpoint and every subsequent local change; do not clean/reset the tree or assume a clean checkout.
- Latest migrations: **3084**. Tasks1-9 reached3080; this batch adds3081-3084 below. Schema code was executed only in isolated fictional test databases. No migration/reset/start of the persistent development workspace occurred.
- Do not start `run_development_workspace.py`, open configured operational databases, contact NTAK/Channex, deploy, replace credentials, commit or push without a new instruction authorizing that work. Existing environment isolation, cookies, CSRF, role/property/tenant boundaries, Flutter3.50.0 and Dart3.14.0 must remain intact.
- Test harness: root `conftest.py`, `testing_safety.py`, `testing_clock.py` and `pytest.ini` install temporary storage, API-key/network/database guards before importing the backend. Use repository `python -B -m pytest`; do not import/start app.py in an ad-hoc script outside those guards. Do not override `--basetemp`.
- `ntak_transport.UnresolvedOfficialTransport` is the default and raises `signature_profile_unresolved`. Mock transport is injected by offline tests only, never selected through a user API/environment flag. Preserve that boundary.

## What exists

| Tasks | State and implementation |
|---|---|
| 1 | Physical accommodation units, versioned beds/types/building/room, dated OOO/OOS, capacity and authorization;3074 |
| 2 | Multi-unit planned reservation allocations/history, transactional conflicts and aggregate quantity reconciliation;3075 |
| 3-4 | Normal booking facts/immutable reporting identity/time, automatic capture, property inventory and booking Flutter controls;3076 |
| 5 | Encrypted effective guest residence/IFA profiles, permanent property salt, frozen reporting IDs;3077. Automatic first identity construction remains explicitly blocked by missing normalization policy. |
| 6-9 | Actual per-guest stays, source-aware transactions, normal Flutter controls, audited reversals/transfers/timestamp corrections and explicit timed day-use/cleaning;3078-3080 |
| 10 | Decimal itemized charge ledger and official category/VAT/package metadata, original quote retention and authoritative folio projection;3081 |
| 11 | Operational payments/refunds, corrections/reversals, post-stay records, reservation folio and property financial Flutter operations;3081/3084 |
| 12 | Property operating calendar, local business dates, chronological/manual/opt-in automatic closing with durable restart recovery;3082 |
| 13 | Automatically source-derived, encrypted immutable daily factual snapshots and transactional NTAK queue capture;3082 |
| 14 | Source corrections, effective IFA-rate history, full daily revisions, frozen-ID retention and outcome-aware UJ/MODOSITO;3083 |
| 15-20 | Not started as new tasks. Earlier queue/security helpers are groundwork, not completion or permission to transmit. |

Migrations3081-3084 are additive/repeatable: `financial_folios` and `financial_entries`; `business_day_settings`, `business_days`, `business_day_history`, `daily_snapshots`, `property_ifa_rates`; `property_ifa_rate_corrections`; nullable original-payment `refund_of` link. Original quotes, financial entries, profiles, rates, snapshots, actual events and allocation history are retained. Reporting job pointers/blockers/recovery metadata can advance; encrypted snapshot facts are not overwritten.

## Read these files first

1. This handoff and [TASKS10_14_IMPLEMENTATION.md](TASKS10_14_IMPLEMENTATION.md).
2. [VALIDATION_READINESS.md](VALIDATION_READINESS.md): original official case extraction/dependencies plus dated implementation updates. The original audit gap matrix is historical; the checkpoint matrix below supersedes its implementation status.
3. [DOCUMENTATION_REVIEW.md](DOCUMENTATION_REVIEW.md): exact unresolved contracts and their supplied source locations. Its first-batch capability/test sections are historical.
4. Earlier reports as needed: [TASK1_PHYSICAL_UNITS.md](TASK1_PHYSICAL_UNITS.md), [TASK2_RESERVATION_ALLOCATIONS.md](TASK2_RESERVATION_ALLOCATIONS.md), [TASKS3_5_IMPLEMENTATION.md](TASKS3_5_IMPLEMENTATION.md), [TASKS6_9_IMPLEMENTATION.md](TASKS6_9_IMPLEMENTATION.md).

Source map (relative to repository root):

- `app.py`: existing init/migration hooks, reservations/imports, inventory/ARI queue, government worker, authentication/CSRF and route registration. It calls the shared services; it is not a second backend.
- `physical_units.py`, `reservation_allocations.py`, `day_use.py`: explicit physical inventory, planned allocation history, timed day-use and cleaning; no double inventory deduction.
- `reservation_reporting.py`, `guest_reporting.py`, `guest_stays.py`: normal booking facts, encrypted effective profiles/frozen identity boundary, actual event history and occupancy.
- `financial_ledger.py`: append-only Decimal financial source of truth; original quotes, active replacements/reversals, payments/refund links, authorization and folio APIs.
- `business_days.py`: operating dates/settings, effective IFA, source collection/serialization, encrypted daily snapshots, classification, closing/recovery/automatic scheduler and APIs.
- `ntak_contracts.py`, `ntak_protocol.py`, `ntak_countries.py`: offline embedded schema loading, serialization/business validation, accepted country set; official files are unchanged.
- `ntak_reporting.py`, `ntak_api.py`: durable jobs/states/attempts/recovery and existing management API. Government outbox uniqueness is retained; the outbox wrapper contains logical identity while ntak_jobs holds the schema payload.
- `ntak_transport.py`, `government_security.py`: blocked live transport and reusable local certificate/key/trust checks. These helpers do not prove deployed credentials or signing interoperability.
- Flutter `lib/features/pms/financial_controls.dart`: folios, charge/payment/refund corrections, other financial entries and day-close settings/readiness/history; entry points in `reservation_dialogs.dart` and `pms_shell.dart`. Other shared controls: `inventory_controls.dart`, `booking_reporting_controls.dart`, `guest_reporting_controls.dart`, `actual_stay_controls.dart`, `ntak_reporting_dialog.dart`. Hungarian source: `assets/native-hu.json`; English uses existing source labels.
- New tests: `tests/test_financial_ledger.py`, `tests/test_business_days.py`, `tests/fixtures/ntak_official_charge_lines.json`; Flutter `test/financial_workflows_test.dart`. Existing relevant suites are listed in the command below.

Normal APIs: GET/POST `/api/reservations/{id}/folio`; GET/POST `/api/properties/{id}/financial-entries` (GET requires business_date); PUT property `/business-calendar` and `/ifa-rates`; GET/PUT property `/business-days/{date}`; POST that day `/close` and `/reporting-recovery`. Stay/identity/physical APIs remain as documented in earlier reports. No normal UI edits reporting dictionaries/XML. The legacy dictionary-closing endpoint cannot override a configured operational calendar and its scheduler is bypassed for such properties.

## All 27 official validation cases: current readiness

Authority: `docs/ntak/validation/PMS_v9_Interfész_Validációs_Tesztfeladatok_v1.07.docx` and `Szobatükör_segédlet_v1.07.xlsx`. The directory contains those exact supplied originals. All196 DOCX tables and all three worksheets were extracted in the original readiness analysis. Case IDs below are official; test fixtures use fictional data and internal legitimate canonical identities. **No row means officially passed.** Signing/transport, real outcome/evidence and applicable first-identity gates are common external blockers.

| Case | Current local readiness / remaining boundary |
|---|---|
| ELO_01A | Normal create fields/unit allocation/automatic reservation capture covered offline; official endpoint/evidence outstanding |
| ELO_01B | Normal booking exists; other-foreign EGYEBKULFOLDI encoding is contract-blocked |
| ELO_02 | Normal guarantee/date/amount modification and revision capture covered; past-arrival policy conflict remains explicit |
| ELO_03 | Normal cancellation/history/release/capture covered; dependent ELO_01B country/official evidence remains |
| ES_01A | Group actual arrival/registration separation covered; fictional Tibor correction sequence demonstrated, no duplicate genuine arrival |
| ES_01B | Individual actual arrival in102 covered; first identity gated unless legitimately frozen |
| ES_01C | Later individual arrival on same booking covered; identity gate as above |
| ES_02 | Audited erroneous-arrival reversal and unsent/processed semantics covered; source scenario sequence ambiguity remains |
| ES_03 | Actual102-to103 transfer, occupancy/allocation history and capture covered |
| ES_04A | Group actual departure covered; no inference from scheduled date |
| ES_04B | Partial-party departure leaving another guest present covered |
| ES_05 | Erroneous-departure reversal/retained history covered; ES_04B/05 sequencing ambiguity remains |
| ES_06A | Same-day103 guest in/out covered with zero nights and normal day-use booking |
| ES_06B | Same booking's104 guest in/out covered; not split into a fictitious second booking |
| NZ_01 | Closed-property snapshot:4 OOO rooms/10 regular places, no sold rooms, schema-valid local capture covered |
| NZ_02 | Three actual nights/two sold units,400 HUF tax RATE, OOO103/OOS104, other charges5800@18/4600@5/1000@27/10000@27 and card21400 covered. Tax rate is not total tax due. |
| NZ_03 | All69 worksheet lines,28467 charges, seven payment categories matching28467, three nights/two units covered; metadata and individual lines retained |
| NZ_04A | Two nights/one unit, DOB1986-01-01, taxable guest/effective400 rate and IFA charge covered |
| NZ_04B | DOB1987-02-11/im5 source correction, IFA reversal, frozen ID and full MODOSITO/VENDEG_VAGY_IFA_JAVITAS covered with mocked processed original |
| NZ_05 | Zero-night103/104 day-use,28000 cash/34500 card and10000 post-stay charge/card linked to original booking covered; correct departure/invoice dates |
| EU_01A | Rejected-outcome parsing/mock queue exists. Full official extreme-value/error-display/evidence rehearsal remains Tasks15-17/20; no production guest-name special cases |
| EU_01B | Rejected-initial -> corrected full UJ semantics covered; full official error/evidence chain remains |
| EU_02A | Processed-review outcome exists; full multi-field warning display/evidence and official malformed-input rehearsal remain15-17/20 |
| EU_02B | Review-processed -> MODOSITO/TECH_HIBA_ADATJAVITAS source regeneration covered; full multi-field official rehearsal remains |
| EU_03A | Existing mocked UJRA_KULDENDO state-machine groundwork only; immutable full daily resend/evidence rehearsal remains16/20 |
| EU_03B | Existing unchanged resend groundwork only; both receipts/polls/evidence must be proven in16/20 |
| AD_01 | Explicitly blocked: supplied information/verification response schema does not carry the final expected-start-date field; automatic onboarding is Task19 |

Source anchors: ELO tables4/5/17/25; ES33/34/50/58/66/67/79/87/88; NZ108/116/124/132/144; EU152/164/176/177; AD189. DOCX table numbers count all document tables, not extra official case IDs. ES_06A/B each require arrival and departure messages. The fixture property is101 STANDARD(3 regular),102 SUPERIOR(2),103 ECONOMY(3),104 APARTMAN(2 regular+1 extra):4 units,10 regular places,1 extra.

## Unresolved technical requirements

1. **Information final result**: interface9.07 section7.3.3 p46 says `elvartAdatszolgaltatasKezdoDatuma` is returned after processing. Supplied `adatszolgaltatasKezdoDatumResponse` and verification `UzenetValaszokType` contain no such element/extension point. Need matching official WSDL/XSD or exact namespace/nesting/retrieval clarification. Do not modify local official schemas.
2. **Information interval**: pp41-42 describe an interval, but supplied request carries only software/provider/message identities. Need the normative request contract or confirmation that paragraph is obsolete. No invented date elements.
3. **Signature references**: pp61-62 show Timestamp/Body references and duplicate Timestamp ID; p63 says one Body reference. Need normative reference policy and interoperability test vector. Exclusive canonicalization/RSA SHA256/384/512/direct X509 reference/300-second time window are described, but this does not resolve reference conflict. No fallback signer.
4. **First guest identity normalization**: pp57-59 defines UTF8 -> SHA256 hexadecimal -> BCrypt/permanent property salt -> final31 characters, with frozen reuse after changes. Published vector passes. International name order/normalization is not fully defined and translated prose/example differ. `identity_for_submission` requires a future approved internal canonical result; no owner hash-input bypass, temporary ID or guessed transliteration.
5. **Country encoding**: ELO_01B other-foreign value EGYEBKULFOLDI does not match supplied OrszagKodType values/pattern. Keep explicit blocker; country appendix itself is present.
6. **After-arrival booking reporting policy**: conflicting pp54/87 rules remain gated (`past_arrival_policy_conflict`). Missing original provider booking timestamp is a factual blocker; ingestion time is not substituted.
7. **Official scenario order**: ES_01A/02 repeat Tibor; ES_04B/05 repeat Natasha departure. Demonstrate audited correction semantics, do not manufacture duplicate physical events. Detailed observation/clarification belongs in the official rehearsal.
8. **Local IFA exemptions**: statutory codes are implemented. Unprovided municipality-specific mappings must not be invented.

All five WSDL files have embedded XSD definitions and no external imports/includes; separate missing schema files are not needed for compilation. v9 PDF appendices include financial categories, extreme limits, countries and postcodes. The validation files resolve workflow requirements but do not resolve the schema/signature/normalization discrepancies above.

## Test environment / issued certificate

User supplied support ticket150337 and official test endpoint **https://pms.tesztntak.hu/ntak/v9**. Certificate was reportedly issued for DELVANEAI, reporting identifier PH4JKQJ2, using the existing CSR. Certificate/private key are managed separately on Hetzner. This is issuance evidence from the user, not locally verified installation/key match/trust/mTLS/signature evidence. No actual credential was opened, generated, replaced or installed here, and no endpoint was contacted. Do not copy that identifier into a different property-registration field without verifying its meaning against the contract. Production/staging credentials, databases and endpoints must remain isolated.

Future credential layout/check helpers exist in `government_security.py`; installation, restrictive service-user access, matching key, complete trust chain, expiry/rotation policy and correct environment/property binding still require server-side verification under a separate authorized task. No private key, salt or secret belongs in this handoff, Flutter or source control.

## Remaining Tasks15-20 and acceptance criteria

| Task | Dependency | Next independently testable acceptance boundary |
|---|---|---|
| 15 | Current queue/snapshots and source IDs | Persist field-level errors/multiple warnings, localize known catalog and link each problem to normal source operations; no raw identity values in general logs |
| 16 | 13-15 | Mock EU_03: retain identical full business content, both receipts and every poll/attempt; crash/timeout -> uncertain, no blind retry; rebuild only when outcome permits |
| 17 | 15-16 | Owner-authorized evidence export with correlated request/reply/poll/source revision; retained evidence, tenant isolation, redaction/access controls; no keys/salts |
| 18 | Official signature clarification and issued server-held certificate | Offline signature vectors, trust/expiry/key mismatch/environment/host tests and explicit gated transport; only separately authorized live work may contact test endpoint |
| 19 | 18 plus official final-start-date result schema | Automatic onboarding information query, correlated verification, persisted displayed start date; absent/invalid result blocks reporting schedule |
| 20 | 1-19 plus all applicable contract resolutions | Full27-case rehearsal via normal API/Flutter operations, exact official fixture/evidence completeness, explicit fixture-only error simulation, Android/Windows builds/device checks and readiness re-audit |

No new work for these tasks was started in this batch. Existing helpers/tests are reusable groundwork.

## Shared behavior VIZA development must preserve

- Raw scanner/registration data, effective reviewed profile corrections and actual stay events are separate sources. Document scan or registration completion must never imply physical arrival.
- Guest identity review and verification-derived registration state, scanner provenance, stable guest/reservation/provider IDs and encrypted sensitive storage must remain intact. Do not change assertions to hide a workflow defect.
- Property/tenant authorization, cookies/CSRF, environment binding, dedicated test storage and network guards are shared boundaries.
- Actual arrival/departure/transfer history and immutable physical allocation/OOO/OOS versions must remain factual; VIZA adapters should call shared authorized services rather than duplicate occupancy logic.
- Frozen NTAK identity/permanent encrypted property salt survives DOB/IFA corrections. VIZA must not rotate it or derive its own guessed canonical reporting identity.
- Financial folios, effective tax history, actual guest-night calculation, daily snapshots and durable government queue/recovery must survive VIZA changes. No duplicate inventory, charges or jobs.
- Use existing scanner/guest/reception regression suites and the NTAK source/snapshot suites below. Do not disable the NTAK protocol gates while repairing VIZA.

## Verification checkpoint and limitations

Final guarded backend regression command below: **131 passed, 2 dependency warnings**,216.11s. After final property-history/idempotent-calendar refinements, the focused financial/closing suite passed **17 tests**,46.54s. Full Flutter: **284 passed**; final `flutter analyze`: **No issues found**. Before the final run, focused sequences40 and17 passed; these overlap the broad suite and must not be added to its count. Five new Flutter workflow tests cover HU/mobile, EN/desktop, reservation/property source correction and normal day close. The previously failing header/reception regressions then passed27 focused tests before the final full284-test run. Physical Android/Windows acceptance, new Android debug/Windows release builds, PostgreSQL locking execution and real NTAK validation were not performed in this batch.

Known failure, independently reproduced before this batch and rerun here: `tests/test_v293.py::test_modification_preserves_manual_fields_and_cancellation_updates_cleaning` expects registration `complete`, receives `incomplete` at line100. Separate result:1 failed,2 dependency warnings. No assertion was changed. The old first-batch scanner pending/incomplete failure in DOCUMENTATION_REVIEW.md is historical: current selected test_v3000 passes. FastAPI/Starlette report two dependency deprecations in current backend runs.

Other explicit limits: legacy quotes need deliberate itemization; whole-HUF reservation compatibility totals are rounded projections while folios retain exact cents; FX rates/evidence are supplied explicitly; multi-unit financial allocation must be unambiguous; missing original payment/invoice date or forbidden reporting context blocks affected reporting; configured automatic close stops for any unconfirmed/inconsistent/dirty day. Closed snapshots are corrected through revisions rather than destructive reopen. Channex day-use availability remains conservatively date-based. Tasks6-9's latest-event correction-chain restrictions remain. General reporting errors/evidence/resend UI is intentionally not completed before Tasks15-17.

## Exact resume instructions after VIZA

1. Obtain a new explicit instruction to resume NTAK. Start with `git status --short`, `git branch --show-current`, `git log -1`; preserve VIZA and other local work. Do not reset/rebase/commit automatically.
2. Read this file, Tasks10-14 report and the dated updates in readiness/documentation review. Inspect only source affected by the next task; do not repeat the full certification audit. Verify migrations3081-3084 and any later VIZA migrations for number/ownership conflicts.
3. Run guarded baselines below. Compare with the explicit known v293 failure; investigate every new failure without weakening assertions. Check changes to shared guest/scanner/stay behavior first.
4. Begin **Task15 only** unless the user's next scope differs. Keep real transmission disabled. Complete15, then16/17 in small reviewable batches; no official fixture shortcuts in production logic.
5. Resolve contract questions separately before18/19. Reuse the already issued server-held certificate/CSR. Do not generate replacement credentials or probe endpoints to infer missing contracts.
6. Only after the later tasks, authorized server verification and full offline rehearsal should a new readiness decision propose official testing. This checkpoint gives no permission to deploy or transmit.

```powershell
Set-Location C:\Delvane\Delvane-Development
git status --short
git branch --show-current
git log -1 --oneline
.\.venv\Scripts\python -B -m pytest tests/test_financial_ledger.py tests/test_business_days.py tests/test_actual_stays.py tests/test_day_use.py tests/test_guest_reporting_profile.py tests/test_reservation_allocations.py tests/test_physical_units.py tests/test_normal_reporting.py tests/test_flutter_reservation_reception.py tests/test_flutter_distribution.py tests/test_guest_checkin.py tests/test_guest_checkin_lifecycle.py tests/test_persistent_development.py tests/test_ntak_reporting.py tests/test_ntak_contracts.py tests/test_v3000.py -q
# Run separately to observe the documented legacy failure:
.\.venv\Scripts\python -B -m pytest tests/test_v293.py::test_modification_preserves_manual_fields_and_cancellation_updates_cleaning -q
Set-Location apps\delvane_business
flutter analyze
flutter test
```

These are test commands, not instructions to launch/reset the persistent acceptance workspace. No build installation/device result is implied.
