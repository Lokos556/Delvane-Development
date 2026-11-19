# NTAK certification readiness

Analysis date: 2026-11-19. **Not ready for official validation.** This is a source review of the current working tree, including unfinished, uncommitted NTAK work; it is not a test execution or certification result. No application code, databases, credentials or deployment settings were changed for this analysis.

## Sources and completeness

Read the complete DOCX body and all **196 tables**, including instructions, case data, request/response placeholders and declarations:
`validation/PMS_v9_Interfész_Validációs_Tesztfeladatok_v1.07.docx`.
Document control: v1.07, 2026-09-24, Visit Hungary, status “Véleményezésre”, declared 33 pages. Table numbers below count every table in document order, including evidence placeholders. They are stable source locators, not invented official case numbers; DOCX pagination was not independently rendered/verified.

Read all nonempty cells, formulas, comments and merged-cell ranges in all three worksheets of `validation/Szobatükör_segédlet_v1.07.xlsx`: `Szobatükör`, `Adatok`, `T03_FOGL_2_terhelés`. No hidden worksheets. Formulas were inspected as formulas rather than silently treated as newly calculated results. The room grid's merged date blocks were read together with the booking and guest table, not as independent occupancy cells.

There are **27 official named cases**: 4 ELO, 10 ES, 6 NZ, 6 EU and 1 AD. ES_06A and ES_06B each require both arrival and departure messages. The five task groups and subsection headings are also part of the requirements; placeholders for screenshots and four request/response stages are evidence requirements, not extra test cases.

Ticket **150337** and the user-provided endpoint `https://pms.tesztntak.hu/ntak/v9` establish that the test endpoint/certificate have been issued. Certificate issuance for DELVANEAI / PH4JKQJ2 is user-provided evidence, not locally verified key matching, trust, mTLS or signature interoperability. The existing Hetzner key/CSR must be reused. No endpoint was opened or contacted.

## Mandatory execution conditions

The introduction and final declaration require backend messages to be generated and sent automatically from **normal business changes**, without a reporting-specific user intervention. Error simulation in task group 4 is the explicit exception. Normal booking, check-in, room change, posting a charge, correcting guest data or closing a business day may be user actions; composing SOAP or manually filling a reporting payload is not an acceptable replacement.

Every submitted request needs its message ID, synchronous response/processing ID, verification request and verification response recorded, plus full-screen screenshots of the actual PMS operation and any limitations. An accepted receipt is not final processing success. The final declaration requires either support for all published errors or an explicit list of unsupported errors.

The schedule spans nine business dates: T01–T05 contiguous past dates, TX/TX+1/TX+2, and independent TY. Eight dates require daily closures; TX+2 is departure context, not an additional requested daily-closing case. TX cannot precede the current calendar day; execution needs at least two calendar days, within a declared validation window of at most five days. Do not assign actual dates or start that window during readiness work.

## Existing implementation map

All paths are repository-relative. These references map the matrix below to actual functions/widgets, rather than equating generic PMS support with passing certification.

