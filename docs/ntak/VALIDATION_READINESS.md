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

Current checkpoint: **L** = normal local core covered offline; **P** = partial official rehearsal/evidence; **B** = specific contract block. All cases retain common signing/transmission/evidence gates. Local coverage is not official acceptance. No case is marked passed. Q/C and evidence export are common dependencies for every case, even where omitted from the dependency cell. Dependencies below are engineering prerequisites unless explicitly prescribed by the source.

| Official ID (DOCX table) | Required operation and principal expected facts | Existing backend / Flutter map | Status and missing capability | Dependencies |
|---|---|---|---|---|
| ELO_01A (4) | Create FOGL_04, room101, HU, TX+1→TX+2, direct online, individual business, guaranteed, HUF20,000, expected1 | Current normal APIs/Flutter; see Tasks3-14 reports | L: Normal create fields/unit allocation/automatic reservation capture covered offline; official endpoint/evidence outstanding | Physical inventory; R facts; Q/C |
| ELO_01B (5) | Create FOGL_05, room103, other foreign, TX+1→TX+2, intermediary offline, group business, not guaranteed, HUF28,000, expected2 | Current normal APIs/Flutter; see Tasks3-14 reports | B: Normal booking exists; other-foreign EGYEBKULFOLDI encoding is contract-blocked | Inventory; country-contract resolution |
| ELO_02 (17) | Modify FOGL_04 arrival to TX, guarantee false, HUF40,000 | Current normal APIs/Flutter; see Tasks3-14 reports | L: Normal guarantee/date/amount modification and revision capture covered; past-arrival policy conflict remains explicit | ELO_01A |
| ELO_03 (25) | Cancel FOGL_05 | Current normal APIs/Flutter; see Tasks3-14 reports | L: Normal cancellation/history/release/capture covered; dependent ELO_01B country/official evidence remains | ELO_01B |
| ES_01A (33) | FOGL_01 room101: Luca Ferri, Zsidi Mária, Zsidi Tibor arrival T02 | Current normal APIs/Flutter; see Tasks3-14 reports | L: Group actual arrival/registration separation covered; fictional Tibor correction sequence demonstrated, no duplicate genuine arrival | FOGL_01, guests, room101 |
| ES_01B (34) | Natasha, FOGL_02 room102, arrival T02 | Current normal APIs/Flutter; see Tasks3-14 reports | L: Individual actual arrival in102 covered; first identity gated unless legitimately frozen | FOGL_02, guest identity, room102 |
| ES_01C (34) | Sergey, FOGL_02 room103, arrival T04 | Current normal APIs/Flutter; see Tasks3-14 reports | L: Later individual arrival on same booking covered; identity gate as above | FOGL_02; unit assignment after ES_03 |
| ES_02 (50) | Erroneous arrival of Zsidi Tibor, FOGL_01 room101 T02 | Current normal APIs/Flutter; see Tasks3-14 reports | L: Audited erroneous-arrival reversal and unsent/processed semantics covered; source scenario sequence ambiguity remains | ES_01A; clarify repeated Tibor entry |
| ES_03 (58) | FOGL_02 room102→103 on T03 | Current normal APIs/Flutter; see Tasks3-14 reports | L: Actual102-to103 transfer, occupancy/allocation history and capture covered | ES_01B; room103 available after OOO |
| ES_04A (66) | Luca and Mária leave FOGL_01 room101 T04 | Current normal APIs/Flutter; see Tasks3-14 reports | L: Group actual departure covered; no inference from scheduled date | ES_01A; correction of Tibor excluded from genuine stay |
| ES_04B (67) | Natasha leaves FOGL_02 room103 T04 | Current normal APIs/Flutter; see Tasks3-14 reports | L: Partial-party departure leaving another guest present covered | ES_01B, ES_03 |
| ES_05 (79) | Erroneous Natasha departure FOGL_02 room103 T04 | Current normal APIs/Flutter; see Tasks3-14 reports | L: Erroneous-departure reversal/retained history covered; ES_04B/05 sequencing ambiguity remains | ES_04B; clarify intended error/correction sequence |
| ES_06A (87) | Nagy Klára FOGL_03 room103, arrival and departure T05 | Current normal APIs/Flutter; see Tasks3-14 reports | L: Same-day103 guest in/out covered with zero nights and normal day-use booking | Day-use support, physical room103, guest identity |
| ES_06B (88) | Kovács Bianka same FOGL_03, room104, in/out T05 | Current normal APIs/Flutter; see Tasks3-14 reports | L: Same booking's104 guest in/out covered; not split into a fictitious second booking | Shared FOGL_03; room104; day-use |
| NZ_01 (108) | New closing for closed-property day T01 | Current normal APIs/Flutter; see Tasks3-14 reports | L: Closed-property snapshot:4 OOO rooms/10 regular places, no sold rooms, schema-valid local capture covered | Inventory; operating status; closing boundary |
| NZ_02 (116) | T02: 3 guest nights,2 sold units, IFA400; OOO103/OOS104; other charges 5,800@18%,4,600@5%,1,000@27%,10,000@27%; card21,400 | Current normal APIs/Flutter; see Tasks3-14 reports | L: Three actual nights/two sold units,400 HUF tax RATE, OOO103/OOS104, other charges5800@18/4600@5/1000@27/10000@27 and card21400 covered. Tax rate is not total tax due. | NZ_01 chronological context; ES_01A/B and Tibor correction |
| NZ_03 (124) | T03:3 nights,2 units, IFA400; workbook full charge list; seven payment categories | Current normal APIs/Flutter; see Tasks3-14 reports | L: All69 worksheet lines,28467 charges, seven payment categories matching28467, three nights/two units covered; metadata and individual lines retained | NZ_02 context; ES_03; complete catalog |
| NZ_04A (132) | T04:2 nights,1 unit, IFA400; Sergey taxable,DOB1986-01-01 | Current normal APIs/Flutter; see Tasks3-14 reports | L: Two nights/one unit, DOB1986-01-01, taxable guest/effective400 rate and IFA charge covered | ES_01C, departure/correction chain, NZ_03 context |
| NZ_04B (132) | Correct T04: Sergey IFA exempt under authority/court reason,DOB1987-02-11; MODOSITO reason VENDEG_VAGY_IFA_JAVITAS | Current normal APIs/Flutter; see Tasks3-14 reports | L: DOB1987-02-11/im5 source correction, IFA reversal, frozen ID and full MODOSITO/VENDEG_VAGY_IFA_JAVITAS covered with mocked processed original | NZ_04A final outcome; IFA mappings |
| NZ_05 (144) | T05 day-use0 nights;103 HUF28,000 cash,104 HUF34,500 card; FOGL_01 post-stay charge/card10,000 | Current normal APIs/Flutter; see Tasks3-14 reports | L: Zero-night103/104 day-use,28000 cash/34500 card and10000 post-stay charge/card linked to original booking covered; correct departure/invoice dates | ES_06A/B; FOGL_01 checkout; ledger |
| EU_01A (152) | TX UJ; FOGL_04 breakfast3,000,000; show TELJESEN_HIBAS | Current normal APIs/Flutter; see Tasks3-14 reports | P: Rejected-outcome parsing/mock queue exists. Safe field-error history and HU/EN source-linked guidance implemented in15; full official extreme-value/evidence rehearsal remains16-17/20; no production guest-name special cases | ELO_02; business-day close; error catalog |
| EU_01B (152) | TX breakfast corrected3,000; still UJ | Current normal APIs/Flutter; see Tasks3-14 reports | P: Rejected-initial -> corrected full UJ semantics covered; full official error/evidence chain remains | EU_01A processing result |
| EU_02A (164) | TX+1 UJ; IFA5%,12 beds,5 rooms; champagne200,001; IFA charge3,000; Tibor postcode1116101 | Current normal APIs/Flutter; see Tasks3-14 reports | P: Processed-review outcome exists; multiple field warnings persist and display with localized source guidance in15; evidence and full official malformed-input rehearsal remain16-17/20 | FOGL_04 actual stays; inventory and ledger |
| EU_02B (164) | TX+1 MODOSITO TECH_HIBA_ADATJAVITAS; IFA400,10 beds,4 rooms; champagne2,000; IFA400; postcode1116 | Current normal APIs/Flutter; see Tasks3-14 reports | P: Review-processed -> MODOSITO/TECH_HIBA_ADATJAVITAS source regeneration covered; full multi-field official rehearsal remains | EU_02A; accepted/reviewed-version semantics |
| EU_03A (176) | TY UJ,IFA400; sole booking __UJRAKULDENDO_VALIDACIO__, no other booking/charge | Current normal APIs/Flutter; see Tasks3-14 reports | P: Task16 synthetic unchanged-resend journey retains exact content, both receipts and polls; complete27-case/official evidence remains20 | Independent TY; closed-day ledger; mock UJRA_KULDENDO |
| EU_03B (177) | Resend identical TY content, obtain TELJESEN_SIKERES | Current normal APIs/Flutter; see Tasks3-14 reports | P: Task16 synthetic unchanged resend and both processing references/polls retained; official validation and full case rehearsal remain20 | EU_03A UJRA_KULDENDO |
| AD_01 (189) | Information request then verification of processing result / expected start date | Current normal APIs/Flutter; see Tasks3-14 reports | B: Explicitly blocked: supplied information/verification response schema does not carry the final expected-start-date field; automatic onboarding is Task19 | C/Q; matching official response schema |

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
| 10 | **Implemented** Decimal itemized charge ledger, official category/subcategory/VAT/package metadata;3081 | 1,2 | All69 worksheet lines round-trip individually, exact28467 HUF; corrections, idempotency and isolated persistence tested. |
| 11 | **Implemented** operational settlements/refunds/post-stay records and normal HU/EN Flutter folios/property finance;3081/3084 | 10 | Seven methods reconcile28467; partial/overpayments, original-linked refunds, history and financial authority tested. No funds collected or legal invoice implied. |
| 12 | **Implemented** operating calendar, property-local dates and chronological manual/opt-in automatic closing;3082 | 6,8-11 | NZ_01 closed day; actual-state readiness, restart recovery and concurrent/idempotent close tested. Inconsistent/unconfirmed/dirty dates stop automatic closing. |
| 13 | **Implemented** encrypted immutable full source snapshots and transactional automatic reporting capture;3082 | 12 | NZ_02-05 operational snapshots validate offline; identity/protocol blockers preserve closed business facts and recover without hand-built payloads. |
| 14 | **Implemented with reporting gates retained** source-derived historical correction revisions;3083 | 5,13 | NZ_04B frozen-ID/IFA/DOB correction; rejected initial -> UJ; processed review -> MODOSITO; receipt/unknown outcome -> durable blocker. Old facts/jobs retained. |
| 15 | **Implemented offline 2026-11-20**: persistent field diagnostics, catalog recovery guidance and normal source links;3088 | Current queue/snapshots | All66 section9.5 keys covered; correlated errors/multiple warnings retained per attempt; HU/EN source workflow controls; see [Task15 report](TASK15_DIAGNOSTICS.md). No SOAP evidence/export claimed. |
| 16 | **Implemented offline 2026-11-20**: immutable encrypted version/request/reply/poll evidence and safe replay boundaries;3089 | 13-15 | Synthetic EU_03 retains byte-identical content and both receipts/polls; crashes/uncertainty are not replayed. See [Tasks16-17 report](TASK16_17_EVIDENCE.md). |
| 17 | **Implemented offline 2026-11-20**: owner/CSRF-scoped redacted canonical JSON export and HU/EN controls | 15,16 | Related versions/attempts/receipts/diagnostics and operator provenance; encrypted wire retained server-side; no official-acceptance claim. See Tasks16-17 report. |
| 18 | **Partial offline 2026-11-20**: explicit RSA SignatureValue/C14N, literal certificate binding and verified TLS foundations; full profile gated | Official signing/digest/response/trust clarification and issued server-held certificate | Synthetic deterministic/tamper, certificate/clock/binding/trust/mTLS tests; no whole-envelope signer or HTTP connector. See [Task18 report](TASK18_SIGNING_READINESS.md). |
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

