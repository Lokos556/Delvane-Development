# Milestone 1 implementation report

Implemented 2026-11-11 in the existing repository. This delivers authenticated,
read-oriented operational workflows against a guarded, disposable instance of the
existing FastAPI backend. It does not authorize operational-data or provider access.
The starting Git working tree was clean. No commit or publication was performed.

## Launch

Detailed setup, role accounts, build notes and security boundaries are in
[README.md](README.md). The release bundle has already been built on this machine.

Terminal 1:

```powershell
Set-Location C:\Delvane\Delvane-Development
.\.venv\Scripts\python -B run_development_workspace.py
```

Choose a disposable password of at least 12 characters at the hidden prompt.
Terminal 2:

```powershell
Set-Location C:\Delvane\Delvane-Development\apps\delvane_business
.\build\windows-vs2026\x64\runner\Release\delvane_business.exe
```

Use `owner@workspace.invalid`, `manager@workspace.invalid`,
`cleaner@workspace.invalid` or `maintenance@workspace.invalid`, with the password
chosen in Terminal 1. Keep that terminal running. Restarting it replaces all
synthetic data and invalidates saved native sessions. No password is printed,
passed on a command line or saved by Flutter.

## Delivered workflows

- Backend login, secure cookie persistence, server-validated session restoration,
  current identity/permissions, CSRF logout, local expiry and 401 invalidation.
- Separate owner/manager, cleaner and maintenance navigation and operational
  homes. Account, organization, role and permission changes invalidate old routes.
- Owner/manager Today: arrivals, departures, today's cleaning turnovers, active
  maintenance cases, near-term registration risks, property readiness/reasons and
  priorities derived from those records. The server supplies the operational date.
- Cleaner: assigned schedule, preparation and read-only checklist context;
  maintenance: permitted assigned/unassigned case context. Workers never request
  owner dashboard, reservation detail, registration vault or general property APIs.
- Real property selection/filtering by ID, read-only reservation search,
  property/reservation/cleaning/maintenance record routes and contextual links.
- Dense responsive sidebar/rail/bottom navigation, loading, empty, permission,
  disconnected/error and retry states. Failed refresh removes the old snapshot.
- Explicit offline-demo entry/exit. Existing synthetic screens remain solely in
  demo mode; they never serve as an API-error fallback.

## Backend changes and endpoints

No authentication, reservation, integration, government or AI business logic was
rewritten. Cookie names, password hashing, seven-day session policy, server role
rules and existing browser endpoints are preserved.

1. Added `GET /api/operations/properties`, following `require_user`, explicit
   supported-role checks and organization-scoped parameterized SQL. Returns only
   ID, name and check-in/out times. Worker rows correspond to assigned work or
   already-authorized maintenance cases. It does not broaden `/api/properties`.
2. Added stable `property_id` fields to the five `/api/operations/today-command`
   queues and cleaning scheduling/assignment/reference/note fields. Existing
   fields, selection predicates and business transitions remain unchanged.
3. The development launcher alone registers `GET /api/development/workspace`.
   Ordinary application startup has no such endpoint. Flutter checks this marker
   before sending/restoring credentials; sessions bind to that workspace instance.

Existing endpoints consumed: `/api/login`, `/api/me`, `/api/logout`,
`/api/operations/today-command`, `/api/owner/dashboard`, `/api/worker/dashboard`,
`/api/properties`, `/api/properties/{id}/overview`, `/api/maintenance`,
`/api/reservations`, `/api/reservations/{id}/detail`, and the owner/manager checklist
read at `/api/work-tasks/{id}/checklist`. Worker checklist reads instead use a fresh
assigned-worker dashboard, avoiding the older broad checklist endpoint.

## Validation

| Check | Executed | Passed | Failed | Skipped |
|---|---:|---:|---:|---:|
| Complete Flutter test suite | 52 | 52 | 0 | 0 |
| Relevant isolated Python regression selection | 35 | 34 | 1 | 0 |
| Unique tests in those final runs | 87 | 86 | 1 | 0 |

