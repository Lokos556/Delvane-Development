# Isolated Python suite validation — 2026-11-11

## Regression follow-up: decisions and changes

Final safe Python run: **204 collected, 203 executed, 199 passed, 4 failed,
1 skipped**. JavaScript: **9 files executed, 9 passed, 0 failed, 0 skipped**.
Counts are unique tests/files, not accumulated diagnostic invocations.

| Regression run | Selected | Passed | Failed | Skipped |
|---|---:|---:|---:|---:|
| Focused fix/precision/clock/assertion checks | 19 | 19 | 0 | 0 |
| Original 13 failures (renamed tests mapped explicitly) | 13 | 9 | 4 | 0 |
| Relevant Channex/reservation regressions | 96 | 95 | 1 | 0 |
| Corrected clock/chat/429 checks | 4 | 4 | 0 | 0 |
| Complete safe Python suite, final run | 204 | 199 | 4 | 1 |
| Guarded JavaScript files | 9 | 9 | 0 | 0 |

Rows overlap and must not be summed. Reports are in ignored
`.pytest_cache/regression-{targeted,original13,channex-reservations,clock,complete}.xml`.
The complete final run supersedes the diagnostic run with a static-clock fixture.
No existing failing test was removed, xfailed, or newly skipped. The sole existing
Python skip is its direct Node wrapper; the underlying JS check passed separately.

This is a repeatable isolated functional baseline with four explicitly unresolved
metadata failures, **not a green release gate**. No operational database was
opened or modified, no production migration or real API call occurred, and no
commit, publication, or dependency installation was performed in this follow-up.

Exact repository files changed in this follow-up (earlier uncommitted isolation
work is preserved and is not counted as a new change here):

- `app.py`
- `conftest.py`
- `testing_clock.py` (new)
- `run_js_tests.py` (new)
- `tests/js_test_guard.cjs` (new)
- `tests/test_clock.py` (new)
- `tests/test_rosa.py`
- `tests/test_v21036.py`
- `tests/test_v223.py`
- `tests/test_v2912.py`
- `tests/test_v297.py`
- `tests/test_v298.py`
- `tests/test_v299.py`
- `tests/test_v3000.py`
- `tests/test_v3030.py`
- `tests/localization_coverage.js`
- `DEVELOPMENT.md`
- `TEST_VALIDATION.md`

The only production-code edit in this follow-up is the last bound parameter in
the legacy single-range Channex ARI insert. It now binds `legacy_rate` instead of
the raw Decimal. The existing `int(round(Decimal))` whole-forint conversion is
reused for both nightly and override storage. No float conversion, global SQLite
adapter, schema migration, pricing-rule change, or availability change was added.
Outbound minor units retain the existing exact Decimal conversion.

Six additional cases cover whole forints, fractions on both sides of a rounding
boundary, half-even ties, and 9007199254740993 (which cannot be represented exactly
as a binary float). They assert SQLite integer types, both stored amounts, exact
outbound minor units, and no availability request from a rate-only update.

### Disposition of each original failure

| Original test | Root cause and disposition |
|---|---|
| test_v295: test_owner_range_change_batches_and_sends_two_ari_calls | Decimal bound to INTEGER override; fixed at the database boundary. Existing batched rate/availability assertions preserved. |
| test_v295: test_ari_failure_is_durable_and_retries | Same Decimal defect; fixed without changing durable retry assertions. |
| test_v297: test_whole_forint_price_is_sent_in_channex_minor_units | Same Decimal defect; fixed; original stored whole-forint/outbound minor-unit assertions preserved. |
| test_v2991: test_existing_date_override_survives_base_rate_change | Same Decimal defect; fixed; override/base-rate assertions preserved. |
| test_v25: test_schema_migration_and_runtime_health | Unresolved runtime/schema metadata contract; test unchanged. |
| test_v28: test_v28_schema_and_runtime | Same unresolved metadata contract; test unchanged. |
| test_v281: test_v281_runtime_and_today_registration_is_contextual | Same unresolved metadata contract; test unchanged, including contextual registration assertions. |
| test_v282: test_v282_schema_runtime_and_team_overview | Same unresolved metadata contract; test unchanged, including team/role assertions. |
| test_v3000: test_viza_id_scan_completes_guest_registration_and_queues_event | Obsolete pre-verification flow. Renamed to test_viza_id_scan_requires_owner_verification_before_queueing; now asserts needs_review/pending and zero reports, then verifies identity and asserts both NTAK/VIZA registration_verified events and recorded reviewer/time. Evidence: migration 3071, scanner/verification routes, newer test_guest_checkin workflow. |
| test_v21036: test_certification_availability_delivery_returns_the_new_action_task_not_an_older_queued_job | Historical request date; replaced with relative dates from the deterministic test clock. Exact range/room/availability/task-ID and untouched-old-job assertions retained. |
| test_v299: test_manual_closure_survives_booking_cancellation | Obsolete cumulative queue count. Existing closure state assertion retained; now requires exactly one new cancellation-reconciliation job with the exact closed date/room/payload. Evidence: cancellation's documented force=True reconciliation path and newer move/cancel tests. |
| test_v223: test_v223_frontend_uses_compact_primary_nav_and_chat_send | Function renamed in Delvane UI. Now checks the actual function declaration and both click/Enter bindings; all other navigation/quick-prompt assertions retained. |
| test_v298: test_static_assets_are_cache_busted_for_v2104 | Old cache tokens. Renamed to test_static_assets_have_explicit_release_cache_versions; verifies the complete three-asset set, individual current version tokens, and actual file existence. Main assets are 2.11.26; the carried-forward v283 patch is 2.10.50. No production assets changed. |

