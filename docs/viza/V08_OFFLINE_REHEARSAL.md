# V08 offline integration rehearsal

2026-11-20. **Synthetic engineering evidence only: no official exercise, endpoint, acceptance or certification.** Existing V01-V07 work was preserved. NTAK remains paused at commit/tag `7b9ead2dd7ea5196aee6dd28731aa841738c62c2` / `ntak-pre-viza-checkpoint`. Latest migration remains3087; V08 adds no schema migration. V09/V10 were not begun.

## Combined rehearsal and fixes

`tests/test_viza_rehearsal.py` now provides9 guarded synthetic cases. The main journey uses ordinary APIs for physical-unit setup, booking creation/modification/allocation, unauthenticated public check-in tokens, parsed identity submission, owner corrections/verification, actual individual/group arrival, transfer and departure. It generates a disposable4096-bit RSA key/certificate only inside the isolated test directory, signs schema-valid bodies using the actual property-validation implementation, independently verifies the signatures, and injects mock THF receipts/status/list responses. Flutter-facing management APIs return mock-labelled per-guest states with downstream delivery still unknown.

The main reservation has3 guests, including a child without document fields, two arrival times, a room transfer, and three departure times. Scanning, scheduled arrival_time, registration and verification produce zero VIZA actual-arrival jobs. Only actual-stay actions capture them. Three durable per-guest arrival UUIDs survive reinitialization/transfer and are reused by each guest's departure; five actual reporting messages are accepted **by the mock only**. Empty lists do not change downstream delivery. The source originals, paired manual changes, encrypted snapshots, outbox/attempt diagnostics, protected DOB/document storage and immutable-fact trigger are checked without exporting identity XML or keys into general logs.

The rehearsal found and fixed these genuine local integration defects:

1. **Raw-country completeness disagreement:** reader `HUN` was correctly normalized to `HU` for VIZA readiness but owner review used the raw code for registration completeness, causing409 on verification. `viza_identity.py` now uses the same normalized/source-aware assessment and stores only the canonical operational country projection; immutable original `HUN` remains intact.
2. **Minor blocked by browser confirmation:** the page's required flags could be relaxed, but the actual confirm handler still unconditionally required document fields. `static/guest-checkin.js` now applies the under14 rule to that handler and both document controls/markers. The existing fifth JS suite now executes the real handler, proving minor submission and adult-document rejection. No-scanner entry is labelled manual rather than MRZ.
3. **Untrusted audit source text:** unrestricted public `scan_method` could carry identity text into plaintext event/audit metadata. `GuestCheckinSubmitBody` now accepts only `camera_mrz`, `camera_ocr`, `camera_mrz_plus_ocr`, `manual`, `id_scanner`; invalid values fail with a redacted422 and no audit leak. No scanned field value is stripped or transliterated.
4. **Obsolete verified snapshot after correction:** an identity edit after capture could leave an old verified snapshot eligible for sending. `viza_delivery.source_matches` checks actual-arrival-date source/readiness; never-attempted work is automatically superseded by fresh encrypted immutable revisions. The send transaction rechecks source, holds, binding and supersession after rendering. Old unsent dependency edges are removed within the current job scope so valid replacements can precede the original departure correctly without cleaning another property's work. Accepted/uncertain work is never silently replaced/replayed, and UUIDs remain stable.

One new rehearsal assertion initially assumed rotated links returned410; existing rotation intentionally deletes the old hash and returns404. Source inspection confirmed the intended denial, and the new assertion now checks404. Previously existing valid assertions were not weakened. Product-defect failures were first observed against the old behavior, then verified after fixes.

## Edge/security evidence map

These are internal synthetic test names, not authority validation identifiers.