| Key | Backend and database evidence | Flutter evidence | Readiness limit |
|---|---|---|---|
| R | `app.py::reservation_create`, `reservation_update`, `reservation_cancel`, provider paths call `ntak_reporting.capture_reservation`; `reservations`, `reservation_events`, `room_types`; `ntak_reservation_facts`, `ntak_reservation_versions` | `reservation_dialogs.dart`, existing booking/edit/cancel flows | Automatic capture exists when enabled, but required guarantee/country/channel/segment/unit facts live in a separate reporting-facts API, not complete normal booking controls. Internal IDs versus stable FOGL identifiers need a deliberate mapping. |
| G | `guest_records`, encrypted `sensitive_guest_data`, identity review; `ntak_protocol.guest_hash`; `ntak_guest_ids` table | Guest registration/identity review through existing reservation flows | Registration verification is not physical arrival. Hash helper/table are not a complete persistent identity lifecycle. Residence country/postcode and IFA exemption require structured operational fields and mappings. |
| S | `ntak_api.stay_event` accepts explicitly constructed event dictionaries; schema serializer supports arrival/departure/move | No normal per-guest arrival, departure, undo or physical-room transfer controls wired to reporting | This is a manual reporting boundary, not a normal stay lifecycle. Missing durable actual stay/unit history. |
| D | `ntak_api.daily_facts`, `ntak_day_facts`, `ntak_daily_requirements`, `schedule_daily` | `ntak_reporting_dialog.dart` displays daily requirements | Scheduler consumes supplied closing dictionaries. No complete snapshot builder from stays, room inventory and financial ledgers; no normal closing/ledger UI. |
| Q | `government_outbox`, `government_delivery_attempts`, `ntak_jobs`; `worker_once`, `ntak_protocol.response` | `NtakReportingDialog`, `NtakRecoveryDialog` show queue, states and limited recovery | Worker supports injected mock adapter; normal execution explicitly blocks. Attempts store request hash and bounded response codes, not the complete certification evidence exchange. Warnings parsed by protocol are not fully persisted/rendered at field level. |
| C | `government_security` checks existing certificate/key, RSA4096, matching public key, validity with expiry margin; TLS context builder; `ntak_transport.SignatureProfile` interface | Settings/status and certificate availability/expiry | No concrete approved signer or operational SOAP adapter. Status still contains endpoint-pending blocker even though endpoint was supplied. Do not interpret this stale diagnostic as an unissued certificate. |
| U | `ntak_api.configure`, status/forms/recovery endpoints; existing owner/manager and CSRF boundary | Reporting settings/status/recovery only | Does not supply missing normal business operations. New dialog strings/localization and mobile behavior require verification; no fresh build/test result is asserted here. |

## Official case readiness matrix

**P** = partial infrastructure, missing certification behavior; **M** = missing normal business workflow; **B** = unresolved contract blocks completion. No case is marked passed. Q/C and evidence export are common dependencies for every case, even where omitted from the dependency cell. Dependencies below are engineering prerequisites unless explicitly prescribed by the source.

