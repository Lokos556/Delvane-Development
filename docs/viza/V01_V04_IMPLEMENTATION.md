# VIZA V01-V04 offline implementation

2026-11-20. Implemented as uncommitted working changes on `main`. Protected HEAD/tag remain `7b9ead2dd7ea5196aee6dd28731aa841738c62c2` / `ntak-pre-viza-checkpoint`. NTAK Tasks1-14 and partial Task5 are preserved. **No official transmission, signing adapter, THF installation or validation is enabled. V05-V10 have not started.**

## Implemented scope

**V01:** `viza_contracts.py` provides typed requests/responses for all four operations, unsigned body/optional SOAP1.1 envelope serialization, safe XML parsing, unchanged-XSD validation and explicit business-rule validation. It preserves all per-guest outcomes and raw multi-error strings, accepting comma/semicolon tokenization without assuming mixed-batch success. It rejects malformed namespaces/operations, DTD/entities, oversized XML, malformed UUIDs, invalid enum/date empties, missing required elements and invalid batches. Names/places enforce200 characters/254 UTF8 bytes; document/visa numbers100 characters. Validation clock and expected-departure parameter are explicit inputs; deployment server settings are not claimed confirmed.

`docs/viza/contracts/` contains the extracted WSDL, its embedded standalone XSD,291 country pairs,73 error definitions with source text/page, and `PROVENANCE.json` containing PDF/asset hashes and extraction provenance. Schema declarations were not amended. The negative cases reproduce the invalid empty-date/enum shapes on p22 and missing `hibaSzoveg` on pp24/27; they do not treat documentation examples as successful signed fixtures. `UnresolvedOuterSecurity` fails closed for Q2.

**V02:** `viza_identity.py` extends the existing guest IDs, encrypted vault and owner verification with encrypted append-only reader/manual history. Original fields never get overwritten by corrections. Each source revision retains fields, actor, timestamp, reason, review flags and raw MRZ birth/code context; projection provides per-field provenance. Authorized `/sources` retrieval preserves subsequent/conflicting reads rather than silently replacing the first original. Paired manual names include the unchanged partner. Combined legacy names are never split or relabelled as reader originals.

VIZA readiness is independent of NTAK hashing. It checks age on the actual arrival business date, under14 document exemption, rolling110-year birth dates, optional birthplace/birth/mother names, country conversions and operator-reviewed third-country applicability. NLD inverse ambiguity and unsupported XKX conversion require review; accepted special codes are not assigned invented meanings. The three third-country elements are always emitted with value/nil as applicable. Corrections require a reason and reset owner verification. Source/reviewer cannot be supplied by the client.

Privacy: DOB/document numbers move from legacy `guest_records` columns into the existing encrypted `sensitive_guest_data` vault. An encrypted compatibility archive preserves both old mutable row facts and the pre-existing vault, including conflicting values; no scan originals are reconstructed. Normal owner APIs hydrate protected legacy defaults where needed. Legacy government snapshots are encrypted, VIZA general previews contain identifiers/completeness only, and stored VIZA preview text is encrypted. Existing PMS display names/nationality remain operational fields; this batch is not a redesign of all PMS personal-data retention. New outbox/audit metadata contains identifiers/codes/field names rather than identity values. Review-flag inputs are allowlisted so arbitrary personal strings cannot enter plaintext blocker diagnostics. No document images are retained.

**V03:** `static/guest-checkin.js` retains parsed structured MRZ names, raw nationality codes and raw MRZ birth context before edits. It records manual deltas and paired corrections; front/back reads cannot silently replace valid front fields. Missing birth names remain unknown. Century/conflicting-code uncertainty requires reception review. Public pre-registration uses a labelled planned-date assessment; actual arrival independently revalidates age/readiness. Under14 pre-registration can omit document fields. Registration/scanning never implies arrival or owner verification.

The existing Tesseract/OCR engine remains. Its CDN script now loads asynchronously so manual entry is not blocked by script download; worker/traineddata/CDN access is still required for OCR first use. No offline-cache, vendor approval or camera-accuracy claim is made. `guest_reporting_controls.dart` / `reservation_dialogs.dart` add normal HU/EN reception review with read-only originals, structured pairs, country/document/visa/entry fields, applicability, ambiguity confirmation and correction reason. It reuses `InventoryForm`, existing sessions and CSRF.