| Requirement | Evidence / actual boundary |
|---|---|
| Reservation create/modify, public check-in, original/manual pair, review, signed arrival/transfer/departure | `test_viza_rehearsal.py::test_full_public_registration_to_signed_mock_arrival_transfer_departure` |
| Under14/day before14/on14; missing optional identity fields | `test_public_minor_boundary_with_normal_owner_review` three parameters; `test_viza_contracts.py` under14/rolling-date/nil/source-pair tests; actual browser handler assertions in `test_viza_scanner_provenance.js` |
| Country ambiguity,291-code set and third-country applicable/nonapplicable fields | `test_viza_identity_capture.py::test_country_third_country_optional_fields_and_readiness`; `test_viza_contracts.py::test_rolling_birth_date_and_countries` |
| Incomplete identity allows truthful PMS occupancy but blocks reporting | `test_actual_stays.py` initial identity blocker/recovery; `test_viza_identity_capture.py` missing owner/profile/identity cases |
|12 guests split10+2; partial/group/individual visits, transfer/restart/retirement/new visit | `test_viza_identity_capture.py` group/lifecycle/outcome policy tests; `test_actual_stays.py` group/multi-unit/corrections; combined main journey |
| Same-day truth preserved and VIZA Q6 gate | `test_same_day_pms_remains_valid_with_explicit_viza_hold`; `test_day_use.py` |
| Outage, definitely-not-sent timing, all retry steps, uncertain/permanent/mixed/multiple-code results | `test_viza_delivery.py` retry/outage/per-guest/error cases |
| Crash before/after possible-send marker, concurrent workers, duplicate prevention | `test_claim_crash_and_sending_crash_recovery`, `test_automatic_capture_and_mock_receipt_concurrent_workers`; actual-stay idempotency/concurrency/rollback suites |
| Late source changes and correct departure dependencies | Rehearsal `test_owner_correction_after_capture_never_sends_obsolete_identity`, `test_correction_during_render_is_held_before_send_marker`, `test_unsent_source_refresh_preserves_departure_dependencies` |
| Malformed/oversized/DTD XML, wrong request/receipt UUID | `test_viza_delivery.py` invalid receipt/correlation tests; `test_viza_contracts.py` XML safety/negative official sample shapes |
| All9 health flags, primary/compound codes, unknown/stale observations | `test_viza_delivery.py` health/poll/stale tests; mock CERT-EXPIRED must have ERROR |
| Both list selectors,10000 cap, stored-page scope, no absent-list inference | Delivery monitor/list tests and Flutter stored-list refresh regression |
| Wrong property/environment, missing/expired/mismatched credentials, CA/hostname failures | `test_viza_security.py`; in-memory SSL MemoryBIO only, no network sockets |
| Protected sources/snapshots, plaintext diagnostic checks, redacted input errors | Main rehearsal, untrusted scan-method test, provenance/encryption/immutable/binding tests |
| Role/tenant/property/CSRF, public token scope/revocation | Rehearsal public rotation/payload-scope test, guest lifecycle tests, VIZA API authorization tests |
| NTAK frozen IDs/salts/gates, source facts, IFA, refunds, historical versions, immutable daily closing | `test_guest_reporting_profile.py`, `test_normal_reporting.py`, `test_actual_stays.py`, `test_financial_ledger.py`, `test_business_days.py`, `test_ntak_contracts.py`, `test_ntak_reporting.py`, units/allocations/day-use suites |
| Schema compatibility/migration twice/restart | VIZA provenance/capture/delivery migrations and `test_persistent_development.py`, all temporary SQLite stores |

The complete Flutter suite exercises native form/reception/stay/identity/admin contracts with fake transports; the combined Python journey exercises their real backend routes. This is not a claim that a physical native client connected to the real backend, or that images were scanned successfully.

## Verification and builds

