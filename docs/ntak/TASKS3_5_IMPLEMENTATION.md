# Tasks 3–5 implementation report

Date: 2026-11-19. Existing uncommitted work preserved. Official transmission remains disabled. No persistent development database access/reset, external government/Channex request, deployment, private-key generation, commit or push occurred.

## Implemented behavior

### Task3 normal reservation facts

Normal reservation POST/PATCH accepts `reporting` with `garantaltFoglalas` (boolean or unknown), `expected_guest_count`, `vendegKuldoOrszaga`, `ertekesitesiCsatorna`, `piaciSzegmens`. Values are validated against the supplied v9 enumerations/country appendix; missing values remain unknown. EGYEBKULFOLDI is retained as entered but produces `sending_country_contract_unresolved`, never a substitute code. This remains an ordinary booking save, not a reporting-payload editor.

Normal reservation forms can include `allocations` in the same transaction using Task2 assignment shape. Invalid facts/allocations roll back the booking and outbox together. Normal allocation PUT now also captures the resulting reportable revision. Physical allocations supply official unit classifications and regular capacity (excluding extra beds); cancellation retains the last reportable unit facts after physical assignments are released.

Migration3076 adds `reservations.ntak_booking_id` and `booking_created_at`. Stable IDs are backfilled from existing primary IDs; direct legacy booking timestamps can reuse their recorded creation time. New ordinary bookings record their original creation timestamp. Provider ingestion timestamps are **not** treated as original provider booking times: where the normalized import lacks an original time, reporting explicitly blocks with `original_booking_timestamp_missing`; the imported PMS booking remains usable. No provider parser contract was guessed. Imported/manual verified reporting facts are stored separately and are not overwritten by existing provider updates.

Capture reuses existing government outbox/jobs/version fingerprinting. A→B→A yields distinct revisions; an identical repeated operation yields none. Frozen booking identity and immutable historical payloads remain intact. Missing total, allocation, timestamp or classification facts block reporting rather than preventing ordinary PMS use. No guest arrival is inferred.

Read operation: `GET /api/reservations/{id}/reporting-details` returns normal editable values, missing-field list, stable reporting booking ID and original timestamp. Identity fields are not writable through that endpoint. Existing legacy developer facts API remains for compatibility; the new ordinary workflow does not depend on it.

### Task4 Flutter controls

- Existing property workspace opens **Apartments and rooms**: effective-date physical inventory, room-type mapping, building/unit labels, official classification, bed counts, active/inactive version editing, dated OOO/OOS creation, period history and dated reopening.
- Capacity view compares physical counts with existing aggregate channel quantities and displays mismatches. It explicitly states that maintenance periods do not automatically close external channel availability.
- Existing reservation editor includes **Booking details and planned units**: guarantee, expected guest count, sending country, sales channel, stay purpose, incomplete-reporting indicator and multiple planned units. Saving uses normal reservation POST/PATCH so fields and new allocations are transactional. Existing split allocations are retained unless the user deliberately changes selection.
- Planned assignments explicitly do not establish actual guest arrival. No certification-only booking flow, NTAK payload input or live Send button was added.
- Uses existing PmsModal/PmsForm/fields/selectors/cards/actions, required indicators, responsive vertical layouts, brand theme and contextual expansion. No new horizontal scroller. Hungarian copy added; English uses the normal source strings. Existing hu-default preference is unchanged.

Physical edits remain append-only Task1 versions: to edit a unit already effective today, choose a later effective date. Retirement/reactivation does not erase history. Existing physical and aggregate inventory remain distinct declarations; discrepancies are shown rather than silently changing published stock. Task2 quantity-aware reservation demand remains the channel calculation source.

### Task5 encrypted guest profile and stable identity

Normal identity-review cards now open **Residence and tourism tax**, with legal name, DOB, birth name/place, sex, residence country/postcode, IFA obligation/exemption and effective date/reason. Residence is separate from nationality. Official statutory reason mappings are KOTELES, im1,im2,im3,im4,im5,im6,im8,im9,im10 (interface v9.07 pp79–80). Unsupported local/dynamic codes are rejected rather than invented. A local exemption not covered by this list needs its official property-specific mapping before reporting.

Migration3077 adds encrypted, effective-dated `guest_reporting_profiles` revisions with ordered revision numbers and actor/source/reason provenance, plus encrypted permanent `ntak_property_salts`. Existing encryption helpers/key infrastructure are reused. Profile API is `GET /api/registration/records/{id}/reporting-profile?business_date=YYYY-MM-DD` and PUT at the same path. Only owner/manager sessions can access the scoped guest/reservation/property. CSRF middleware remains effective. Manual/correction provenance cannot be labelled scanner-origin through this endpoint.

