# Web-fidelity port in progress

For USB-connected Android debug testing of this same application, use
[ANDROID_TESTING.md](ANDROID_TESTING.md). It includes the isolated Windows backend,
`adb reverse`, debug APK installation and Xiaomi acceptance checklist.

The authenticated default now uses the source-shaped PMS shell. See [PORT_STATUS.md](PORT_STATUS.md) for implemented screens, substantial remaining gaps and visual differences. The Milestone 1 instructions below still describe the secure isolated launcher, but its UI inventory is historical. This build is not full web parity.

Reservations, Reception, property rates, worker maintenance/cleaning, stock,
team administration and Channex distribution now have real API workflows. The current
validation is 160 Flutter tests and 48 selected isolated Python tests passing
in the latest operational-desk and visual continuation; see
[PORT_STATUS.md](PORT_STATUS.md) for exact coverage, endpoints and remaining visual
and functional gaps. The Milestone 1 test counts and read-only inventory below
are historical, while its guarded launch/security instructions remain applicable.

The source-based visual pass includes 38 paired desktop/mobile page and expanded-desk captures.
See [VISUAL_REFERENCE.md](VISUAL_REFERENCE.md) for measured design values, safe
capture commands and remaining visual differences. This is not pixel-perfect parity.

# Delvane Business

Milestone 1 connects the native Flutter client to the existing FastAPI PMS using
its own session-cookie/CSRF authentication. The original backend/web PMS stays at
the repository root. The app defaults to a sign-in screen, not fixture data.

## Launch the integrated Windows workspace

Use two terminals. Do not run `uvicorn app:app`, existing production launchers, or
supply a database path for this milestone.

Terminal 1, from the repository root:

```powershell
Set-Location C:\Delvane\Delvane-Development
.\.venv\Scripts\python -B run_development_workspace.py
```

Enter a new disposable password of at least 12 characters at the hidden prompt.
The same password applies to these **synthetic accounts only**:

- `owner@workspace.invalid`
- `manager@workspace.invalid`
- `cleaner@workspace.invalid`
- `maintenance@workspace.invalid`

The launcher serves `http://127.0.0.1:8765`. It installs the existing isolation
guards **before importing app.py**, creates fresh temporary SQLite data, suppresses
local environment/credential loading and sibling database adoption, disables the
seeded demo logins, and blocks outbound sockets/DNS/urllib and child processes.
It never opens or copies an operational database. Existing schema initialization
and derived-record refreshes run only inside that temporary tree. Access logging
is disabled. Keep the terminal open; Ctrl+C stops the server and cleans up data.
A force-killed process may leave ignored OS-temporary synthetic files.

Terminal 2:

```powershell
Set-Location C:\Delvane\Delvane-Development\apps\delvane_business
flutter --no-version-check pub get
powershell -NoProfile -ExecutionPolicy Bypass -File .\tool\build_windows.ps1
.\build\windows-vs2026\x64\runner\Release\delvane_business.exe
```

Sign in using one of the accounts above and the password you chose. The existing
web client is also available at `http://127.0.0.1:8765/` against this disposable
data. Restarting the server creates a new workspace and invalidates the native
client's saved session. Press Reconnect if the app started before the server.

The build script first attempts Flutter's standard Windows release build. This
host has VS 2026 while Flutter 3.32.2 selects a VS 2019 generator; the reviewed
script handles that specific mismatch with installed VS 2026 CMake/MSBuild. The
ExecutionPolicy setting above applies to that one child process only. It does not
change system policy. On a compatible Flutter/VS pair, use `flutter run -d windows`
or launch `build/windows/x64/runner/Release/delvane_business.exe` after the standard
build. Keep all DLLs and `data/` beside the executable, including the secure-storage
plugin DLL.

The default API origin is compiled as `http://127.0.0.1:8765`. There is no arbitrary
server picker or production-mode bypass. Before sending credentials/restoring a
cookie, the app requires `/api/development/workspace` to identify the disposable
launcher instance. This endpoint exists only in the guarded launcher, not the
ordinary backend. The marker prevents accidental environment confusion; actual
data isolation is enforced by the Python guards. Do not proxy it onto another PMS.
A future approved staging/production rollout needs a separate configuration and
release review, not removal of the marker check.

## Functional scope

- Owner/manager: Today queues for arrivals, departures, cleaning turnovers,
  maintenance, near-term incomplete registration and derived operational
  priorities; real property readiness and reasons; read-only reservation search.
- Cleaner: My day with assigned upcoming cleaning, deadlines/preparation,
  read-only checklists and permitted maintenance cases. Fresh assignment is
  checked through the worker dashboard before opening a task.
- Maintenance: My cases and visible assigned/unassigned maintenance cases;
  restricted operational property context. No reservation or guest-document view.
- Stable-ID property selection filters every workspace queue and reservation list.
- Reservation, property, cleaning and maintenance records have their own routes,
  linked records, Back navigation, loading/error/retry states and explicit
  read-only status. Role/organization/permission changes discard protected routes.
- Refresh and foreground resume revalidate identity. Failed refresh clears the
  previous snapshot and shows an unavailable state; fixture data is never used.
- Desktop sidebar, tablet rail and compact phone/short-landscape bottom navigation
  use the existing white/ink/yellow theme with dense operational lists.

Registration means the backend's completeness/review state, not certified identity
or government acceptance. Property readiness is the existing backend heuristic,
not an invented occupancy or revenue metric. Cleaning schedules and checklist
initialization can be refreshed by backend GET handlers; this is why the launcher
must always use disposable data even though the client has no business-write UI.

