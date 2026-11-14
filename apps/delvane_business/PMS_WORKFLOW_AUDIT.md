# PMS workflow audit — 14 November 2026

Repository: `C:\Delvane\Delvane-Development`, Flutter app `apps/delvane_business`, existing FastAPI backend. Branch: `main`, tracking `origin/main`. Existing uncommitted environment, localization, IDE and generated-platform changes were present and preserved. No commit, push, deployment, operational database access or production provider call was performed.

## Scope and evidence

Reviewed `PORT_STATUS.md`, the 125-row `FEATURE_PARITY.md`, authenticated app composition, PMS workflow adapters, reservation/identity API handlers, isolation guards and related backend/native tests. Current composition defaults to authenticated PMS; explicit demo mode uses the mock repository. The old “Flutter's exact current scope” prose near the end of FEATURE_PARITY.md still describes the historical mock-only app and should not be used as current implementation evidence.

Classifications below distinguish locally implemented behavior from external delivery and unfinished native controls. They do not certify production readiness. Backend tests exercise real in-process API requests under disposable SQLite/network/file guards; Flutter tests use synthetic API doubles. A complete native GUI-to-server acceptance run and physical-device test were not performed. Existing ledger totals remain **78 implemented, 21 partial, 13 missing native, 11 backend-blocked, 2 simulated**; this safety fix does not promote unrelated feature rows.

## Workflow classification

| Area | Implemented and regression-covered | Partial, missing, simulated or backend-blocked |
|---|---|---|
| Reservations/calendar | Create/edit/cancel, inquiry confirmation, availability conflicts, room/rate reads, exact integer HUF, notes/history; calendar navigation, checkout-exclusive occupancy and overflow selection | Partial: combined search/status browsing and full cancelled-record discovery. Backend risks: booking concurrency/capacity and physical-room assignment. Channex acceptance is separate. |
| Channex/distribution | Local mappings, rate plans, range/bulk ARI contracts, outgoing queue diagnostics/retry; adapter behavior exercised with stubs and unconfigured/role failures | Partial: live import/poll/ack/ARI delivery and provider acceptance unverified, individual ack retry UI absent. Missing native: technical credentials and commercial onboarding. Simulated: sandbox feed/import tools. Backend-blocked: additional full direct OTA adapters. |
| Guest lifecycle | Browser guest link/submission, encrypted identity storage boundary, owner review, completeness/review distinction, local government queueing; links now require current confirmed booking | Missing native: public camera/OCR/check-in, sensitive vault/scanner administration and complete preference/history surfaces. Partial: manual registration status can diverge from identity review. Government queueing is not government acceptance. Arrival/departure displays do not establish a separately verified physical arrival/checkout state machine. |
| Reception | Manual intake, linked messages, analyze/draft/save/apply, mark-replied/archive, rule changes and scheduled approval | Partial/backend-blocked: real IMAP/OTA ingestion, external sending, delivery scheduler and complete threading. Simulated: scheduled simulate-send. Copying a link and marking replied do not send anything. |
| Operations | Reservation-derived cleaning, own-task start/checklist/finish, optional finish note; maintenance report/start/resolve/operator verify; inventory quantities and operational property context | Missing native: maintenance reassignment editor. Partial/backend risk: worker checklist/maintenance assignment authorization needs tightening; task scheduling/reassignment controls and property/day aggregation need review. Backend-blocked: purchasing. |
| Staff | Member creation and once-only setup password, owner role changes/reset/revocation, manager restrictions, workload and session invalidation | Missing/partial: complete welcome/recovery UX. Backend-blocked: transactional invitation email, working MFA/passkeys, payroll. Setup password is not invitation delivery. |
| Properties | Readiness/overview, room-type creation, rate-plan reads/creation, guest preferences and shared/property knowledge | Backend-blocked/missing contracts: general property CRUD, physical-room allocation, room inventory editing and rate-plan edit/delete. No unsupported editor was added. |
| AI | Persistent local conversation, supported facts, observe simulation, assist approval and narrow cleaning reassignment execution; mode/authority persistence, action history and eligible undo | Partial: complete diagnostics/evidence UI and dedicated native reassignment acceptance. External model behavior unverified. Backend-blocked: arbitrary autonomous payment/refund/maintenance/government execution; authority labels do not supply executors. |
| Billing | Stored reservation amounts and manual unpaid/partial/paid/refunded labels | Backend-blocked: invoice domain/numbering/PDF/correction/NAV, card charging/refunds, financial ledger/reconciliation. A paid label is not money movement. |

## Implemented critical batch

Closed a guest identity collection gap after reservation cancellation or demotion to inquiry:

