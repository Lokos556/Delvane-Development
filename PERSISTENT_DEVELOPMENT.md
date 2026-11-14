# Persistent local PMS acceptance testing

Use fictional data only. This mode requires no cloud hosting and uses the existing
FastAPI app, authentication, CSRF, Flutter clients and SQLite infrastructure.

## Why reservations disappeared

`run_development_workspace.py` deliberately opens `IsolatedEnvironment` before
importing `app.py`. `testing_safety.py::allocate_root()` creates a fresh
`tempfile.TemporaryDirectory(prefix="delvane-tests-")`; `protect_app()` points
`DB_PATH` to `collection.db` in that directory. `prepare_workspace()` initializes
synthetic fixtures/accounts and generates a new workspace ID. Leaving the context
on shutdown closes connections and removes that temporary directory. Starting
again creates another directory/database/workspace ID. A force-killed process
may leave an old temporary directory behind, but the next start still chooses a
new directory; it does not reopen the former one.

This is intentional disposable storage, not a missing reservation commit.
`app.py::reservation_create()` inserts inside `with db()`, and `db()` calls
`con.commit()` on successful exit. The automated API/process restart proof confirms
that the same reservation contract persists when its database is retained.

Both clients use `http://127.0.0.1:8765`: Windows connects directly, while
`connect_android.ps1` maps Android's device port to that same Windows port with
`adb reverse tcp:8765 tcp:8765`. Closing an app or its Android helper terminal does
not reset the database; stopping the disposable backend ends its temporary store.

The old disposable launcher remains available with the same reset/isolation
behavior. This change does not recover data already removed by its normal cleanup.

## Start persistent development

Stop the currently running backend with **Ctrl+C** in its terminal first. Keep
only one backend on port 8765. In a Windows PowerShell terminal:

```powershell
Set-Location C:\Delvane\Delvane-Development
.\.venv\Scripts\python -B run_persistent_development_workspace.py
```

On first startup, choose and confirm a fictional-account password of at least
12 characters. The existing synthetic bootstrap runs once, including sample
properties and these accounts:

- `owner@workspace.invalid`
- `manager@workspace.invalid`
- `cleaner@workspace.invalid`
- `maintenance@workspace.invalid`

On later starts, the same command opens the same development database. There is
no password/setup prompt, account replacement, fixture reseeding or automatic
reset. Existing edits, suspensions and deletions stay in effect. Normal backend
schema migrations and ordinary reservation-derived task refreshes still apply.
Credentials changed through the PMS remain changed.

Keep the backend terminal open while testing. Stop it with **Ctrl+C**, then run
the same command whenever you want to resume. The workspace ID, encryption key,
server-side sessions and existing records survive; ordinary session expiry,
logout and revocation still apply.

## Open Windows and connect the Xiaomi 15

The current local Windows build requires no configuration change or rebuild:

```powershell
Set-Location C:\Delvane\Delvane-Development
& .\apps\delvane_business\build\windows-vs2026\x64\runner\Release\delvane_business.exe
```

Connect the unlocked Xiaomi by USB and authorize debugging. In another terminal:

```powershell
Set-Location C:\Delvane\Delvane-Development
powershell -NoProfile -ExecutionPolicy Bypass -File .\apps\delvane_business\tool\connect_android.ps1 -Install
```

If the current APK is already installed, reapply USB forwarding without reinstalling:

```powershell
Set-Location C:\Delvane\Delvane-Development
powershell -NoProfile -ExecutionPolicy Bypass -File .\apps\delvane_business\tool\connect_android.ps1
```

For several authorized devices, add `-DeviceId SERIAL`. Reapply forwarding after
USB reconnects. The helper accepts both guarded workspace modes, reports the
mode, and does not uninstall the app or clear its data. Sign in with the chosen
development password. Use **Reconnect** if the client opened before the server.
Staging/production app builds intentionally do not connect to this local backend;
use the existing local build.

## Storage and isolation

The persistent store has one fixed location; no database URL or custom data path
is accepted by this launcher:

```text
C:\Delvane\Delvane-Development\.development\persistent\workspace.db
C:\Delvane\Delvane-Development\.development\persistent\workspace.json
```

`workspace.json` contains the development ownership/workspace identity and
encryption key. Keep it with the database; do not publish it. The entire
`.development/` directory, including lock files, SQLite sidecars and reset
archives, is excluded from Git. The manual store is created only when you start
the new launcher; the automated checks use separate OS-temporary stores.

The launcher reuses the existing network/file/subprocess isolation guards. It
strips inherited `ROSA_*`/OpenAI settings, ignores local dotenv files and sibling
database discovery, forces the owned SQLite file, disables demo reset after
bootstrap, and blocks outbound sockets/DNS/provider calls and child processes.
It binds only Windows loopback. Its startup ownership checks reject unexpected
files, redirected/hard-linked storage, missing databases, and databases whose
development identity does not match the marker. A process lock prevents a second
persistent instance or reset from using the store while it is running. A busy
port is refused before store initialization. Production/staging configuration,
credentials and infrastructure are unchanged.