**V04:** `viza_reporting.py` runs inside the existing actual-stay transaction. Each genuine guest visit has its own lowercase UUID; messages, group events, NTAK IDs and occupancy segments remain independent. Transfers do not create a new visit. Departures reference the original UUID. Groups split into batches of at most10. Captured identity/business facts are encrypted and immutable; generic government outbox rows contain routing identifiers only. Property/identity/protocol blockers do not abort legitimate PMS stay operations.

Duplicate/concurrent requests, rollback and restart use existing property/reservation locks plus unique visit/event constraints. Processing markers make no-message corrections idempotent too. Existing pre-migration stay events are explicitly excluded from automatic UUID inference; a later departure without an original VIZA UUID gets a legacy blocker. Existing reservation/registration preparation rows cannot be read by the new typed VIZA capture/serializer path.

Erroneous arrival closes/retires its UUID permanently; later genuine arrival gets a new UUID. Never-sent invalid arrival work is superseded with unaffected group members retained; the closure is recorded locally and held from sending an arrival that THF never received. Accepted arrivals can produce the documented departure closure; uncertain arrivals retain Q7 closure holds. Never-sent timestamp/departure corrections preserve old snapshots and create/suppress revisions as appropriate. Accepted/uncertain unsupported corrections retain Q5 holds on the visit, including subsequent work. Same-day expected-departure ambiguity retains Q6 holds without changing truthful PMS day-use dates/times. Historical-noon fallback was not introduced: actual timestamp remains explicitly required.

## Migrations and API changes

- **3085** `encrypted_identity_provenance`: `guest_identity_sources`, immutable-history triggers, `legacy_guest_identity_archives`; encrypted compatibility/privacy conversion during normal initialization. No operational database was migrated in this assignment.
- **3086** `viza_actual_visit_capture`: `viza_visits`, active-visit uniqueness, `viza_jobs`, immutable-fact trigger, `viza_job_guests`, `viza_visit_holds`, `viza_captured_events`. Repeated initialization preserves visits and excludes only pre-migration events on first application.
- GET/PUT `/api/registration/records/{guest_id}/viza-identity`; GET `/sources` suffix. Owner/manager, organization/property lookup, reservation locking and existing CSRF apply. API state specifies when readiness is only a planned-date preview.
- Existing scanner/public check-in bodies accept `scanned_fields`, `manual_fields`, `scan_ambiguities`, `reader_context` alongside legacy display fields. Original fields remain client reader claims, not hardware attestation; owner verification is still required.
- Existing actual-stay GET includes redacted `viza_reporting` diagnostics. Existing reporting-recovery POST can create fresh immutable never-sent VIZA arrival revisions after normal identity correction/verification. It never transmits or retries an uncertain report.

## Verification

- Final VIZA contract/provenance/capture suite: **40 passed**,2 dependency deprecation warnings,22.36s. Includes all four request/response paths, malformed examples/XML, Unicode/nil/batch boundaries, paired corrections, age/countries, encryption/legacy migration, visit lifecycle, uncertain/accepted/never-sent corrections, concurrency/idempotency/rollback/restart, legacy exclusion and day-use holds.
- Broader backend run: **162 passed,1 failed**,2 dependency deprecation warnings,173.19s. The failure is the previously documented `tests/test_v293.py::test_modification_preserves_manual_fields_and_cancellation_updates_cleaning`: expected registration `complete`, actual `incomplete`. Its assertion was preserved. This run covered VIZA, guest registration/verification, actual stays, NTAK profiles/contracts/reporting, units/allocations, normal reservation reporting, day-use, folios, daily closing, persistence and existing Channex/import behavior (`test_v293.py`, `test_v2991.py`). The final focused run above additionally verifies the last conditional-source/legacy-exclusion refinements; the broader run was not repeated after those bounded changes.
- JavaScript: all four existing scripts passed, plus new `tests/test_viza_scanner_provenance.js`. These exercise synthetic parsing/UI/provenance; they do not execute physical OCR.
- Flutter: **288 tests passed** (284 existing +4 new HU/EN mobile/desktop identity-review tests),37s; `flutter analyze --no-pub`: **no issues**,2.4s.
- `git diff --check`: clean. HEAD and checkpoint tag independently verified unchanged.