| Official ID (DOCX table) | Required operation and principal expected facts | Existing backend / Flutter map | Status and missing capability | Dependencies |
|---|---|---|---|---|
| ELO_01A (4) | Create FOGL_04, room101, HU, TX+1→TX+2, direct online, individual business, guaranteed, HUF20,000, expected1 | R / booking form | P: normal booking must save all reporting facts and automatically queue one independent request | Physical inventory; R facts; Q/C |
| ELO_01B (5) | Create FOGL_05, room103, other foreign, TX+1→TX+2, intermediary offline, group business, not guaranteed, HUF28,000, expected2 | R / booking form | P: unknown-foreign country encoding conflicts with current supplied XSD; complete normal field/UI mapping | Inventory; country-contract resolution |
| ELO_02 (17) | Modify FOGL_04 arrival to TX, guarantee false, HUF40,000 | R / edit form | P: guarantee update must be a normal booking operation and cause exactly one new factual revision | ELO_01A |
| ELO_03 (25) | Cancel FOGL_05 | R / cancellation flow | P: cancellation hook exists but needs original reportable snapshot, stable identifier and final-result evidence | ELO_01B |
| ES_01A (33) | FOGL_01 room101: Luca Ferri, Zsidi Mária, Zsidi Tibor arrival T02 | G,S / registration only | M: per-guest actual arrival transaction and reporting generation; source's Tibor overlap flagged below | FOGL_01, guests, room101 |
| ES_01B (34) | Natasha, FOGL_02 room102, arrival T02 | G,S / registration only | M: arrival history and automatic event | FOGL_02, guest identity, room102 |
| ES_01C (34) | Sergey, FOGL_02 room103, arrival T04 | G,S / registration only | M: later individual arrival independent of other guests on same booking | FOGL_02; unit assignment after ES_03 |
| ES_02 (50) | Erroneous arrival of Zsidi Tibor, FOGL_01 room101 T02 | S / no undo control | M: audited erroneous-arrival correction through normal stay workflow; compensating departure per interface rules | ES_01A; clarify repeated Tibor entry |
| ES_03 (58) | FOGL_02 room102→103 on T03 | S / booking room-type change insufficient | M: physical-unit move with guest list, old/new unit snapshots and occupancy history | ES_01B; room103 available after OOO |
| ES_04A (66) | Luca and Mária leave FOGL_01 room101 T04 | S / no actual departure control | M: actual per-guest checkout and automatic event | ES_01A; correction of Tibor excluded from genuine stay |
| ES_04B (67) | Natasha leaves FOGL_02 room103 T04 | S / no actual departure control | M: partial-party checkout; retain Sergey occupancy | ES_01B, ES_03 |
| ES_05 (79) | Erroneous Natasha departure FOGL_02 room103 T04 | S / no undo control | M: audited departure reversal with compensating arrival; resolve overlap with ES_04B rather than double checkout | ES_04B; clarify intended error/correction sequence |
| ES_06A (87) | Nagy Klára FOGL_03 room103, arrival and departure T05 | R,G,S / overnight forms | M: same-day business booking, guest/unit allocation, actual in/out; two messages | Day-use support, physical room103, guest identity |
| ES_06B (88) | Kovács Bianka same FOGL_03, room104, in/out T05 | R,G,S / overnight forms | M: one booking across two physical rooms; no invented second booking or overnight stay | Shared FOGL_03; room104; day-use |
| NZ_01 (108) | New closing for closed-property day T01 | D / status display | M: operating calendar, confirmed business-day closure and automatic snapshot/message | Inventory; operating status; closing boundary |
| NZ_02 (116) | T02: 3 guest nights,2 sold units, IFA400; OOO103/OOS104; other charges 5,800@18%,4,600@5%,1,000@27%,10,000@27%; card21,400 | D,G,S / no ledger UI | M: actual occupancy, dated OOO/OOS, exemptions; categorized non-stay ledger, VAT and settlement | NZ_01 chronological context; ES_01A/B and Tibor correction |
| NZ_03 (124) | T03:3 nights,2 units, IFA400; workbook full charge list; seven payment categories | D / no posting UI | M: complete category/subcategory/VAT/package and payment ledger; 28,467 total from 69 workbook lines | NZ_02 context; ES_03; complete catalog |
| NZ_04A (132) | T04:2 nights,1 unit, IFA400; Sergey taxable,DOB1986-01-01 | D,G / incomplete normal ledger | M: actual guest-night snapshot and correct daily postings | ES_01C, departure/correction chain, NZ_03 context |
| NZ_04B (132) | Correct T04: Sergey IFA exempt under authority/court reason,DOB1987-02-11; MODOSITO reason VENDEG_VAGY_IFA_JAVITAS | D,G / no normal closed-day correction | M: edit source guest/IFA facts, preserve frozen reporting ID, rebuild entire closing; audited reason/record | NZ_04A final outcome; IFA mappings |
| NZ_05 (144) | T05 day-use0 nights;103 HUF28,000 cash,104 HUF34,500 card; FOGL_01 post-stay charge/card10,000 | D,S / no ledger/day-use UI | M: day-use revenues without guest nights; post-stay ledger linked to original booking | ES_06A/B; FOGL_01 checkout; ledger |
| EU_01A (152) | TX UJ; FOGL_04 breakfast3,000,000; show TELJESEN_HIBAS | Q,D / generic error display | P: controlled error simulation exception; normal ledger provenance, detailed error display and evidence | ELO_02; business-day close; error catalog |
| EU_01B (152) | TX breakfast corrected3,000; still UJ | Q,D / correction API currently requires MODOSITO for changed saved day | M: distinguish rejected initial version from accepted closing; source correction must regenerate UJ appropriately | EU_01A processing result |
| EU_02A (164) | TX+1 UJ; IFA5%,12 beds,5 rooms; champagne200,001; IFA charge3,000; Tibor postcode1116101 | Q,D,G / generic review state | P: multi-field warnings, review UI and source-linked diagnostics; error simulation exception only | FOGL_04 actual stays; inventory and ledger |
| EU_02B (164) | TX+1 MODOSITO TECH_HIBA_ADATJAVITAS; IFA400,10 beds,4 rooms; champagne2,000; IFA400; postcode1116 | Q,D,G / no normal correction UI | M: source corrections and full closing regeneration, preserving previous evidence and guest reporting ID | EU_02A; accepted/reviewed-version semantics |
| EU_03A (176) | TY UJ,IFA400; sole booking __UJRAKULDENDO_VALIDACIO__, no other booking/charge | Q,D / no normal booking+closing route | P: explicit official error-simulation fixture may use marker; queue must not contain special-case success logic | Independent TY; closed-day ledger; mock UJRA_KULDENDO |
| EU_03B (177) | Resend identical TY content, obtain TELJESEN_SIKERES | Q supports one unchanged resend / state UI | P: verify immutable payload, second processing ID and both evidence chains; normal worker remains blocked | EU_03A UJRA_KULDENDO |
| AD_01 (189) | Information request then verification of processing result / expected start date | Schema preview; explicit information block / no automatic onboarding call | B: missing final date response contract remains; automatic property setup trigger and result presentation needed | C/Q; matching official response schema |

