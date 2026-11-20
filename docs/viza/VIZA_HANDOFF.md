# Delvane VIZA development handoff

Checkpoint date:2026-11-20, after V08 offline rehearsal. This document is sufficient to resume without previous conversations. **Official government communication is disabled. No official VIZA exercise or physical scanner acceptance has occurred.**

## Repository and protected state

- Repository `C:\Delvane\Delvane-Development`; existing FastAPI backend `app.py`; Flutter app `apps/delvane_business`.
- Branch `main`. Protected tag `ntak-pre-viza-checkpoint` resolves to **7b9ead2dd7ea5196aee6dd28731aa841738c62c2**, preserving NTAK through Task14, migrations through3084 and partial Task5. NTAK development remains paused. At V08 completion HEAD also matched that commit; the subsequently authorized local VIZA checkpoint advances HEAD without moving the NTAK tag.
- **Local VIZA checkpoint:** the annotated tag `viza-offline-checkpoint` identifies the committed V01-V08 offline implementation, tests, official source/contract documentation and Flutter reporting work. Resolve it with `git rev-parse viza-offline-checkpoint^{commit}` and verify its object type with `git cat-file -t viza-offline-checkpoint`. The NTAK tag does NOT contain these newer changes. Inspect the current working tree before resuming and preserve subsequent legitimate work; do not reset/restore the NTAK tag over VIZA or commit/push automatically.
- Latest implementation migration **3087**; V08 adds no migration. Only guarded fictional SQLite test databases were migrated. The persistent development workspace was never opened/reset/migrated by this task.
- Preserve Flutter **3.50.0**, Dart **3.14.0**, environment isolation, cookie/session/CSRF/property boundaries, shared PMS business logic and all NTAK specification gates.

## Read in this order

1. This handoff and [V08_OFFLINE_REHEARSAL.md](V08_OFFLINE_REHEARSAL.md): current fixes, evidence and limitations.
2. [IMPLEMENTATION_READINESS.md](IMPLEMENTATION_READINESS.md): current20-area classification; historical tables are explicitly superseded.
3. [EXTERNAL_READINESS_CHECKLIST.md](EXTERNAL_READINESS_CHECKLIST.md): exact outstanding V09/V10 items.
4. [SPECIFICATION_REVIEW.md](SPECIFICATION_REVIEW.md): authoritative source references and all Q1-Q9.
5. [V01_V04_IMPLEMENTATION.md](V01_V04_IMPLEMENTATION.md), [V05_V07_IMPLEMENTATION.md](V05_V07_IMPLEMENTATION.md), [IMPLEMENTATION_ROADMAP.md](IMPLEMENTATION_ROADMAP.md) for bounded implementation history.
6. `docs/ntak/NTAK_HANDOFF.md` before changing shared guest/stay/financial/calendar/reporting infrastructure.

Authority is `docs/viza/pms_thf_viza_if_v700_hu.pdf`, v700,2024-02-22,57 pages, SHA256 `4946453bec2af4297316fd0f206c78d1271bdf9bd5ed40ea1f93840665c778b9`. Section5 pp28-43 embeds one complete XSD; no external import/include is missing. Do not amend the schema to make malformed documentation examples validate. VIZA official validation exercises/sample cards have not been supplied.

## What is implemented

| Batch | Current state |
|---|---|
| V01 | Typed all4 THF request/response business bodies, unchanged local schema validation, safe XML/business limits,291 country pairs and73 errors with source pages. Unsigned SOAP bodies are not outer WS-Security. |
| V02-V03 | Encrypted immutable reader/manual source history, field provenance/pairs, under14/optional/Unicode/country rules, normal public browser check-in and HU/EN reception review. Original values are retained; combined legacy names are not split. Actual OCR/device accuracy remains unverified. |
| V04 | Automatic actual per-guest visit UUIDs and encrypted immutable capture, max10 batching, transfer/restart stability, departure references, closure/retirement and outcome-aware correction holds. Registration/planning does not infer arrival. |
| V05 | Exact property RSA-SHA256 validation with Base64 DER/signature, server-held binding/CN/fingerprint checks, verified TLS foundations and disabled live/outer-security interfaces. Only disposable synthetic credentials tested. |
| V06-V07 | Persistent attempts/leases/due times/dependencies, precise retry policy, mock-only receipts/per-guest results/monitoring/lists, scoped administration/source links/local paging and constrained recovery. No configuration can activate live communication. |
| V08 | Nine combined normal-API rehearsal cases, privacy/migration/NTAK regressions, build attempts, current classifications and external checklist. Genuine integration defects fixed; not certification. |
| V09-V10 | **Not begun**: official materials/provisioning/interop/physical scanner/authority exercises remain future authorized work. |