- `app.py`: public token validation reads the current reservation status and returns HTTP 410 for a non-confirmed booking before guest data is returned or submitted. Owner/manager link generation returns HTTP 409 for non-confirmed bookings before records/tokens are created.
- `tests/test_guest_checkin_lifecycle.py`: two real API lifecycle cases create a confirmed disposable stay, issue a usable link, cancel or change the booking to inquiry, then assert that link generation, unauthenticated public reads and identity submission are rejected. They also assert no sensitive identity or scan event was persisted by the rejected submission.
- Existing confirmed-stay submission and manual identity-review tests remain passing. The UI uses its existing safe 409 handling; no new endpoint, dependency, schema, migration or toolchain change was needed.

This checks current reservation state at access time. It does not redesign token issuance, automatic revocation/history, completed-stay policy, or concurrent cancellation/submission handling.

## Validation

- Flutter **3.50.0**, Dart **3.14.0** verified; analysis clean; **221 Flutter tests passed**.
- Main isolated backend suite: **60 passed** covering isolation, workspace/auth/CSRF/roles, environment metadata, reservations, reception, guest submission/review, operations, staff and distribution contracts, including the two new lifecycle cases. Existing Starlette/AnyIO warnings and a denied optional pytest-cache write were reported; the suite exited successfully.
- Additional local AI/channel suite: **19 passed, 1 failed**. `tests/test_v281.py::test_v281_runtime_and_today_registration_is_contextual` expects runtime version `2.10.27`; the current endpoint returns `2.10.55`. This historical test failure was retained, not hidden by changing a version assertion. Its subsequent registration-context assertions were not reached. Current source also advertises a different FastAPI version; release metadata needs reconciliation.
- Android debug APK built successfully at `apps/delvane_business/build/app/outputs/flutter-apk/app-debug.apk`. The existing Kotlin migration warning remains. Used only the documented process-scoped normal-path TEMP workaround. Log: `build/pms-audit-android.txt` inside the app.
- Windows release built successfully through `tool/build_windows.ps1 -DartDefineFromFile config/local.json`, using the existing VS2026 fallback. Full bundle: `apps/delvane_business/build/windows-vs2026/x64/runner/Release/`; log: `build/pms-audit-windows.txt` inside the app. Keep adjacent DLLs and data with the executable. These build outputs include the preserved existing environment/UI changes; the new lifecycle fix runs in the backend.
- No physical Android/Windows interactive acceptance, iOS compilation, live HTTPS staging, actual OTA delivery or government submission is claimed.

## Prioritized remaining work

1. Tighten server assignment checks for cleaning checklist and maintenance mutations, with own/other/unassigned/foreign-tenant tests. Review registration completeness versus identity verification and version/schema metadata consistency. These remain release risks despite successful happy-path tests.
2. Complete reservation status browsing and maintenance reassignment using existing backend contracts; add independent API and native failure/permission tests. Verify cancel/change/import effects on cleaning, guest links and availability, including concurrency, retries and idempotency.
3. Run the full critical journey from the native Windows app and physical Android device against the guarded disposable backend: each role, booking edit/cancel/conflict, guest submission/review, reception draft/apply, cleaning finish and maintenance verify. Include session expiry, failed refresh, keyboard/back and secure-store lifecycle.
4. Prepare separately isolated Channex staging credentials/property mappings and test real create/change/cancel revisions, duplicate/retry acknowledgements, ARI acceptance and outage recovery. This requires explicit provider-test configuration; no operational credentials or property were used here.
5. Specify missing backend domains before implementation: property/room management and real billing/payment accounting. Preserve browser guest flow until native scanner/identity features have acceptance evidence.

## NTAK/VIZA prerequisites and hold point

NTAK/VIZA work was not started. Existing local queue/readiness/preview capabilities are not certified transport. This list reports repository prerequisites from `NTAK_VIZA_NEXT.md`, not a fresh verification of government interface versions or legal requirements.

Before beginning: close critical PMS authorization/identity/state risks, complete native-to-disposable-server acceptance and reconcile release metadata. Establish a stable property/reservation/guest lifecycle and prove that completeness, human identity verification and government acknowledgement remain separate.

Then obtain the official developer/test packages and approval: actual manufacturer/operator company and contact details, public test-system address/IP where required, assigned software/property identifiers, current schemas/WSDLs and message validation sequence, test endpoints and certificates/signing material, plus the VIZA storage-forwarding module. Do not invent application details or assume the WSDL version named in an older repository note remains current.

Use a separately isolated test deployment/database/storage and synthetic identity fixtures, with explicit access control, encrypted sensitive material and redacted logs. Define retries, deduplication, rejection/acknowledgement handling and audit evidence against the supplied official interfaces. Official test validation/certification remains a prerequisite for a production-ready claim.
