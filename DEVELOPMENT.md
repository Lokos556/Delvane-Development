# Safe development and tests

The existing PMS and operational database are preserved. Do not start the app with
ordinary launchers, run setup scripts, copy a live database into tests, or use
production credentials to prepare a test environment. Integrated Flutter development
uses the guarded `run_development_workspace.py` for disposable data, or
`run_persistent_development_workspace.py` to retain fictional acceptance data across
restarts. Both install isolation before importing the app and serve only loopback.
See [persistent local setup/reset](PERSISTENT_DEVELOPMENT.md) and
[Delvane Business setup](apps/delvane_business/README.md) for the two-terminal launch.

## Commands (from the repository root)

The project-local `.venv` uses Python 3.14. Development dependencies have been
installed and validated with `pip check`.
The safety-guard tests need only Python's standard library:

```powershell
python -B -m unittest discover -s tests -p test_isolation.py -v
```

For API tests, use a dedicated virtual environment containing the development
dependencies. `requirements-dev.txt` records the top-level baseline;
`requirements-dev.lock.txt` pins the complete resolved Windows/Python 3.14 test
environment. Pytest/httpx are required for pytest fixtures and FastAPI TestClient.
The current Starlette/httpx combination works but emits deprecation warnings;
switching clients is separate work, not needed to execute these tests.

When dependency installation is authorized, prepare the environment with:

```powershell
python -m venv .venv
.\.venv\Scripts\python -m pip --isolated install --index-url https://pypi.org/simple -r requirements-dev.lock.txt
```

First run the guards and the previously unsafe database tests:

```powershell
.\.venv\Scripts\python -B -m pytest -q tests/test_isolation.py tests/test_v2.py tests/test_guest_checkin.py
```

After that passes, the normal suite command is:

```powershell
.\.venv\Scripts\python -B -m pytest -q
```

Pytest configuration disables external plugin autoloading. Do not use full
unittest discovery: legacy tests require the pytest safety hooks.
Do not import application modules in external pytest plugins, disable the root
conftest, pass `--noconftest`, or supply `--basetemp`. Run sequentially; parallel
pytest execution is not validated. The Python localization wrapper is explicitly
skipped because its Node child process would not inherit Python guards. Do not run
the synthetic benchmark generator as part of the normal suite: it writes fixtures
and invokes an external OCR executable.

The same localization check and eight scanner/MRZ JavaScript files can now be run
through the separate guarded source-snapshot runner (an existing Node 20+ is
required, with no download or install):

```powershell
.\.venv\Scripts\python -B run_js_tests.py --node '<absolute path to node.exe>'
```

The runner copies only explicitly reviewed JavaScript source into a temporary
directory. Node permissions grant read access only to that snapshot, no writes,
child processes, workers, or native addons. A preload blocks network/DNS access
and verifies permission denials before any test runs. Environment variables are
replaced, including home/config paths. Do not launch Node directly against this
repository as a substitute for this command.

`testing_clock.py` fixes the test calendar at 2026-11-01 12:00:00 so November 2026
certification migration fixtures stay future-dated on any host. Pytest replaces
date/datetime references only in app/test modules; production date validation is
unchanged. Each test resets a deterministic microsecond counter so separate
high-resolution events remain ordered instead of sharing a timestamp. Import
date/time at module scope in new tests (or use `app.date` and
`app.datetime`) so it uses this clock. The JS runner fixes Date in the host and
test VM contexts to the same UTC instant. Tests of real elapsed time and other
calendar scenarios require explicit fixtures; this is not a production clock.

Initial validation on 2026-11-11: 196 unique tests selected in five stages; 182 passed,
13 failed, and one was skipped (195 actually executed). All 12 guard tests and
18 authentication/authorization-stage tests passed. See `TEST_VALIDATION.md` for
the stage results and failure classifications. No production migration or real
external API connection was performed. This is a usable isolated development
environment with a known failing baseline, not a fully passing release gate.
The follow-up in `TEST_VALIDATION.md` records the Decimal fix, evidence-based
assertion updates, new precision/date coverage, JavaScript results, and unresolved
runtime metadata ambiguity. Do not reinterpret those metadata failures as passing
tests or suppress them with skips/xfails.
Final follow-up counts: Python 204 collected / 203 executed, 199 passed, 4 failed,
1 skipped; guarded JavaScript 9 files executed, all passed. The original 13 failing
tests now yield 9 passes and the four unchanged metadata failures. This remains a
known failing regression baseline until the metadata contract is resolved.