Reproduction (repository root, isolated guards are automatically installed by root conftest):

```powershell
.\.venv\Scripts\python -B -m pytest tests/test_viza_contracts.py tests/test_viza_identity_capture.py -q
.\.venv\Scripts\python -B -m pytest tests/test_guest_checkin.py tests/test_guest_checkin_lifecycle.py tests/test_v3000.py tests/test_actual_stays.py tests/test_guest_reporting_profile.py tests/test_physical_units.py tests/test_reservation_allocations.py tests/test_normal_reporting.py tests/test_day_use.py tests/test_financial_ledger.py tests/test_business_days.py tests/test_ntak_reporting.py tests/test_ntak_contracts.py tests/test_persistent_development.py tests/test_v293.py tests/test_v2991.py -q
node tests/test_mrz_parser.js
node tests/test_guest_scanner_parser.js
node tests/test_v21089_hungarian_id_ocr.js
node tests/test_guest_registration_ui.js
node tests/test_viza_scanner_provenance.js
Set-Location C:\Delvane\Delvane-Development\apps\delvane_business
flutter analyze --no-pub
flutter test --no-pub
```

Local verification logs are ignored under `build/viza-audit/` (`v01-v04-final-focused.txt`, `v01-v04-final-backend.txt`, `v01-v04-final-flutter.txt`, `v01-v04-analysis.txt`).

Tests use the repository's isolated SQLite/encryption/network guards and fictional guests. Both migrations are applied repeatedly in tests. PostgreSQL trigger branches are implemented but have not been exercised against a PostgreSQL server; this remains a deployment verification requirement. Persistence tests use temporary stores, never the user's persistent workspace.

The two superseded JS assertions were deliberately replaced: invented birth-name fallback is now forbidden, and DOB minimum is rolling110 years instead of1920. Other valid assertions remain. Implementation-time SQL insertion/migration-marker errors were caught and fixed; the final results below are the completion evidence.

No Android/Windows build or physical-device/OCR test was performed in this batch. Flutter remains3.50.0 / Dart3.14.0. Device/browser camera, actual OCR accuracy, first-load asset access and deployed database verification remain outstanding.

## Unresolved requirements and next bounded work

All Q1-Q9 in [SPECIFICATION_REVIEW.md](SPECIFICATION_REVIEW.md) remain documented. None is declared resolved by a mock or code change. Q1 assigned endpoint binding, Q2 outer WS-Security, Q3 invalid samples, Q4 delimiters/mixed outcomes, Q5 submitted corrections, Q6 day-use, Q7 uncertain outcomes/list caps, Q8 code ambiguity and Q9 conditional/server rules retain their applicable holds. Typed business bodies/capture are implemented; signing, secure sending, THF health and official acceptance are not.

For **V05**, reuse the captured facts and contract types; bind provider/property/environment and8-character reporting ID to existing server-held credentials/trust. Implement only documented property RSA-SHA256 validation; resolve normative outer security before enabling it. No secrets belong in Flutter or these documents.

For **V06**, extend these job/guest/predecessor facts with delivery leases, all per-guest dependency edges/outcomes, protected receipts, the VIZA retry policy and THF polling/list correlation. The current predecessor pointer is a capture aid, not a completed delivery scheduler. A global receipt boolean or missing list entry must never become delivery proof. Preserve every Q5/Q6/Q7 hold and never send generic legacy preparation rows.

For **V07**, reuse normal identity review and redacted actual-stay diagnostics; add property-scoped THF health/status/outcome/recovery management only after V05-V06 read models exist. Do not label local capture counts as live THF health.

No V05-V10, NTAK15-20, deployment, credentials replacement, commit, push or checkpoint-tag update occurred.