Use only synthetic identities. This remains local acceptance storage, not a
production deployment, backup service or government-certified system. Windows
file permissions are inherited from the repository's directory; protect access
to your local account and development files.

## Switch between environments

| Mode | Backend command | Restart behavior |
|---|---|---|
| Persistent local acceptance | `.\.venv\Scripts\python -B run_persistent_development_workspace.py` | Retains fictional data and workspace identity |
| Disposable local acceptance | `.\.venv\Scripts\python -B run_development_workspace.py` | New temporary data, password setup and workspace identity |

Stop the active backend with Ctrl+C before starting the other command. Then use
Reconnect/sign in and reapply the Android USB helper if needed. The changed
workspace ID prevents the app restoring credentials into the wrong local store.
Switching modes does not delete the persistent store. Neither command switches
to staging/production; no app API origin, firewall or Wi-Fi configuration changes
are needed. Do not substitute `uvicorn app:app` or operational launch scripts.

## Deliberate reset

Stop the persistent backend, then run:

```powershell
Set-Location C:\Delvane\Delvane-Development
.\.venv\Scripts\python -B run_persistent_development_workspace.py --reset
```

Type exactly:

```text
RESET PERSISTENT DEVELOPMENT DATA
```

The command refuses to run against an active store or unrecognized directory.
It moves only the owned persistent development directory to
`.development\persistent-archive-<random-id>`. It does not recursively delete data,
touch operational/staging stores, or remove archives automatically. Start the
persistent launcher again to create a fresh workspace, encryption key and initial
password. Old sessions/guest links cannot authenticate against that fresh store.
Archives contain the former test database and its matching key; keep both together
if preserving a development snapshot.

If a startup was interrupted during first initialization, or the marker/database
is missing or mismatched, the launcher fails closed rather than silently
overwriting data. Keep a copy for diagnosis and use the explicit reset mechanism
when appropriate. Do not copy an operational database into this folder.

## Verification

Real process restart proof (separate from pytest):

```powershell
Set-Location C:\Delvane\Delvane-Development
.\.venv\Scripts\python -B verify_development_persistence.py
```

This creates a newly owned OS-temporary proof directory and uses an ephemeral
loopback port. It starts a guarded backend process, creates fictional reservation,
guest/identity, staff and assignment data through HTTP, stops it gracefully,
starts another process with the same temporary persistent store and checks the
records, encryption, workspace ID and session. It also verifies missing-CSRF
rejection and two disposable processes' reset/cleanup behavior. Both child modes
receive poisoned fictional external configuration to prove it cannot select an
external database. The proof never opens the manual persistent store, production
or staging databases; it removes only its own temporary test directory afterward.

Focused backend checks:

```powershell
.\.venv\Scripts\python -B -m pytest -q -p no:cacheprovider tests/test_persistent_development.py tests/test_isolation.py tests/test_flutter_workspace.py
```

Results from 14 November 2026:

- Real independent-process persistent/disposable proof: **passed**.
- Initial focused backend run: **29 passed**; final broader backend regression
  run: **127 passed**, including 8 new persistent-development tests. Existing
  isolation, environment, PMS, guest, staff, AI and distribution tests were retained.
- Flutter analysis: **clean**; complete Flutter suite: **229 passed**.
- Android helper PowerShell syntax and `git diff --check`: **passed**.
- Existing Starlette/AnyIO deprecation warnings remain. No test failure was
  observed in the completed checks. No physical Xiaomi/Windows interactive test,
  APK installation, new app build, staging/provider request or cloud deployment
  is claimed. The Flutter UI and PMS business logic were not changed.

Regression logs are under the app's ignored `build/`: `persistence-backend-tests.txt`,
`persistence-analysis.txt` and `persistence-flutter-tests.txt`. Process-proof PASS
messages were observed directly; the command is reproducible above. No automatic
backup schedule is supplied; reset archives are retained locally. Keeping the
SQLite file and its matching `workspace.json` together preserves encrypted test
data. Ordinary startup never recreates a missing/suspended owner; use an existing
authorized account or the deliberate offline reset for a new fictional workspace.

Implementation changes: new `persistent_development.py` and
`run_persistent_development_workspace.py`; small storage-policy hooks in
`testing_safety.py` with unchanged disposable defaults; shared bootstrap marker
and loopback server helper in `run_development_workspace.py`; new
`verify_development_persistence.py` and `tests/test_persistent_development.py`;
Android helper console wording; Git exclusion and setup documentation. No commit
or push was performed.