Raw scanned/guest-submitted fields remain in existing registration/vault records; corrections are stored as a separate operational source, not rewritten as a fresh scan. Profile changes reset existing identity review to needs_review. The immutable profile revision history preserves corrections. Audit events contain field source/effective date and IDs, not identity field values, salts or canonical hash input. Review consumers for future VIZA/stay reporting must resolve the effective operational profile while retaining the raw scan source.

`identity_for_submission` provides the property-isolated freeze-on-first-reporting-use boundary, using existing `ntak_guest_ids`. The permanent bcrypt salt is created only when an approved canonical identity is first supplied internally, encrypted and never rotated by profile edits. Once frozen, the same reporting ID is returned after DOB/name/IFA corrections, including the NZ_04B regression. Salt and canonical identity inputs have no Flutter/HTTP upload or download field. No real property salt was generated; tests use isolated data only.

**Normalization blocker:** supplied v9.07 pp57–59 establishes UTF-8 identity input → SHA256 lowercase hexadecimal → bcrypt with permanent property salt → final31 characters, and the published example passes exactly. It does not establish a complete international name-order/normalization policy; its English name description and concatenated example differ. The algorithm is implemented, but automatic canonical-name construction is not guessed. Missing an approved canonical identity adapter raises `identity_normalization_unresolved`; the API reports that state. Tests supply canonical input only to the internal helper. No user-facing manual canonical-hash editor bypasses this block. Task5 is therefore implemented for operational profiles, salt/identity storage and frozen reuse, with automatic first identity derivation explicitly protocol-blocked.

## Verification

Task3 was verified before Flutter work:24 backend tests passed across normal reporting, prior reporting and allocations. Task4 initially passed two HU/EN form tests before guest work; the subsequent planned-two-unit selection test also passed. Task5 and normal-reporting focused suite:14 passed. Broad backend run:99 passed with two existing FastAPI/Starlette deprecation warnings. Final refinements were followed by22 backend checks (normal reporting, profiles and allocations), all passed; official-country validation was subsequently checked again: **14 passed**. Final normal multi-unit creation test: **3 normal-reporting tests passed**.

Full Flutter run:274 passed before adding the two-unit selection test; three focused controls tests then passed. Final full Flutter run: **275 passed**; clean Flutter analysis. An additional property-creation test was then added; all **4 focused controls tests passed**, including that test. No physical Android/Windows verification or build result is claimed for this batch.

Initial test failures were corrected: a query incorrectly looked for reservation_id directly on ntak_jobs instead of joining government_outbox; fixed. A later timestamp-validation edit caused a syntax error caught at test collection; fixed before rerun. Flutter formatting lint/import warnings were removed, not suppressed. The independently reproduced pre-existing test_v293 guest-registration status failure remains documented in Task2's report; that legacy failing test was not changed and was not included in the99-test command.

Broad guarded backend command:

```powershell
Set-Location C:\Delvane\Delvane-Development
.\.venv\Scripts\python -B -m pytest tests/test_normal_reporting.py tests/test_guest_reporting_profile.py tests/test_reservation_allocations.py tests/test_physical_units.py tests/test_flutter_reservation_reception.py tests/test_flutter_distribution.py tests/test_guest_checkin.py tests/test_guest_checkin_lifecycle.py tests/test_persistent_development.py tests/test_ntak_reporting.py tests/test_ntak_contracts.py tests/test_v3000.py -q
Set-Location apps\delvane_business
flutter analyze
flutter test
```

New coverage includes ELO_01A-like creation, guarantee modification/ELO_02 facts, cancellation/ELO_03 retention, ELO_01B country blocker, schema-valid capture, rollback, A→B→A versus identical saves, physical allocation creation through normal booking API, multi-unit Flutter selection, HU/EN required fields/Unicode input, residence/nationality separation, official IFA codes, encrypted history, official hash example, property scope and frozen DOB correction. Prior guest/allocation/provider and persistent-workspace tests remain guarded. No genuine NTAK communication or certification result is claimed.

## Files and remaining boundaries

New backend files: `reservation_reporting.py`, `guest_reporting.py`, `ntak_countries.py`; normal mutation/capture hooks in `app.py`, `ntak_reporting.py`, `reservation_allocations.py`. New Flutter files: `inventory_controls.dart`, `booking_reporting_controls.dart`, `guest_reporting_controls.dart`; existing property and reservation dialog entry points and native Hungarian strings updated. New tests: `test_normal_reporting.py`, `test_guest_reporting_profile.py`, Flutter `inventory_controls_test.dart`. Official schemas unchanged.

Unresolved start-date response/signature profile remain blocked. Original imported booking times absent from normalized source data remain explicit missing facts. Automatic guest identity normalization and local IFA reason mappings remain gated as above. No actual stays, room transfers, day-use, financial ledgers or SOAP implementation was added. Tasks6–9 can begin on the planned allocation and effective guest-profile foundations; first resolve actual-event provenance and use the identity boundary without pretending normalization is approved. Day-use remains Task9.