## Authentication and security

`POST /api/login` issues the existing HttpOnly `rosa_session` cookie. The native
transport captures that cookie; it does not manufacture bearer tokens. `GET
/api/me` validates the session and supplies user, organization, permissions and the
CSRF token. `POST /api/logout` sends both cookie and `X-Rosa-CSRF` to revoke the
server session. A 401 clears local credentials and protected routes. A 403 remains
an access/security error, not a reason to grant access or fabricate data.

Only the cookie, expiry and origin/workspace binding are persisted using
[flutter_secure_storage 9.2.4](https://pub.dev/packages/flutter_secure_storage/versions/9.2.4).
Its Windows plugin uses encrypted storage backed by a key in Windows Credential
Manager; Android uses encrypted preferences/KeyStore; Apple uses Keychain. The
package and resolved dependencies are locked for this Flutter/Dart toolchain.
No passwords, guest records or CSRF tokens are persisted. Storage failure fails
closed; there is no plaintext fallback. Native secret-store behavior still needs
interactive device acceptance testing beyond compilation and fake-store tests.

Cookie Max-Age is bounded to the current seven-day contract. Local expiry also
clears the UI; server expiry/revocation/active-account checks remain authoritative.
The backend's declared idle timeout is not enforced by its current implementation;
this milestone does not silently change that policy or its known login-rate-limit
debt. Offline logout clears local state and reports when server revocation could
not be confirmed; the server session can remain until expiry/revocation. Secure
store deletion failure is reported rather than claimed successful.

HTTPS is required for non-loopback origins. HTTP is permitted only for explicit
loopback development. Redirects are disabled, proxy routing is disabled, responses
are size/time bounded and errors never display raw server bodies. Credentials
stay on one fixed origin. Provider credentials and guest identity vault endpoints
are never requested. Android backup is disabled; macOS client networking and
Keychain capabilities are configured. No global TLS or certificate bypass exists.

## Demo separation

Explore offline demo is an explicit sign-in-screen action and has an Exit demo
control. It retains the seven original synthetic preview screens and labels.
It has no session, remote repository, fallback path or provider calls. Demo task
checkboxes, drafts, scripted AI and settings stay in memory and do not affect the
connected workspace. Authenticated mode never embeds these demo screens.

## Backend API contract

Existing endpoints used:

- `POST /api/login`, `GET /api/me`, `POST /api/logout`.
- Owner/manager: `GET /api/operations/today-command`, `/api/owner/dashboard`,
  `/api/properties`, `/api/reservations`, `/api/reservations/{id}/detail`,
  `/api/properties/{id}/overview` and `/api/work-tasks/{id}/checklist`.
- Workers: `GET /api/worker/dashboard`; checklist/preparation comes from the
  assigned-task payload, avoiding the older broad checklist-read permission.
- All supported roles: `GET /api/maintenance`.

Minimal backend additions:

- `GET /api/operations/properties`: organization-scoped ID/name/check-in/checkout
  only. Cleaner context is restricted to assigned work or already-visible cases;
  maintenance context to assigned/unassigned visible cases. Existing `/properties`
  authorization remains unchanged. No guest/address/financial fields are returned.
- Additive `property_id` fields on every Today queue and cleaning scheduling/context
  fields so Flutter never joins records by display name. Existing fields and query
  semantics remain intact; browser handlers continue to use their old fields.
- `/api/development/workspace` is registered only by the isolated launcher.

## Tests and builds

From this Flutter directory:

```powershell
flutter --no-version-check analyze
flutter --no-version-check test
powershell -NoProfile -ExecutionPolicy Bypass -File .\tool\build_windows.ps1
```

Flutter tests use injected transports and in-memory secret stores, never a real
server, operational database or external API. Existing demo tests explicitly opt
into demo mode. Backend commands run from the repository root through conftest:

```powershell
.\.venv\Scripts\python -B -m pytest -q tests/test_isolation.py tests/test_flutter_workspace.py tests/test_v22.py tests/test_v25.py
```

This selection currently yields 34 passes and one pre-existing version/schema
metadata failure, recorded in TEST_VALIDATION.md and unchanged by these additive
API changes. No failure is skipped or assertion weakened. See MILESTONE_1.md for
exact validation results and changed files.

## Remaining work and structure

This is a functional authenticated read-oriented milestone, not complete PMS
parity. Booking mutation/calendar, reception/messaging, task start/finish/edit,
identity approval, team administration, AI execution and provider/reporting writes
remain in the web PMS. No offline writes, persistent guest cache, background push
or external delivery is introduced. Worker readiness is intentionally restricted.
The existing reference worker Maintenance-page dependency issue is not rewritten.

Windows is the verified build target here. Android/iOS/macOS runners are retained;
Apple requires a Mac/signing and all mobile/native secret-store behavior needs
device testing. Android loopback debug access also requires an explicit local
network policy/ADB setup; do not disable TLS globally to work around it.

New code lives in `lib/core/auth/` and `lib/features/workspace/`, with the shared
HTTP transport in `lib/core/network/`. The original `BusinessController` and mock
repository serve only demo mode. `WorkspaceRepository` maps allowlisted fields,
`WorkspaceController` owns loading/property/navigation state, and the authenticated
nested Navigator owns record routes. FastAPI owns all authorization and business
state. The audit documents FEATURE_PARITY.md and FLUTTER_ROADMAP.md describe the
pre-milestone baseline and longer migration plan; they are not current pass counts.
