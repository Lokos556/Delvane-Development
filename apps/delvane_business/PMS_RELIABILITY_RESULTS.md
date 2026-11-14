# PMS workflow reliability — 14 November 2026

Implemented in the existing `C:\Delvane\Delvane-Development` checkout on `main`. Preserved the existing uncommitted work, Flutter 3.50.0 / Dart 3.14.0, local/staging/production isolation, existing authentication/CSRF and Hungarian-default/English UI. No operational database, production provider, credentials, deployment, commit, merge or push was used.

## Staff assignments and permissions

- Owners/managers can create manual cleaning tasks and assign, reassign or unassign open work. New backend contracts: `POST /api/work-tasks`, `PATCH /api/work-tasks/{id}/assignment`. Derived turnover tasks retain their existing reservation-driven scheduling; manual tasks have separate source keys and survive refresh.
- Team → Workload adds **Create cleaning task** and **Assign work**, covering cleaning and maintenance. Assignee choices include only active staff of the required role. Suspended or changed-role assignees must be corrected explicitly. Failures remain inline and preserve input. Owners still exclusively manage accounts; managers receive no new account-management rights.
- Cleaner checklist reads and writes require the actual task assignment. Cross-tenant and other-worker records return indistinguishable not-found errors. Worker start/finish also respects the current role and task kind.
- Cleaner property context, maintenance reads and maintenance reporting require an unfinished assigned cleaning task at that property. Completed historical work does not grant access to current property operations. Completed own-task history remains readable through the task contract.
- Maintenance staff retain the existing own/unassigned case queue. Starting/resolving an unassigned case claims it under a row lock. Workers cannot steal another assignment or self-verify resolved work. The legacy resolve endpoint uses the same authorization as status changes. Only operators can assign maintenance, and the target must be an active maintenance user in the same organization.
- Assignment/status mutations serialize against worker writes. Existing AI reassignment and undo now protect task state; undo cannot restore inactive/wrong-role assignees or rewrite completed tasks. Session identity is read from current user data, so role/suspension changes are enforced by FastAPI on subsequent requests; Flutter revalidates on workspace refresh.

## Guest identity and link lifecycle

- Registration is derived from the expected guest count, completeness and human verification. Missing data means **incomplete**; all data collected but not fully verified means **pending**; only all expected guests verified means **complete**. Reservation creation and both edit routes cannot bypass that rule with a manual completion label.
- Flutter shows data completeness and identity review separately. Registration is read-only in the reservation overview; link/reminder and identity-review actions are unavailable for cancelled/inquiry stays. Guest status/detail/list/registration-centre responses use the derived state. Reopening a workspace reloads server state.
- Booking date/property/room/count/name/status edits revoke active links. Cancellation, imported changes/cancellations and reservation undo also revoke links. Reconfirming a booking does not revive its old links. Expired, revoked and completed tokens cannot submit again; replacement links rotate the prior token.
- Guest submission, verification, token issuance and reservation edits lock the reservation row. Concurrent submissions of the same link save only one identity submission. Repeated status/link requests cannot duplicate guest slots. Reducing the count removes only untouched spare slots; submitted/reviewed records require explicit review instead of silent deletion. Increasing the count makes the reservation incomplete until the extra guests register and are reviewed.
- Public collection validates required identity fields and birth date. Scanner ingestion retains its merge contract, accepts partial scans as incomplete, and never equates collection with verification. Rejected identities can receive a replacement link for correction. Identical scanner or encrypted-sensitive-data retries preserve a later human review; actual identity-data edits require review again.
- Repeated approval does not duplicate government events. A new transition back to fully verified can create updated local outbox events. Responses report whether this request actually queued them; this is not transport, submission acceptance or certification.
- New scanner event logs contain field names rather than document numbers or full input. Public/status/detail responses do not expose document numbers. Existing historical logs and underlying identity-storage encryption/retention policies were not migrated or redesigned.

## Existing test failure