## Workbook acceptance facts and consistency issues

- `Szobatükör!A3:F6`: 101 STANDARD, one double+one single, no extras, HUF20,000/night; 102 SUPERIOR, one double, HUF25,000; 103 ECONOMY, one double+one single, HUF28,000; 104 APARTMAN, one double plus one extra, HUF34,500. Baseline is **4 rooms,10 regular places,1 extra bed**, not 11 regular places. Need one property containing physical units; representing each room as an unrelated property would evade the required model.
- Grid: T01 property closed; T02 room103 out-of-order and104 out-of-service; Natasha transfers102→103 T03; FOGL_03 uses103 and104 for same-day T05; FOGL_04 uses101 and FOGL_05 is cancelled. TY marker uses103.
- `Adatok!A4:H8` defines five bookings; `A15:M23` defines nine guest rows. Persist birth place, date, sex, nationality versus residence country separately, postcode and IFA obligation/exemption. Mária's hospital/social-institution exemption, minors Klára/Bianka and Sergey's later authority/court exemption require real reason-code mapping, not generic exempt=true.
- `T03_FOGL_2_terhelés!A2:G70` has **69 charge lines**, including IFA400 (row34), accommodation28,000 at5% (row55), and 67 one-forint category/subcategory examples. Total F71=28,467. Payments in NZ_03 are five×4,067 plus two×4,066 =28,467. Package inclusion and VAT are discretionary where the sheet says so; row34/55 prescribe them. Do not collapse categories or drop one-forint items.
- DOCX ES_01A already includes Tibor's arrival, while ES_02 again calls it erroneous; the workbook calls him erroneously arrived. Likewise ES_04B and ES_05 both name Natasha T04. Treat these as a sequence requiring clarification/explicit operational demonstration, not license to report duplicate real arrivals/departures. Corrected final occupancy must reconcile with NZ_02–04.
- FOGL_02 booking-level departure T05 differs from Natasha's individual T04 departure; Sergey remains until T05. This is a required per-guest lifecycle distinction, not an inconsistency to overwrite.

## Required model and business UI work

1. Physical accommodation units with building/number, official type, bed inventory and dated OOO/OOS intervals; booking-to-unit allocation supporting multiple rooms and moves. Existing room types/aggregate availability cannot prove these facts.
2. Normal reservation attributes for guarantee, expected guests, guest sending country, sales channel and market segment; immutable reportable booking number and original creation time. Facts must be part of ordinary create/edit/import transactions, with automatic outbox capture. Handle repeated A→B→A changes as distinct genuine revisions.
3. Per-guest actual arrival/departure, room assignment intervals and reversal events, reasons/actor/timestamps; registration completeness remains independent. Day-use must be an explicit valid stay type through date validation, conflicts, cleaning and reporting, not an overnight-date workaround.
4. Structured guest residence/IFA reasons with effective dates; permanent per-property hashing salt and frozen reporting ID lifecycle integrated with identity corrections. Do not regenerate a reported identity because DOB changes in NZ_04B.
5. Operational charge/payment ledgers: business date, booking/unit/guest links, amount, currency/rounding, official category/subcategory, VAT, package membership, payment method/subtype, post-departure context and correction history. A total_huf/payment_status field cannot reproduce the workbook.
6. Business-day operating calendar, closure state/version, source snapshot and audit reason. Build payload automatically on normal close; later source corrections produce full replacement snapshots with outcome-aware UJ/MODOSITO classification. Current daily-facts API is not this workflow.
7. User-facing source-linked field errors/warnings, follow-up actions and localized HU/EN descriptions; field values must not leak to general logs. Secure certification evidence export needs actual requests/responses, IDs, original and retry processing references and screenshots collected separately with access/retention controls.