V08 fixes raw `HUN` registration completeness normalization, actual browser minor submission/required markers, untrusted scan_method audit leakage/manual fallback, and stale verified snapshots after source changes. Never-attempted packages now receive new immutable source revisions automatically; source/binding/holds are rechecked after rendering before the possible-send marker. Superseded unsent dependencies are replaced without changing visit UUIDs.

## Migrations and source map

- **3085** `viza_identity.py`: `guest_identity_sources` with immutable triggers; encrypted legacy compatibility archives. Existing `sensitive_guest_data` vault protects DOB/document values previously duplicated into guest_records; legacy government snapshots/previews are protected. Old mutable rows are not reconstructed as scanner originals.
- **3086** `viza_reporting.py`: `viza_visits`, `viza_jobs`, `viza_job_guests`, `viza_visit_holds`, `viza_captured_events`; immutable encrypted facts and stable logical visit IDs. Pre-migration stay events are explicitly excluded from automatic original-UUID inference.
- **3087** `viza_delivery.py`: `viza_settings`, `viza_dispatch`, `viza_attempts`, `viza_guest_outcomes`, `viza_message_status`, `viza_job_dependencies`, `viza_monitor_schedule`, `viza_observations`, `viza_actions`; immutable binding trigger and shared government attempt linkage.
- `viza_contracts.py`: DTOs/serialization/parsing, explicit exact report timestamp, schema/business rules. `docs/viza/contracts/PROVENANCE.json`, WSDL/XSD/countries/errors preserve official asset provenance. `docs/viza/error-messages-en.json` supplies English descriptions; Hungarian source text/pages remain available.
- `viza_security.py`: property validation, pinned verification, safe VIZA credential binding, TLS and outer-security/transport interfaces. `government_security.py` remains the shared safe credential loader; inherited4096-bit policy is local, not a claimed VIZA normative minimum.
- `viza_delivery.py`: source freshness, automatic zero-attempt revision recovery, claims/possible-send markers, definite-not-sent retries versus uncertain holds, all departure predecessors, receipts and monitoring. Mock transport requires explicit internal injection and `APP_ENV=test`; no owner/API mock selector exists.
- `viza_api.py`: property-scoped administration/read models/settings/observations/stored lists/recovery and redacted action/attempt history.
- `app.py`: init/API/worker hooks, public guest workflow and metadata validation. `guest_stays.py`: shared actual-event transaction invokes VIZA and preserved NTAK capture. `guest_reporting.py`: legacy protected-default compatibility; NTAK frozen identity/salt logic retained.
- Browser `static/guest-checkin.js`, HTML/i18n: existing local OCR/MRZ engine, raw source/manual projection, century/code/conflict review, under14 confirmation. Tesseract/CDN first-use dependency remains; no offline OCR promise.
- Flutter `lib/features/pms/{guest_reporting_controls.dart,viza_reporting_dialog.dart,integrations_page.dart,reservation_dialogs.dart,inventory_controls.dart}` and `assets/native-hu.json`: normal source review/admin UI using existing auth/network/design.

Normal APIs: reservation creation/modification/allocation and `/api/reservations/{id}/actual-stay`; token-bound `/api/public/checkin/{token}`; owner verification `/api/reservations/{rid}/guests/{gid}/verify`; GET/PUT `/api/registration/records/{gid}/viza-identity` and GET `/sources`; administration prefix `/api/government/viza/properties/{property_id}` with GET overview, PUT `/settings`, POST `/observe`, POST or stored GET `/lists/{selector}`, POST `/jobs/{id}/recover`. Recovery does not authorize unrestricted resend.

## Security/operational boundaries