## Tasks10-14 implementation update - 2026-11-19

See [TASKS10_14_IMPLEMENTATION.md](TASKS10_14_IMPLEMENTATION.md) for additive migrations3081-3084, source-of-truth decisions, APIs, financial/closing Flutter controls, source-derived snapshots and outcome-aware corrections. The official case matrix above now reflects current local coverage; no case is officially passed. The ledger retains all69 worksheet lines and seven settlement categories. Actual guest nights and dated physical history drive closing; no registration/schedule inference or manual reporting payload is used by normal operations.

[NTAK_HANDOFF.md](NTAK_HANDOFF.md) is the self-contained checkpoint before pausing NTAK for later VIZA prioritization. It includes all27 cases, unresolved contracts, known failure, issued test-environment status, exact baseline commands and remaining Tasks15-20. Those tasks and VIZA implementation were not started. Consult its final verification section for current results and device/build limitations. All previous protocol gates and persistent-workspace restrictions remain.

Final Tasks10-14 verification: **131 selected backend tests passed** (two dependency deprecation warnings), **284 Flutter tests passed**, clean Flutter analysis. The separate, pre-existing v293 registration-status test still fails and is explicitly retained/documented in the handoff. No physical device, Android/Windows build, PostgreSQL execution or official validation is claimed.