## New documents versus previous discrepancies

| Previous issue | New evidence | Conclusion / affected contract |
|---|---|---|
| Test endpoint/certificate pending | User ticket150337 provides endpoint and successful issuance | Operational prerequisite supplied; still no local certificate, trust/key-match or external verification. Current hardcoded pending diagnostic needs later correction. |
| Missing start-date result | AD_01 repeats information→verification requirement; no replacement WSDL/XSD supplied | **Unresolved**: information `adatszolgaltatasKezdoDatumResponse` and verification `UzenetValaszokType` still cannot carry `elvartAdatszolgaltatasKezdoDatuma` from interface v9.07 p46. |
| Information-query interval | AD_01 supplies no interval | Supports a start-date-only use case, but does not resolve contradictory interface pp41–42 text or authorize invented interval fields. |
| Signature references / duplicated Timestamp example | No signature test vector, security-policy XML or replacement schema in DOCX/XLSX | **Unresolved**, interface pp61–63; signed transport must remain gated. |
| Unchanged resend | Task4c EU_03 explicitly requires unchanged content and then success | Resolves expected behavior for this validation marker scenario. Does not remove interface p38 FeldolgozasHiba/duplicate modified-version recovery rules for other outcomes. |
| Past stay events and booking changes | Introduction permits contiguous past T01–T05 closures/events; TX earliest today for advance bookings | Clarifies the validation schedule. Does not settle all general post-arrival advance-booking modification conflicts (interface pp54/87). |

Additional discovered incompatibility: ELO_01B's “egyéb külföldi” corresponds to v9.07 p86 `EGYEBKULFOLDI`, while supplied `OrszagKodType` permits `[A-Z]{2}|EGYEB` (plus empty). No new schema resolves it. Do not substitute HU, EGYEB or an invented ISO country to pass. Record as a contract blocker specifically for ELO_01B.

## Ordered implementation tasks

Each task is a separate reviewable development batch with fictional, offline acceptance tests. No task authorizes official validation or deployment. Complete model/API work before its Flutter companion; do not add a test-only Send SOAP button.