### Why four metadata failures remain

The inspected implementation disagrees with itself:

| Source | Advertised value |
|---|---|
| Runtime endpoint and health endpoint | 2.10.55 |
| FastAPI/OpenAPI version | 2.10.59 |
| Main frontend assets / requested release | 2.11.26 |
| SCHEMA_VERSION / runtime schema field | 3070 |
| Latest applied migration during isolated initialization | 3071 |
| Old runtime tests | 2.10.27 / 3056 |

Simply asserting 2.10.55/3070 would endorse stale or conflicting metadata. There
is insufficient evidence of an intentional separate backend-version contract.
The four tests and production metadata are therefore left unchanged as requested
for ambiguous intent. A separate metadata alignment decision should
define backend/release version semantics and whether advertised schema means the
latest applied migration; then assertions can verify that contract rather than
copying current literals. The v25 expectation of `development` would also need to
be reconciled with this deliberately isolated `test` environment.

### Calendar determinism and safe JavaScript execution

`testing_clock.py` fixes the Python test calendar at 2026-11-01 and resets a
microsecond counter per test. App/test date and datetime references use that
clock. Relative future/past validation remains intact. Historical certification
migration fixtures remain fixed scenarios ahead of this test date. Local imports
in test_rosa/test_v3030 and the real-clock import in test_v2912 were aligned with
the same fixture clock. No production validation rule was changed.

A diagnostic full run with a completely static instant exposed a fixture problem:
chat intentionally writes microsecond timestamps, but the fixture collapsed them
all to one value. The deterministic microsecond counter preserves event ordering
without artificially advancing second-based retry/throttle windows. Chat ordering
and the 429 pause regression both pass with the corrected fixture; chat business
logic and assertions were not changed.

The existing Visual Studio-bundled Node 20.13.1 executes the reviewed JS files via
`run_js_tests.py`. It copies only explicitly allowlisted sources into temporary
storage. Node permissions restrict reads to that snapshot and deny writes,
children, workers and addons. `tests/js_test_guard.cjs` blocks networking/DNS,
fixes host/VM Date, and asserts permission denials before executing each file.
The child environment is replaced; no repository database, credential file, or
real home directory is available. The original Python subprocess guard remains
unchanged.

All nine JS files pass. The formerly skipped localization check had one additional
obsolete source key, `Ask Rosa anything…`; the UI and all locale layers now use
`Ask Delvane anything…`. Only the expected source key was updated; the required
Hungarian translation, complete language/key coverage, and dynamic-pattern checks
remain enforced. The Python localization wrapper stays skipped because its own
direct subprocess path is not authorized by the Python harness; its exact JS
payload is executed successfully through the separate guarded runner.

## Initial validation (historical baseline)

Environment: project-local `.venv`, CPython 3.14, dependencies pinned in
`requirements-dev.lock.txt`. `pip check` passed. Application and business logic,
existing functional assertions, and operational data were not changed. No commit
was created. PyPI was used only for the authorized dependency installation; tests
did not contact real provider APIs.

## Results

Counts are unique tests in disjoint stages after correcting harness issues.
Diagnostic reruns are not added to these counts.

| Stage | Selected | Passed | Failed | Skipped |
|---|---:|---:|---:|---:|
| Isolation | 12 | 12 | 0 | 0 |
| Authentication/authorization and recovery | 18 | 18 | 0 | 0 |
| Reservations/registration | 15 | 13 | 2 | 0 |
| Channex/channel integration | 81 | 75 | 6 | 0 |
| Remaining API/source tests | 70 | 64 | 5 | 1 |
| Total | 196 | 182 | 13 | 1 |

195 tests actually executed. Zero collection/setup errors in the final stage runs.
JUnit reports and the local stage-selection manifest are in ignored
`.pytest_cache/validation-*` files. The isolation report includes the additional
Windows socketpair regression test introduced during validation.

## Genuine application defect: four failures, one root cause