## Isolation guarantees and boundaries

Root `conftest.py` installs `testing_safety.py` before collecting tests. It rejects
an already imported application and user-selected pytest base directories.

- Application environment settings are replaced for the test process; inherited
  Rosa/OpenAI credentials are removed. Local `.env` files are not loaded.
- Sibling-release configuration/database discovery is disabled.
- Every test gets a fresh temporary database path. Existing tests can still
  redirect to their own pytest `tmp_path` inside the allocated temporary tree.
- SQLite connections and application database initialization/reset are rejected
  outside that tree. The reset guard runs before any database deletion.
- SQLite's dbapi2 alias, SQL ATTACH, raw database/environment file opens, and
  database removals are also guarded. Tracked SQLite connections are closed on
  teardown, including raw connections left open by existing tests on Windows.
- Copies involving outside files are blocked, preventing adoption of live data.
- Application database connections reject PostgreSQL. Socket connections and
  urllib requests, DNS resolution, and UDP sends are blocked; external adapters
  must use test doubles.
- On Windows, only the standard-library socketpair operation may establish its
  internal loopback pair for asyncio wake-ups. Ordinary loopback connections to
  local services remain blocked. JUnit uses a synthetic hostname to avoid Windows
  platform detection spawning a process.
- All schema initialization and demo seeding happen only in disposable data.
- Process environment and guards are restored at session end; owned temporary
  data is removed. No operational database is opened by the harness.

These are accidental-access guards for this suite, not an OS security sandbox.
Subprocess creation is blocked because children do not inherit Python patches.
Tests must not bypass guards, use alternate database drivers, retain unpatched
function references, rename operational files, or access data under unrecognized
filenames. These remain reasons to review new tests before execution.
Background-worker behavior and real PostgreSQL/provider integration are separate
test concerns. Never treat this harness as permission to run unreviewed code with
operational-data access.

## Initial test-infrastructure audit

- `tests/test_v2.py`: three tests called `init_db(reset=True)` against the configured
  database without redirecting it. Shared isolation now supplies temporary paths.
- `tests/test_guest_checkin.py`: TestClient lifespan initialized the configured
  database and its helper executed DELETE/INSERT statements there. It now uses
  per-test temporary data through the same shared isolation.
- Most other backend modules monkeypatch `DB_PATH`, but previously inherited the
  backend selection, local secrets, legacy-database discovery, and network access.
  Shared guards now cover these as well, including collection-time imports.
- `tests/test_v29.py` deliberately tests copying a legacy database. Synthetic
  source/destination paths remain permitted inside temporary storage.
- Some tests contain stale version assumptions or source-string assertions; their
  correctness has not been established merely by adding isolation.

## Git and Docker hygiene

The initial Git working tree was clean. Tracked filenames and common credential
signatures were checked without printing secret values. No tracked local database,
private environment file, certificate/private-key file, or matching credential
signature was found. `.env.example` is tracked; its credential/key fields are empty.
This is not an exhaustive secret scan or historical Git audit.

`.gitignore` now excludes database sidecars, secret environment files, environments,
caches, logs, credentials, and certificates. It preserves `.env.example`.
`.dockerignore` allows only current runtime inputs and denies sensitive file types
within static assets too. No Docker build was run. Add future runtime files to the
allowlist deliberately.

If a sensitive file is discovered in Git, stop and report its path without its
contents. With approval, remove it from the index while preserving the local file
(`git rm --cached -- <path>`), and rotate any exposed credential. Ignoring a file
does not remove tracked copies or historical copies. History rewriting and removal
of operational files require separate approval.