| Order | Small task | Depends on | Independent completion test |
|---|---|---|---|
| 1 | **Implemented 2026-11-19**: physical-unit model, dated OOO/OOS and capacity APIs; migration3074 | None | **16 unit tests passed; 74 relevant regression tests passed.** Isolated repeat migration,4 rooms/10 regular places/1 extra, dated history, tenant/property isolation; see [Task1 report](TASK1_PHYSICAL_UNITS.md). |
| 2 | **Implemented 2026-11-19**: transactional multi-unit overnight allocations and history; migration3075 | 1 | One overnight booking holds103+104; conflicts, OOO/OOS, concurrent claims and quantity-aware aggregate inventory tested. **50 relevant tests passed**, including8 allocation tests. See [Task2 report](TASK2_RESERVATION_ALLOCATIONS.md); Task9 day-use remains separate. |
| 3 | **Implemented** normal booking facts, immutable identity/time and automatic transactional capture; migration3076 | 1 | ELO-like create/edit/cancel, A→B→A, idempotency, rollback and multi-unit data tested. Missing provider original timestamp and EGYEBKULFOLDI remain explicit blockers. |
| 4 | **Implemented** property physical-unit/OOO/OOS controls and normal reservation reporting/multi-unit selection | 2,3 | Full Flutter275 passed; focused4 controls tests passed including property unit creation and two-unit selection via mocked transport. No physical-device result claimed. |
| 5 | **Implemented with isolated normalization blocker**: encrypted effective guest profiles, statutory IFA codes, permanent encrypted property salt and frozen-ID lifecycle; migration3077 | 1 | Official hash vector, Unicode, correction history and NZ_04B-style frozen-ID retention pass. Automatic international canonical identity construction remains blocked pending exact normalization policy. |
| 6 | **Implemented** persistent per-guest actual lifecycle and transactional automatic capture; migration3078 | 2,5 | Separate registration/occupancy, group and individual actions, rollback, concurrency, restart and identity-blocker recovery tested offline. Official transmission remains gated. |
| 7 | **Implemented** normal reservation/reception/operations stay controls | 6 | Responsive HU/EN controls, history, occupancy and reporting blockers; mobile/desktop workflow tests and full Flutter279 passed. |
| 8 | **Implemented** audited reversals, timestamp corrections and actual transfers; causal reporting dependencies migration3079 | 6 | ES_02/03/05 fictional offline flows, retained history, idempotency and unsent-event corrections tested. Older/repeated correction chains and uncertain submission outcomes are explicitly gated. |
| 9 | **Implemented** explicit timed day-use API, physical allocations, cleaning and Flutter; migration3080 | 2,6 | Two-unit same-day arrivals/departures, zero nights, retained revenue, overnight conflicts and DST validation tested. Channel inventory is conservatively date-based; no equivalent provider day-use support is claimed. |
| 10 | Add itemized charge catalog and dated posting ledger | 1,2 | All 69 workbook lines round-trip with VAT/category/package metadata and total28,467 |
| 11 | Add settlement/post-stay ledger and posting UI | 10 | Seven NZ_03 payment methods sum28,467; NZ_05 post-stay10,000 linked to FOGL_01 |
| 12 | Add operating calendar and normal business-day close | 6,8–11 | NZ_01 closed day; NZ_02 OOO/OOS/occupancy and other revenue generated from actual records |
| 13 | Generate full daily snapshots and automatic queue on close | 12 | NZ_02–05 source-derived XML validates; no hand-assembled closing JSON; restart recovery |
| 14 | Add outcome-aware source correction and closed-day UI | 5,13 | NZ_04B MODOSITO; EU_01B UJ after rejected original; EU_02B MODOSITO after review |
| 15 | Persist field-level results and localized recovery diagnostics | Q groundwork | Known error catalog and multiple warnings displayed with source links; no raw guest data in logs |
| 16 | Complete resend/evidence persistence with mocked SOAP | 13–15 | EU_03 retains identical business content, records both receipts/polls; crash/timeouts never blind-retry |
| 17 | Add access-controlled evidence export | 15,16 | Every request/reply/poll correlated, full evidence retained securely; keys/salts excluded |
| 18 | Implement resolved official transport/security adapter behind gate | Official signature clarification and server-held issued certificate | Disposable offline credentials, signature verification, trust/expiry/key mismatch and environment/host restrictions; no real endpoint call |
| 19 | Complete automatic onboarding information query | Official final-date schema clarification;18 | AD_01 mock result stores/displays start date; absent/invalid result blocks scheduling |
| 20 | Full offline business-flow rehearsal and readiness re-audit | 1–19; country resolution | All27 cases through normal API/Flutter operations; fixture-only error simulation restricted to task4; evidence completeness, Android/Windows builds and regressions |

Tasks1–17 can progress without waiting on all protocol clarifications, using schema-valid offline mocks and explicit unresolved-country cases. Task18/19 must not silently select an invented security/date contract. EU error simulation can be explicit and isolated because the official document permits it; it must never add production branches keyed to official fictional guest names, FOGL IDs or the resend marker.

## Analysis verification and next task

Case extraction was cross-checked against the case-definition tables (including two cases in tables34,132,152,164); workbook sums and sheet inventory were checked. Existing backend functions, schema definitions, worker and Flutter source were read without importing or starting the backend. Existing uncommitted implementation and unfinished verification remain unchanged. No new backend/Flutter tests or builds were run for this documentation-only task, and no previous pass count is presented as current certification evidence.