- Final broader backend run: **216 passed,1 independently confirmed pre-existing failure**,2 dependency deprecation warnings,255.76s. Exact failure: `tests/test_v293.py::test_modification_preserves_manual_fields_and_cancellation_updates_cleaning`, expected registration `complete`, actual `incomplete`. All other selected PMS/VIZA/NTAK regressions passed. No test expectation was weakened to hide it.
- Final post-review rehearsal/delivery rerun: **46 passed**,2 dependency warnings,61.75s, after restricting dependency cleanup to the current job scope.
- Combined rehearsal final run: **9 passed**,2 dependency warnings,18.10s. This includes two supplemental race/dependency cases added after the broad run was collected. The preceding focused rehearsal/delivery/identity run passed57 tests after the source-freshness fix. The broad run covers all85 existing VIZA tests as well as the collected rehearsal cases.
- Full Flutter suite: **298 passed**,36s. Analysis: **no issues**,2.2s.
- All5 JavaScript scanner/UI/provenance suites passed, including the new actual confirm-handler minor/adult/manual-source checks.
- Windows release: **passed** using the existing project-local VS2026 fallback. Bundle: `apps/delvane_business/build/windows-vs2026/x64/runner/Release/`; rebuilt Dart `data/app.so` SHA256 `74ba00e28c4159eac36d4989d503e15fc91f3711cb7836d5be234d728750cc9f`.
- Android unsigned release: **attempted and blocked by uncached dependencies in offline mode**; not a passed build. Details below.
- PostgreSQL and physical-device/OCR verification: **not performed**, for the reasons below.
- `git diff --check`: clean; HEAD/tag both independently resolve to the protected commit. Supplied PDF hash remains `4946453bec2af4297316fd0f206c78d1271bdf9bd5ed40ea1f93840665c778b9`.

Ignored local logs: `build/viza-audit/v08-backend-final.txt`, `v08-combined-final.txt`, `v08-rehearsal-final.txt`, `v08-baseline-failure.txt`, `v08-analysis.txt`, `v08-flutter.txt`, `v08-windows.txt`, `v08-android.txt`. Initial defect logs are engineering evidence only and contain fictional values. Test keys/material lived only in the guarded temporary test tree. The ignored checkpoint source archive was used solely for independent baseline-failure reproduction.

Reproduce from the repository root, using the safety harness:

```powershell
.\.venv\Scripts\python -B -m pytest tests/test_viza_rehearsal.py tests/test_viza_contracts.py tests/test_viza_identity_capture.py tests/test_viza_security.py tests/test_viza_delivery.py tests/test_guest_checkin.py tests/test_guest_checkin_lifecycle.py tests/test_v3000.py tests/test_actual_stays.py tests/test_guest_reporting_profile.py tests/test_physical_units.py tests/test_reservation_allocations.py tests/test_normal_reporting.py tests/test_day_use.py tests/test_financial_ledger.py tests/test_business_days.py tests/test_ntak_reporting.py tests/test_ntak_contracts.py tests/test_persistent_development.py tests/test_v293.py tests/test_v2991.py -q
node tests/test_mrz_parser.js
node tests/test_guest_scanner_parser.js
node tests/test_v21089_hungarian_id_ocr.js
node tests/test_guest_registration_ui.js
node tests/test_viza_scanner_provenance.js
Set-Location C:\Delvane\Delvane-Development\apps\delvane_business
flutter analyze --no-pub
flutter test --no-pub
```

The reproduction command now includes all9 rehearsal cases; its total count can exceed the recorded broad run because two cases were added after that run was collected. No unrelated whole-repository test pass is claimed.

The known v293 assertion was independently reproduced from an ignored `git archive` copy of the protected checkpoint, using the current virtual environment and the checkpoint's own guarded tests. Its expected `complete` versus actual `incomplete` result is identical. The working checkout/tag was never reset or restored.

PostgreSQL: no local psql/postgres/pg_ctl/docker executable or PostgreSQL service was available for a safe isolated run. No ports, configured DSNs or operational databases were probed. PostgreSQL trigger/concurrency/migration execution remains outstanding; do not infer it from SQLite success.

Windows release used existing local Flutter/VS2026/CMake support. The initial normal Flutter build hit a pre-existing generator-cache mismatch; the project-local VS2026 fallback compiled/installed the release bundle successfully. The old runner EXE timestamp is normal: Dart code is in the newly rebuilt `data/app.so`. Bundle is not installed or device-tested.