## Local pre-VIZA checkpoint

NTAK is paused until VIZA integration and validation are completed. The local tag `ntak-pre-viza-checkpoint` preserves implementation through Task14/migration3084 and Task5's explicit first-identity normalization blocker. See [NTAK_HANDOFF.md](NTAK_HANDOFF.md) for the complete resume state. Earlier audit sections and batch reports are historical; the current task/case matrices and latest implementation updates supersede their old gap/next-task statements. This local checkpoint does not enable government transmission or authorize Tasks15-20, VIZA implementation, deployment or pushing.


## NTAK resumed after VIZA checkpoint — 2026-11-20

Current authorized resume starts at `09ae8459ae95299fccfc9af5c1e8ac2d7901701f` (`viza-offline-checkpoint`); the historical NTAK tag remains on `7b9ead2dd7ea5196aee6dd28731aa841738c62c2`. VIZA V01-V08 and migrations3085-3087 are preserved. The pause statements above describe historical checkpoints, not the current instruction.

**Task15 is the first bounded implementation batch**, following the handoff's explicit sequential resume advice. [TASK15_DIAGNOSTICS.md](TASK15_DIAGNOSTICS.md) records implementation, source locations, verification and limits. Migration3088 adds only safe per-attempt NTAK diagnostics. Tasks16-17 remain the next offline batch: complete encrypted SOAP/resend evidence before providing secure export. Existing shared source snapshots, encrypted identity provenance, frozen NTAK IDs, actual stays, allocations, financial ledgers, daily corrections and VIZA delivery semantics are unchanged.