The old test hard-coded runtime version `2.10.27` and schema `3056`, while health/runtime hard-coded `2.10.55` and FastAPI advertised `2.10.59`. Health, runtime and FastAPI now share `APP_VERSION = 2.10.59`; tests compare that contract and `SCHEMA_VERSION`. The older environment assertion now respects the guarded test environment. Legacy registration fixtures were updated to establish actual reviewed identity state instead of treating a manual label as verification. The formerly failing test now passes.

## Validation and build evidence

- Flutter analysis: **clean**.
- Complete Flutter suite: **229 passed** (221 existing plus 8 new tests). Coverage includes operator/worker contracts, excluded inactive assignees, preserved form input on failure, cancelled-stay actions, derived/reopened registration and Hungarian captions. The only later native edit removed an unused test import; final analysis is clean.
- Final broad backend suite: **119 passed**, including **30 new reliability cases**. The preceding focused lifecycle run also passed **46 tests**; those overlap the broad suite and are not added to its count. All backend execution uses repository test isolation, disposable SQLite, absent production credentials and blocked provider/network access.
- Android debug APK: **built successfully**. `apps/delvane_business/build/app/outputs/flutter-apk/app-debug.apk`. Used the documented process-only TEMP workaround; the existing Kotlin migration warning remains.
- Windows release: **built successfully** through `tool/build_windows.ps1 -DartDefineFromFile config/local.json` and the existing VS2026 fallback. Keep the complete `apps/delvane_business/build/windows-vs2026/x64/runner/Release/` bundle together.
- Logs under the app's ignored `build/`: `pms-reliability-analysis.txt`, `pms-reliability-flutter-tests.txt`, `pms-reliability-backend-tests.txt`, `pms-reliability-final-focused.txt`, `pms-reliability-android.txt`, `pms-reliability-windows.txt`.
- `git diff --check` passes. Existing Starlette/AnyIO deprecation warnings remain. No physical phone, Win32 interactive acceptance, iOS build, real PostgreSQL concurrency run, live staging or provider acceptance is claimed.

## Acceptance readiness and remaining boundaries

These changes are ready for physical-device acceptance **against the guarded disposable backend** after automated checks pass. Use synthetic identities and tasks. On Android and Windows, verify: owner/manager task creation and reassignment, the old worker losing access after refresh, own checklist completion, maintenance claim/resolve/operator verify, guest submission/rejection/correction/review, cancellation/edit revocation, reopen/refresh and expired sessions. Include Hungarian and English, keyboard/Back behavior and a failed request/retry.

Property authorization still derives from work assignments; no new per-property ACL or new role was introduced. Unassigned maintenance remains an intentional organization-wide maintenance pool. There is no new physical-arrival/checkout state machine: registration completion is not proof of physical check-in, checkout or government acceptance. A decrease that would discard submitted guest data is deliberately blocked pending an explicit guest-record review/removal workflow. Booking-capacity concurrency and comprehensive PostgreSQL load testing remain separate work. Existing browser manual-registration controls may now receive a safe conflict when attempting a status inconsistent with identity review.

NTAK/VIZA implementation remains on hold. Complete the native-to-disposable-backend device journey and review remaining PMS acceptance risks first. Then obtain official developer/test access, current interface packages and validation sequence, assigned manufacturer/property identifiers, certificates/signing configuration, test endpoints and the VIZA forwarding module. A separately isolated test deployment and official validation/certification remain necessary. No government transport or successful submission was fabricated or started.

## Changed implementation files

Backend: `app.py`; new `tests/test_pms_reliability.py`; adjusted `tests/test_v25.py`, `tests/test_v281.py`. Preserved `tests/test_guest_checkin_lifecycle.py` from the prior fix.

Flutter: `lib/features/pms/operations_workflows.dart`, `pms_controller.dart`, `reservation_dialogs.dart`, `team_page.dart`; new `work_assignment_dialog.dart`; Hungarian catalog `assets/native-hu.json`; new `test/reliability_port_test.dart`; updated synthetic contract doubles `test/support/management_pms.dart`, `test/support/workflow_pms.dart`.

Documentation: this focused results note and a new top section in `PORT_STATUS.md`. Earlier environment/UI/generated changes remain uncommitted and preserved.
