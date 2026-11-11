# Safe development and tests

The existing PMS and operational database are preserved. Do not start the app,
run setup scripts, copy a live database into tests, or use production credentials
to prepare a test environment. Flutter is outside this phase.

## Commands (from the repository root)

Python 3.14 is the inspected interpreter. No packages were installed in this phase.
The safety-guard tests need only Python's standard library:

```powershell
python -B -m unittest discover -s tests -p test_isolation.py -v
```

For API tests, use a dedicated virtual environment containing the development
dependencies. `requirements-dev.txt` records an exact top-level baseline; runtime
versions reflect the existing interpreter. Pytest/httpx are required because the
tests use pytest fixtures and FastAPI TestClient. Their proposed versions have not
yet been installed or validated together. Transitive dependencies are not locked;
a fully resolved lock requires a separate dependency-installation/validation step.

When dependency installation is authorized, prepare the environment with:

```powershell
python -m venv .venv
.\.venv\Scripts\python -m pip install -r requirements-dev.txt
```

First run the guards and the previously unsafe database tests:

```powershell
.\.venv\Scripts\python -B -m pytest -q tests/test_isolation.py tests/test_v2.py tests/test_guest_checkin.py
```

After that passes, the normal suite command is:

```powershell
.\.venv\Scripts\python -B -m pytest -q
```

Do not use full unittest discovery: legacy tests require the pytest safety hooks.
Do not import application modules in external pytest plugins, disable the root
conftest, pass `--noconftest`, or supply `--basetemp`. Run sequentially; parallel
pytest execution is not validated. JavaScript-only tests require an existing Node
installation; the localization test skips when Node is unavailable. Do not run
the synthetic benchmark generator as part of the normal suite: it writes fixtures
and invokes an external OCR executable.

Implementation validation: eight standard-library guard tests passed, and the
real application initialized its schema successfully inside the guarded temporary
tree. The API suite was not run because pytest and httpx are absent. No production
migration or external connection was performed. Normal API development remains
conditional on preparing the development environment and passing the targeted
pytest command above.

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
- Copies involving outside files are blocked, preventing adoption of live data.
- Application database connections reject PostgreSQL. Socket connections and
  urllib requests, DNS resolution, and UDP sends are blocked; external adapters
  must use test doubles.
- All schema initialization and demo seeding happen only in disposable data.
- Process environment and guards are restored at session end; owned temporary
  data is removed. No operational database is opened by the harness.

These are accidental-access guards for this suite, not an OS security sandbox.
New subprocesses do not inherit Python patches; review subprocess-based tests
before running them. Tests must not bypass guards, use alternate database drivers,
or access operational files through raw file APIs. Background-worker behavior and
real PostgreSQL/provider integration are separate test concerns.

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