Android release was attempted with cached Gradle9.5.0, `--offline`, process-only normal-path TEMP/TMP, and an ignored init script clearing the release signingConfig so no existing signing key was used. The attempt is **blocked**, not passed: release `io.flutter:flutter_embedding_release:1.0.0-371f77202a73e8dff57a8b3bff75bca55c090aee` and AndroidX annotation artifacts are not cached. No download, toolchain/project migration, credential generation/replacement or physical installation was performed. Existing default debug-key release configuration was not edited. Flutter3.50.0/Dart3.14.0 remain unchanged.

## Readiness result and remaining local limits

The resolved offline lifecycle/security/state/UI paths are implemented and exercised; this is **not external readiness approval**. All Q1-Q9 remain open with operation-specific gates. See [EXTERNAL_READINESS_CHECKLIST.md](EXTERNAL_READINESS_CHECKLIST.md) for exact V09/V10 prerequisites and [IMPLEMENTATION_READINESS.md](IMPLEMENTATION_READINESS.md) for every requirement's current classification.

Explicit limits: real HTTP transport and normative outer WS-Security/response verification are not implemented/enabled; accepted/uncertain corrections, same-day VIZA reporting and positive downstream-delivery proof remain gated. Mixed-property THF list responses are conservatively held rather than selectively exposed. Automatic identity snapshot refresh applies only to never-attempted work; identity changes after a technical attempt are conservatively held and need a separately reviewed trusted-source recovery design, even when a previous failure was labelled definitely-not-sent. Do not turn that limitation into an unrestricted resend.

VIZA source/receipt/binding records are encrypted and general diagnostics redacted, but existing PMS booking/display names and operational nationality remain plaintext for compatibility. This is not a completed system-wide personal-data retention/key-rotation audit. Actual scanner/OCR accuracy, asset offline availability, PostgreSQL and physical Windows/Xiaomi verification remain outstanding.

No official endpoint, existing private key, operational database, real guest, deployment, commit, push or checkpoint-tag change occurred. V09/V10 and resumed NTAK development were not started.

## Build reproduction details

The Windows attempt used `flutter --no-version-check build windows --release --no-pub`. On its existing generator-cache mismatch, the already documented project-local VS2026 fallback was used: resolve installed VS2026 CMake with vswhere, configure `windows` into `build/windows-vs2026/x64` using generator `Visual Studio 18 2026`, architecture x64 and `FLUTTER_TARGET_PLATFORM=windows-x64`, then `cmake --build build/windows-vs2026/x64 --config Release --target INSTALL`. No source/toolchain/cache removal was required. The extra FETCHCONTENT_FULLY_DISCONNECTED flag was unused by this project; no government endpoint was involved.

Android was built directly through the existing cached Gradle9.5.0 installation with `--offline --no-daemon --max-workers=2`, project `apps/delvane_business/android`, target `:app:assembleRelease`, `-Ptarget-platform=android-arm,android-arm64,android-x64`, an absolute `-Ptarget` pointing to `lib/main.dart`, and `-Ptree-shake-icons=true`. TEMP/TMP were restored in `finally`; only an ignored normal-path `build/v08-jvm-tmp` was used. The ignored `build/viza-audit/v08-unsigned.init.gradle` used this build-only override:

```groovy
gradle.beforeProject { project ->
    project.plugins.withId('com.android.application') {
        project.extensions.getByName('androidComponents').finalizeDsl { android ->
            android.buildTypes.getByName('release').signingConfig = null
        }
    }
}
```

Pass the init script with an **absolute** `-I` path because Gradle resolves relative paths from the Android project. The first attempt with a relative init path failed before compilation; the corrected attempt reached release dependency resolution and failed on the uncached artifacts described above. Do not retry with existing private/debug keys or substitute fake dependencies.