`DisabledOfficialTransport.exchange` always refuses. `VerifiedHttpsTransport.exchange` is a disabled interface, not a completed HTTP implementation. `UnresolvedOuterSecurity` refuses signing/response verification. Do not flip `ROSA_MTU_CERTIFIED` or a public configuration flag and assume that makes government transmission safe.

Property signing requires an explicitly supplied server credential root/reference with `certificate.pem`, `private-key.pem`, and `binding.json` identifying VIZA/org/property/environment/reporting_id/endpoint/public fingerprint. Issuer/root CA trust and exact endpoint binding are separate prerequisites. No current NTAK/Hetzner private key was inspected/used. Existing NTAK ticket150337/certificate is not automatically VIZA authorization.

All accepted results in current engineering evidence are mock-labelled THF receipts. Downstream delivery stays unknown unless rejected-list evidence establishes rejection; absence from lists never implies delivery. Q4 mixed results are held. Uncertain/rejected/submitted corrections are not silently reset; visit UUIDs are not manufactured to bypass errors.

Remaining local limitations: changed identity after a technical attempt is conservatively held, including definitely-not-sent cases; safe trusted-source version recovery for that combination remains a separate local design/task. Shared-THF foreign-property lists are held rather than selectively exposed; Q7 behavior needs confirmation. General diagnostic views are bounded, full capped observations remain encrypted. Existing operational display/booking names/nationality remain plaintext; global retention/deletion/key-rotation work is not completed by VIZA encryption tests.

## Current verification and known failures

- Final broad selected backend run: **216 passed,1 independently confirmed pre-existing v293 failure**,2 dependency warnings,255.76s.
- Final combined normal-API rehearsal: **9 passed**,18.10s, including two supplemental late-source/dependency cases not collected in the broad run. Final post-review scoped rehearsal/delivery rerun: **46 passed**,61.75s. Complete evidence is in the V08 report.
- Full Flutter: **298 passed**,36s; analysis clean,2.2s. All5 scanner/UI/provenance suites passed, including the real confirm-handler minor/adult check.
- Windows release built successfully; Android unsigned release attempted but blocked by uncached offline release dependencies.
- SQLite migration/idempotency/restart/concurrency checked; PostgreSQL and physical-device/OCR/live THF evidence outstanding.
- Official PDF unchanged; `git diff --check` clean; protected HEAD/tag independently verified unchanged.

The v293 failure was independently reproduced against the protected commit extracted into an ignored source copy and run under its own isolated test harness. Expected registration `complete`, actual `incomplete`; no existing assertion was weakened. Do not repair it by restoring insecure manual completeness semantics.

Windows bundle: `apps/delvane_business/build/windows-vs2026/x64/runner/Release/`; new Dart `data/app.so` SHA256 `74ba00e28c4159eac36d4989d503e15fc91f3711cb7836d5be234d728750cc9f`. Normal Flutter hit existing CMake generator cache mismatch; existing VS2026 fallback succeeded. No install/device execution was claimed.

Android compile attempt used cached Gradle9.5.0, `--offline`, process-only normal-path TEMP/TMP and an ignored Gradle init script clearing release.signingConfig. It failed on missing release Flutter embedding engine371f772... and AndroidX annotation artifacts. No cached-old APK is evidence of a new successful release. Do not use the existing debug/private signing key just to make this build pass; prefetch approved public dependencies later and use an unsigned build for compilation-only checks.

No isolated PostgreSQL tools/service were available; no operational DSN/port was probed or infrastructure provisioned. PostgreSQL DDL/concurrency, physical Windows/Xiaomi camera/OCR, full native-to-real-backend connection, live signed THF interoperability and official acceptance remain outstanding. Full command/evidence details are in the V08 report.

## Unresolved protocol discrepancies (none resolved by mocks)