The 33 added Flutter tests and 9 added backend tests pass. Earlier targeted runs
were repeated during fixes and are not counted twice. Existing demo assertions
were retained, with their app construction changed to explicit `demoMode: true`.

Commands:

```powershell
# In apps/delvane_business
flutter --no-version-check analyze
flutter --no-version-check test
powershell -NoProfile -ExecutionPolicy Bypass -File .\tool\build_windows.ps1

# In repository root
.\.venv\Scripts\python -B -m pytest -q tests/test_isolation.py tests/test_flutter_workspace.py tests/test_v22.py tests/test_v25.py
```

`flutter analyze`: no issues. Windows x64 Release: successful through the existing
VS 2026 compatibility fallback, including `flutter_secure_storage_windows_plugin.dll`.
Direct Flutter build still selects the unavailable VS 2019 generator on this
toolchain; the documented app-local fallback succeeds without changing the SDK or
machine policy. Full suite was run after the functional fixes; the final code was
rebuilt successfully. `git diff --check` reported no whitespace errors.

The Python failure is unchanged:
`tests/test_v25.py::test_schema_migration_and_runtime_health` expects runtime version
`2.10.27`; current source reports `2.10.55`. This is the known metadata ambiguity in
TEST_VALIDATION.md. The assertion and runtime/schema metadata were left untouched.
The other historical metadata failures were not part of this relevant selection;
this report does not claim the full backend suite is green. Starlette/httpx and
AnyIO emit existing deprecation warnings; dependencies were not upgraded to hide them.

Coverage includes login/cookie validation, origin/workspace binding, CSRF logout,
restoration, expired/revoked sessions, unsupported roles, permission-denied access,
secure-store failure, unconfirmed offline logout, role changes, stable-ID mapping,
exact integer amounts, reassigned-worker denial, queue loading/error/empty/retry,
record links/Back, property scope, explicit demo separation, and all four roles
at five live viewports. Existing demo coverage remains at seven viewports.

Backend validation runs under root conftest's existing temporary-data guards.
New tests verify minimal property fields, tenant/worker filters, browser-compatible
cookie/CSRF behavior, the disposable launcher and a real Uvicorn startup/shutdown
on an ephemeral loopback listener without outbound client connections. Flutter
tests use injected transports/stores, not a real server or native secret store.
No operational database, migration against operational data or real provider was used.

## Security considerations and remaining limitations

- Platform-secure storage contains only the cookie, bounded expiry and
  origin/workspace binding. Passwords, guest data and CSRF tokens are not persisted.
  The pinned secure-storage plugin and its generated registrations are included.
  Secret-store failures fail closed; no plaintext fallback exists. HTTPS is
  required off loopback; redirects, credential-bearing URLs and proxy routing are
  rejected/disabled. Errors do not show private response bodies.
- The launcher reuses existing guards before importing application code. Local
  `.env` loading, sibling adoption, non-temporary SQLite, outbound network and
  subprocesses are blocked. Its isolated marker is an accidental-environment gate,
  not a substitute for those guards. Guards protect the reviewed app paths and
  are not an OS sandbox against deliberately malicious/native bypasses.
- Connected data is synthetic development data persisted by the real backend in
  temporary SQLite, distinct from bundled demo fixtures. There is deliberately
  no production/staging bypass or operational database selector in this milestone.
- API GETs can update session timestamps, derive cleaning or initialize checklists
  inside temporary data. Native business controls are read-only. Booking edits,
  calendar, task mutations, reception, identity approval, team, AI and provider
  writes remain in the web PMS for later milestones.
- Registration queues mirror current near-term backend rules; readiness mirrors
  its heuristic. Neither proves identity authenticity, government acceptance,
  collected payments or channel delivery. Existing worker-web maintenance routing
  and wider authorization debt remain separate backend/reference work.