At `app.py:6833`, the legacy integration-level single-range ARI path inserts
`body.rate_huf` directly into parameter 15 (`rate_override_huf`). Pydantic parses
this field as Decimal; SQLite cannot bind Decimal without conversion/an adapter.
The adjacent nightly rate is converted to int, but the override is not. This is
an application persistence defect in the SQLite path, not a missing dependency or
an external-service error. PostgreSQL behavior was not tested.

Affected tests:

- `tests/test_v295.py::test_owner_range_change_batches_and_sends_two_ari_calls`
- `tests/test_v295.py::test_ari_failure_is_durable_and_retries`
- `tests/test_v297.py::test_whole_forint_price_is_sent_in_channex_minor_units`
- `tests/test_v2991.py::test_existing_date_override_survives_base_rate_change`

All four raise `sqlite3.ProgrammingError: Error binding parameter 15: type
'decimal.Decimal' is not supported`. No conversion shim was added to the test
harness, because it would mask business/persistence behavior.

## Outdated test expectations: nine failures

1. Four runtime tests expect version `2.10.27`, while the endpoint returns
   `2.10.55`: `test_schema_migration_and_runtime_health` (test_v25),
   `test_v28_schema_and_runtime`,
   `test_v281_runtime_and_today_registration_is_contextual`, and
   `test_v282_schema_runtime_and_team_overview`. Their old schema assertions
   (`3056`) and the v25 expectation of `development` also need review; execution
   stopped at the first version assertion. The harness intentionally uses `test`.
   Runtime/frontend/FastAPI/schema version drift is independently real technical
   debt; updating these tests alone would not resolve it.
2. `tests/test_v3000.py::test_viza_id_scan_completes_guest_registration_and_queues_event`
   expects immediate complete registration/report queueing. The current scanner
   route sets `needs_review` and returns `pending`; owner verification is the
   later queueing boundary. The newer guest-check-in/verification test passes.
3. `tests/test_v21036.py::test_certification_availability_delivery_returns_the_new_action_task_not_an_older_queued_job`
   sends a hard-coded range starting 2026-11-10. On validation day 2026-11-11 the
   backend correctly rejects it as past. Use a controlled clock/relative fixture
   in a separate test-maintenance change.
4. `tests/test_v299.py::test_manual_closure_survives_booking_cancellation`
   expects one availability job but finds two. The preceding assertion passes:
   availability remains 0, manual availability remains 0, and reservation
   availability becomes 1. Current cancellation deliberately forces historical
   reconciliation, creating another job. The exact job-count expectation is stale;
   this result does not demonstrate that manual closures reopen incorrectly.
5. `tests/test_v223.py::test_v223_frontend_uses_compact_primary_nav_and_chat_send`
   searches for `sendRosaChat`; the frontend now defines and wires
   `sendDelvaneChat`. This source-string test is obsolete, not a browser behavior
   test.
6. `tests/test_v298.py::test_static_assets_are_cache_busted_for_v2104` expects
   three `?v=2.10.27` strings; current assets use 2.11.26 and 2.10.50. Cache-version
   consistency still warrants separate review; this assertion cannot validate it.

Existing functional tests were left unchanged so these mismatches remain visible.

## Harness/environment issues corrected before final results

- Windows asyncio builds an internal wake-up socketpair over loopback TCP. The
  original blanket connect block prevented all 18 authentication tests from
  reaching their API assertions. The guard now permits only that standard-library
  socketpair operation; a regression test confirms ordinary loopback stays blocked.
  All 18 tests passed on rerun.
- JUnit hostname detection attempted a Windows platform subprocess. A synthetic
  test-only hostname removes that need; subprocess blocking remains enabled.
- Raw SQLite connections retained by existing tests can keep Windows files open.
  The harness tracks and closes connections at teardown.

No dependency remained missing after installation. Starlette warns about future
httpx client support, and AnyIO warns about a deprecated portal alias. These are
maintenance warnings, not the causes of the 13 failures.

## Skip and safety boundary

`tests/test_localization.py::test_all_supported_locales_have_full_coverage` is
skipped because it starts a Node child process that would not inherit Python
database/network guards. Standalone JavaScript tests and the fixture-generating
OCR benchmark were outside this Python validation run.

Guards cover the database/configuration paths used by the inspected suite,
including imports, resets, migration adoption, raw file access, SQL ATTACH, and
external networking. They are not an OS security sandbox: alternate native
drivers, raw file APIs under different names, renames, saved unpatched references,
and intentionally disabling pytest configuration require separate review. Tests
must continue to use synthetic data. Live PostgreSQL, providers, device OCR,
parallel execution, and production deployment were not validated.

The environment is ready for regular isolated development against this recorded
baseline. The suite is not green and must not be used as a passing release gate
until the genuine defect and outdated assertions are addressed deliberately.