Tasks18-19 require normative signing references and the final-start-date response contract respectively; their unambiguous offline groundwork remains reusable. Task20 depends on the earlier tasks and applicable country/protocol resolutions; no official case has been passed. Task5 remains partial with first-ID normalization blocked. The issued test endpoint/certificate are documented operational facts, not local installation or interoperability evidence. Both government transmissions remain disabled. See the Task15 report for the current test totals and the preserved v293 failure.

Final Task15 verification: **120 backend checks passed**, **300 Flutter tests passed**, Flutter analysis clean and all5 scanner suites passed. Broad earlier backend run230 passed/1 new fixture-assumption failure; corrected schema-negative cases pass in the final run. The separately rerun pre-existing v293 failure remains. No new build/device/official validation is claimed.


## Tasks16-17 implementation update — 2026-11-20

[Tasks16-17 evidence report](TASK16_17_EVIDENCE.md) supersedes earlier pending statements for those tasks. Migration3089 adds immutable encrypted evidence to the existing NTAK queue and an owner-only audited redacted export, including HU/EN controls. EU_03 unchanged resend and separate receipt/poll correlation are demonstrated with synthetic schema-valid mocks; no authority case is officially passed. Earlier missing wire data is not reconstructed. VIZA implementation and Task5 normalization gate remain preserved. Tasks18-20 are unstarted;18/19 retain their official signing/result-schema dependencies. No new transmission, build/device or certification claim is implied.

Final Tasks16-17 verification: **144 shared backend tests passed**, followed by **17 final evidence tests passed** (overlapping counts), **302 Flutter tests passed**, clean analysis and all5 scanner suites passed. Earlier broad249-pass/3-new-test-setup-failure results and their corrections are recorded in the report. The separate pre-existing v293 failure remains. Latest migration3089; no build/device or official transmission claim.


## Task18 signing readiness update — 2026-11-20

[TASK18_SIGNING_READINESS.md](TASK18_SIGNING_READINESS.md) distinguishes explicit requirements, examples and local policies with exact security/appendix citations. The RSA4096 CSR requirement is explicit (section6.1.1 p32); universal certificates are treated as expired3 days early (p30). The explicit Body-only Reference statement (p63) must be distinguished from the inconsistent illustrative Timestamp+Body example (pp61-62); no complete approved profile was selected. Accepted Reference digests, official response security, issuer/software/OID details and environment trust/provisioning remain unresolved. No operational certificate was read.

Task18 is **partial offline**, with a new independent `ntak_security.py` primitive module and safe Task15 failure diagnostics. No migration or Flutter change;3089 remains latest. Tasks16-17 immutable evidence/replay/export boundaries, VIZA and Task5's normalization blocker remain intact. Task19 request/negative-result preparation and resolved Task20 business-flow preparations have independent offline possibilities, but neither task was begun or declared complete. Both government transmissions remain disabled. Tests and external-material requirements are in the report.