- Server expiry/revocation is authoritative. Existing idle-timeout enforcement
  and login-rate-limit debt were not changed. Offline logout reports when server
  revocation cannot be confirmed. Store-deletion failure is shown explicitly.
- Refresh is manual/on resume, not push or continuous streaming. Filters/drafts
  are not durable across restart, and no offline mutation/cache is added.
- Windows compilation and deterministic workflows are verified. Interactive
  native secure-storage acceptance, Windows UI sign-in smoke testing and mobile/
  Apple device builds are not claimed. Android local HTTP policy/ADB and Apple
  signing/capabilities require device validation before rollout.

## Exact changed-file inventory

All paths below are relative to the repository root (29 files including this report).

| File | Change |
|---|---|
| `DEVELOPMENT.md` | Link the guarded integrated-development entry point |
| `app.py` | Minimal scoped property endpoint and additive Today fields |
| `run_development_workspace.py` | Guarded disposable loopback server and synthetic accounts |
| `tests/test_flutter_workspace.py` | Backend role/auth/context/launcher/server contract tests |
| `apps/delvane_business/README.md` | Current launch, architecture, security, API and validation instructions |
| `apps/delvane_business/MILESTONE_1.md` | This implementation report |
| `apps/delvane_business/pubspec.yaml` | Add pinned platform-secure session storage |
| `apps/delvane_business/pubspec.lock` | Resolve and lock that package and dependencies |
| `apps/delvane_business/lib/app/app.dart` | Authentication gate, explicit demo and protected route scope |
| `apps/delvane_business/lib/core/network/api_client.dart` | Cookie response metadata, methods, safe native transport and 401 hook |
| `apps/delvane_business/lib/core/auth/auth_controller.dart` | Existing-cookie session lifecycle and server identity |
| `apps/delvane_business/lib/core/auth/session_store.dart` | Platform-secure storage abstraction |
| `apps/delvane_business/lib/features/workspace/login_page.dart` | Responsive login/reconnect and demo entry |
| `apps/delvane_business/lib/features/workspace/workspace_models.dart` | Typed operational records and safe shape checks |
| `apps/delvane_business/lib/features/workspace/workspace_repository.dart` | Existing API mapping and authorized record reads |
| `apps/delvane_business/lib/features/workspace/workspace_controller.dart` | Remote loading, filters and role navigation |
| `apps/delvane_business/lib/features/workspace/workspace_page.dart` | Dense responsive Today/work/properties/stays/account |
| `apps/delvane_business/lib/features/workspace/record_page.dart` | Record routes, contextual links, read-only detail and retry |
| `apps/delvane_business/test/auth_test.dart` | Authentication/session/storage failure tests |
| `apps/delvane_business/test/workspace_test.dart` | Role, mapping, data-state, responsive and navigation tests |
| `apps/delvane_business/test/support/fake_pms.dart` | Synthetic transport and in-memory store fixtures |
| `apps/delvane_business/test/app_test.dart` | Explicit demo construction; retain assertions |
| `apps/delvane_business/test/preview_test.dart` | Explicit demo raster generation |
| `apps/delvane_business/android/app/src/main/AndroidManifest.xml` | Internet permission and disable credential backup |
| `apps/delvane_business/macos/Runner/DebugProfile.entitlements` | Client networking and Keychain capability |
| `apps/delvane_business/macos/Runner/Release.entitlements` | Client networking and Keychain capability |
| `apps/delvane_business/macos/Flutter/GeneratedPluginRegistrant.swift` | Generated secure-storage/path-provider registration |
| `apps/delvane_business/windows/flutter/generated_plugin_registrant.cc` | Generated secure-storage registration |
| `apps/delvane_business/windows/flutter/generated_plugins.cmake` | Generated secure-storage build linkage |

Build outputs, dependency caches and raster previews remain ignored. No backend
files were moved; operational paths, browser assets and production integrations
were not edited. FEATURE_PARITY.md/FLUTTER_ROADMAP.md remain the dated audit baseline.