| ID | Source | Affected operation / required resolution |
|---|---|---|
| Q1 | Sec4 p9 vs WSDL p43 | Assigned HTTPS test endpoint/bindings versus private HTTP example; no automatic endpoint fallback. |
| Q2 | Sec3.1 p7, examples pp15-27 | All live SOAP signing/response verification: contradictory digest/token/reference/freshness examples; obtain normative policy/vectors. |
| Q3 | Example p22 and pp24/27 | Arrival empty date/enums and receipts missing required hibaSzoveg fail unchanged schema; obtain valid machine-readable examples. |
| Q4 | Schema pp32-33 | Comma/semicolon multi-error and mixed batch/global receipt semantics; preserve all results, hold ambiguous success/replay decisions. |
| Q5 | Sec6.2 p50 | Submitted identity/time/departure corrections: only erroneous-arrival closure is documented; no copied NTAK compensation semantics. |
| Q6 | EF0033 pp45-46 | Same-day expected-departure date: true PMS day-use stays valid, affected VIZA reports remain held. |
| Q7 | Sec2 p6, sec4.1 pp9-10, schema pp31/40, EF0021 p45 | Uncertain replay, late/duplicate reconciliation, positive downstream delivery,10000 cap and shared-property list handling; absence is not delivery evidence. |
| Q8 | Country appendix pp51-57, NLD p55, XK p57 | Ambiguous country inverse/special meanings/XKX variants; keep originals and require reviewed mapping. |
| Q9 | Intro p3, validation pp44-50 | Exact conditional/third-country/server-parameter edge rules; do not invent requirements or facts. |

## Safe reproduction and resume instructions

1. Inspect current branch/working tree and verify both local checkpoint tags; preserve any subsequent uncommitted work. Do not reset/restore the checkpoint or repeat the whole initial audit.
2. Read current V08 readiness/report/checklist. When official materials arrive, compare assigned facts and signed examples against Q1-Q9 before implementing anything speculative. User must authorize that new bounded task; this handoff is not permission for V09/V10 or any live call.
3. Use `.\.venv\Scripts\python -B -m pytest` from repository root. Root `conftest.py`, `testing_safety.py`, `testing_clock.py` install temporary SQLite/encryption/key/network guards BEFORE importing app. Do not import/start app in an ad-hoc script, override `--basetemp`, disable guards, run `run_development_workspace.py`, or point tests at persistent/operational storage.
4. Fast combined rehearsal: `.\.venv\Scripts\python -B -m pytest tests/test_viza_rehearsal.py -q`. Existing VIZA tests: `tests/test_viza_contracts.py`, `test_viza_identity_capture.py`, `test_viza_security.py`, `test_viza_delivery.py`. The V08 report lists the complete backend/NTAK/scanner/Flutter commands.
5. Preserve shared NTAK guest salts/frozen IDs/unresolved first-normalization gate, physical inventory and aggregate Channex source of truth, allocation/occupancy history, day-use truth, ledger/refunds/IFA, operating calendar and immutable daily snapshot/version semantics. Keep `ntak_transport.UnresolvedOfficialTransport` gated; do not resume NTAK15-20 incidentally.
6. Before any future sender enablement, resolve Q2 and implement/verify a real HTTPS connector and signed-response profile as an explicitly authorized task. Complete missing local recovery/PG/build checks, obtain actual certificate/trust bindings and official exercise/sample-card materials, and follow the V09/V10 checklist. Do not invent exercise IDs or call mock passes official acceptance.
7. No external endpoint, current private key, real guest, persistent database, deployment, credential replacement, commit, push or checkpoint-tag change without new applicable authorization.

## Authorized local checkpoint preparation

The user separately authorized a local Git commit and annotated `viza-offline-checkpoint` tag after V08. This permission is limited to preserving the completed offline implementation. It does not authorize V09/V10, NTAK work, a live government call, deployment or push. Earlier reports' no-commit/uncommitted statements describe their original implementation sessions. The checkpoint includes code, synthetic test source, documentation and the unchanged supplied official PDF/WSDL/XSD; ignored environments, current credentials/keys/certificates, databases, builds and diagnostic artifacts stay outside Git.

Checkpoint preparation inspected recorded test/build evidence and transport gates; it does not claim a new application test/build/device run. Known v293 failure, Android release dependency blockage, PostgreSQL/device gaps, partial recovery cases and Q1-Q9 remain exactly as documented. Resolve the exact commit from the annotated tag rather than embedding its own hash in this file.

Git attributes preserve byte-hashed official contract assets/PDF without line-ending conversion. Only the WSDL/XSD's intentional extracted source whitespace is exempted from end-of-line/EOF whitespace checks; application code retains normal checks. This prevents hash drift across checkout platforms without editing the official schema or source extraction.