Task1 subsequently implemented and verified on 2026-11-19; see [Task1 report](TASK1_PHYSICAL_UNITS.md). Recommended next development task: **Task2 only**, multi-unit reservation allocations and move history using the new physical unit identities. Reporting certification remains incomplete.

Source SHA-256 fingerprints (for reproducibility):

- `PMS_v9_Interfész_Validációs_Tesztfeladatok_v1.07.docx`: `fda01b01e918a2ea78c05f7594a04d8f43fc2ee68bc85d58429fa179472f6bd8`
- `Szobatükör_segédlet_v1.07.xlsx`: `223537827dc3c2177ae520b8d33c19de53b670657e1f9b2388140373c2bdadeb`

## Task1 implementation update — 2026-11-19

Physical inventory/OOO/OOS model gap in the earlier analysis is now addressed by `physical_units.py` and migration3074. This update supersedes only that part of the historical gap inventory: no allocations, stay events, ledgers, SOAP or Flutter controls were added. Aggregate room-type/Channex inventory remains unchanged. Dated capacity is operational physical capacity, not reservation availability. Zero configured physical records is not a verified zero-room property. Historical room-type links and bed capacities are versioned; periods retain cancellation provenance. All74 relevant guarded backend tests passed, including16 Task1 tests and existing reservation, distribution, persistent-development and NTAK suites (two dependency deprecation warnings). Persistent development data was not accessed or reset. No official validation was run.

## Task2 implementation update — 2026-11-19

Implemented multi-unit overnight planned allocations, transactional replacement/history, reservation date/cancel lifecycle and aggregate quantity reconciliation. No extra reservations/provider identities are created. Unallocated legacy/imported bookings retain their one-unit default. Task1 physical maintenance edits now validate inverse allocation conflicts. Details, test results and the independently reproduced pre-existing test_v293 registration failure are in [TASK2_RESERVATION_ALLOCATIONS.md](TASK2_RESERVATION_ALLOCATIONS.md). Next task: Task3, ordinary reservation reporting fields/API/import capture; no official validation readiness is claimed. The earlier Task2 recommendation is superseded by this implementation update.

## Tasks3–5 implementation update — 2026-11-19

See [TASKS3_5_IMPLEMENTATION.md](TASKS3_5_IMPLEMENTATION.md) for migrations3076/3077, APIs, UI entry points and actual test results. This update supersedes the corresponding earlier gap inventory only. Normal booking fields and allocations now save transactionally and capture revisions automatically; imported bookings with unavailable original provider timestamp remain usable but reporting-blocked. Property inventory and normal booking controls expose planned units and reconciliation warnings. Effective encrypted guest profiles preserve manual/correction provenance separately from raw scans; reviewed corrections cannot change a frozen reporting ID.

Additional explicit blocker: interface v9.07 pp57–59 provides a canonical hash example but not a complete international name normalization/name-order policy. `identity_for_submission` requires an approved internal canonical identity result for the first freeze, otherwise `identity_normalization_unresolved`. No manual hash-input editor or guessed name reordering was introduced. Task5 automatic first identity derivation is blocked specifically; all unaffected profile/history/storage functionality is implemented. Statutory IFA codes from pp79–80 are supported; undisclosed local exemption mappings are not invented. Tasks6–9 can proceed on these data foundations with the identity gate respected. No actual arrivals, room-transfer reporting, day-use, ledger or official transmission was added.

## Tasks6–9 implementation update — 2026-11-19

See [TASKS6_9_IMPLEMENTATION.md](TASKS6_9_IMPLEMENTATION.md) for migrations3078–3080, APIs, lifecycle/correction rules, day-use inventory semantics and actual verification results. This update supersedes only the corresponding earlier gaps. Actual business events survive reporting blockers and are distinct from registration and planned allocations. No certification-only workflow or guessed first identity was added. Official normalization, signature and response-contract gates remain; mocked offline scenarios are not official validation.

Tasks10–14 can proceed using retained reservation revenue, effective profiles, allocation history and actual occupancy facts. Itemized ledgers, settlement, operating-day close and full daily snapshots remain unimplemented. Persistent development data was not accessed or reset; no government/Channex calls, deployment, credentials, commit or push occurred.
