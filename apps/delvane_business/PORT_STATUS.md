# Delvane PMS Flutter port: current status

## Latest pass — Distribution and remaining functional parity

Updated 2026-11-11. This section supersedes the historical reports below. The
existing web PMS, including its later JavaScript overrides, remains authoritative.
Earlier uncommitted work was preserved. Backend source, operational databases,
production integrations and dependencies were not changed. No commits/publication.

### Workflows now connected

- Integrations replaces the remaining navigation-only notice with actual connection
  cards, distribution/queue/acknowledgement counts, history, configured/unconfigured
  states, known staging/production labels and certification-workspace context.
  Unknown environment is reported as unknown. Owner-only Add connection creates
  the original local sandbox slot; it does not configure credentials or grant OTA access.
- Map existing inventory loads remote property/room/rate options through FastAPI,
  shows local room inventory and dependent rate-plan choices, and submits complete
  property/room/rate mappings. Changing a room clears incompatible selected rates.
  Failed inventory reads clear stale choices and disable Save. The client does not
  create remote inventory or implement the obsolete staging-creation flow.
- Rates & availability includes existing single-range controls: room/default/all
  mapped rooms, rate plan, available units, nightly price, arrival/through minimum
  stays, maximum stay, stop sell, closed arrival/departure and certification resend.
  Bulk rows have independent rate plans/dates/restrictions, add/remove, duplicate-plan
  checks and one batch request. Blank fields remain null (keep current), false
  remains false, and no availability field leaks into rate-only batch updates.
- Existing base-calendar publication (365 days), 500-day full sync, safe delivery
  queue/error/retry diagnostics and explicit pending retry are connected. Results
  distinguish no-change, queued, retrying and submitted tasks. Accepted writes show
  a result instead of leaving a repeatable Save button after a failed later read.
  Provider task submission does not mean OTA acceptance or certification.
- Decimal rate inputs use exact decimal strings accepted by Pydantic Decimal;
  integer prices remain integers. No binary floating-point price conversion occurs.
  The separate base-rate endpoint accepts only integer whole units, including for
  non-HUF currencies; the native form reports that backend limitation explicitly.
- Check bookings uses the existing receiver and displays revision/count/error and
  saved/acknowledgement state. It remains unavailable when the server reports setup
  incomplete. Background polling, durable storage, retry and acknowledgement stay
  on the backend. No provider request was actually made in this development pass.
- The original local Test feed workflow is reproduced: add synthetic booking,
  extend a night, cancel/restore, outage/recover, load/replace iCal, preview changes
  and apply import. It is labeled a local simulator. Preview is separate from import;
  accepted mutation plus failed refresh locks additional writes until a successful
  refresh. This is original simulation parity, not mock replacement of a live API.
- Property Rate plans reads actual room/plan/mapping information and can create a
  plan through the existing API using a returned local room and exact integer HUF.
  A complete dedicated web creation dialog was not found; this native form exposes
  existing backend functionality using shared forms, not a newly invented rate
  engine. Arbitrary plan editing/deletion and existing room-inventory editing lack
  supporting endpoints and are not simulated.
- Guest history now includes the original Add preference key/value form and saves
  to the existing API. Operations adds the original eight-row journey pagination,
  current-stage context and stay navigation. Existing cleaner, maintenance,
  inventory, readiness, scheduling derivation and staff functionality is retained.
- Cross-entity search now routes guest/message results as well as properties/stays.
  Ctrl-K/Cmd-K opens search. Async results do not update an already closed dialog.
- Government reporting displays the actual lock/certification flag and per-system
  queue states. Native guest administration continues through the existing Today
  risk queue, stay completeness, secure links, reminders and owner verification.
  No certified submission, document scanner, invoice or payment flow was invented.

### Existing endpoints connected in this pass

All paths are under `/api`. No endpoints were added or modified.

| Area | Contracts |
|---|---|
| Integration workspace | `GET /integrations`, `/integration-sync/summary`, `/integration-events`, `/government/status`, `/properties`; owner `POST /integrations` |
| Channex mapping | `GET/PUT /integrations/{id}/channex/inventory-mapping`, including selected-property query; `GET .../channex/rate-mappings` |
| Pricing/distribution | `GET/PUT .../channex/ari`; `PUT .../channex/ari/batch`, `.../channex/base-rate`; `POST .../channex/full-sync` |
| Delivery/receiver | `GET .../channex/outbox`; `POST .../channex/outbox/retry`, `.../channex/receive` |
| Original simulator | `GET /integrations/{id}/feed`; `POST .../sandbox/events`; `PATCH .../sandbox/events/{external_ref}`; `POST .../sandbox/outage`, `.../sandbox/recover`, `.../sandbox/ical`, `.../sync/preview`, `.../sync/apply` |
| Property rates | `GET /properties/{id}/room-types`; `GET/POST /properties/{id}/rate-plans` |
| Guest/search | `POST /guests/{id}/preferences`; existing `GET /guests/{id}`, `/search`, `/guest-journeys` |

### Feature ledger

All **125 original IDs** in FEATURE_PARITY.md were retained. Each current native
location, classification and next action was updated against source/API contracts:
**73 fully implemented reference client workflows, 24 partial, 15 missing native
workflows, 11 blocked by reference/backend limitations, 2 original simulations**.
These are scoped functional classifications, not 73 production-certified features
or a claim of pixel/device acceptance. Navigation alone is not counted complete.
The Web column independently preserves original partial/simulated/backend-only status.

### Validation and safety

- `flutter --no-version-check analyze`: **no issues**.
- `flutter --no-version-check test`: **110 passed, 0 failed, 0 skipped**. Includes
  17 new tests for roles, decimal/integer fidelity, null/false semantics, mapping
  associations/stale reads, batch field ownership, duplicate plans, base/full sync,
  safe delivery labels, failed write retention, sandbox stale locking, preview/import,
  rate creation/preferences, 390/1440 layouts, Ctrl-K and revoked protected dialogs.
- **48 unique isolated Python tests passed, 0 failed, 0 skipped**, across these runs:

  ```powershell
  .\.venv\Scripts\python -B -m pytest -q tests/test_isolation.py tests/test_flutter_distribution.py tests/test_v2107.py tests/test_v21027.py tests/test_v21038.py tests/test_v297.py tests/test_v2912.py tests/test_v3000.py tests/test_v3020.py
  .\.venv\Scripts\python -B -m pytest -q tests/test_v23.py
  ```

  First selection: 42 passed; original sandbox suite: 6 passed. Root conftest
  installed temporary-path/environment/SQLite/file/outbound-network protections
  before application imports. Provider adapters were in-memory fixtures, never
  live Channex. Five new API cases validate exact decimal-string wire values,
  missing-key behavior, worker denial and rate-plan/guest-preference persistence.
  Existing mapping, ARI, full-sync, precision, backoff, government status and sandbox
  import/cancellation/outage/iCal/tenant tests also passed. Existing Starlette/httpx
  and AnyIO deprecation warnings remain; no dependencies were upgraded.
- Windows release: **passed** through `tool/build_windows.ps1`. Flutter's initial
  VS2019 generator failed as expected; the existing local VS2026 fallback built
  and installed the release bundle. No build-tool modifications were needed.
- `git diff --check`: passed. This is a targeted backend selection, not a full
  historical backend-suite claim. No unsafe subprocess-based tests were run.
- No operational server was started; no operational data was accessed or migrated.
  Authentication still requires the isolated development marker. Secure session
  storage, CSRF, expiration and protected-navigation revocation are preserved.
- No new paired visual screenshot comparison or interactive Windows acceptance
  run was performed. Final fonts/spacing/sticky/pane/locale fidelity remains work.

### Files changed in this pass

Paths below are relative to `apps/delvane_business`, except the Python test.
Other pre-existing uncommitted files were preserved.

| File | Change |
|---|---|
| `lib/features/pms/channel_api.dart` | Role-checked channel contracts, exact price values and delivery state labels |
| `lib/features/pms/channex_mapping_dialog.dart` | Property/room/rate mapping and stale selection protection |
| `lib/features/pms/distribution_dialog.dart` | Single/bulk ARI, base calendar, full sync, queue/retry and result states |
| `lib/features/pms/integrations_page.dart` | Live workspace/status/history, owner slot creation and receiver results |
| `lib/features/pms/sandbox_dialog.dart` | Original local feed simulator, preview and import |
| `lib/features/pms/property_rates_dialog.dart` | Existing local rate-plan read/create contracts |
| `lib/features/pms/property_dialog.dart` | Contextual rate-plan entry point |
| `lib/features/pms/guest_history_dialog.dart` | Original guest preference creation |
| `lib/features/pms/pms_shell.dart` | Integrations routing, journey paging/stay links, search routes/shortcut |
| `lib/features/pms/pms_controller.dart` | Real properties/history reads for integrations |
| `test/channel_port_test.dart` | 17 new isolated native contract/widget tests |
| `test/support/channel_pms.dart` | Synthetic, no-socket test transport only |
| `../../tests/test_flutter_distribution.py` | Five guarded real API contract scenarios |
| `FEATURE_PARITY.md` | All 125 current native implementation classifications/evidence |
| `PORT_STATUS.md` | Current implementation/validation/limitations |
| `README.md` | Current validation pointer |

### Remaining gaps and backend blockers

- Native technical credential configuration, commercial authorization onboarding,
  individual inbound acknowledgement retry, government connection configuration
  and developer payload/readiness tools remain missing/partial. The active web
  primarily maps existing inventory and shows a government notice; backend-only
  tools are not presented as fully implemented visible client workflows.
- Original standalone public guest form, camera/OCR/MRZ and diagnostics remain the
  existing browser flow. Native sensitive-vault/scanner administration, recovery/
  email-verification forms, generic approval_items controls, welcome/48-hour desk
  and some full search/filter/detail treatments remain incomplete.
- Existing cleaning scheduling derives from server reservation changes and
  reassignment uses existing chat/proposal execution. No direct generic task
  scheduling/assignment editor endpoint or active dedicated web control was found.
  Manual maintenance reassignment is backend-capable but lacks a complete native
  editor. Existing start/finish/checklist/report/resolve/verify/stock controls remain.
- General property CRUD, physical-room allocation, existing room inventory editing,
  rate-plan edit/delete, certified NTAK/VIZA transport, invoicing/NAV, payment
  processing, transactional invitations, working MFA and durable push/offline
  synchronization cannot be supplied by unsupported Flutter controls.
- Exact web layouts, text metrics, statuses/localization, sticky/independent pane
  scrolling, relative timestamps and complete intelligence/action evidence still
  need the dedicated visual/depth pass. No claim of complete replacement is made.
- Existing backend assignment/tenant validation weaknesses and broader security
  debt are not silently changed in this client port. Prior pass notes remain
  relevant. Production rollout still needs separately authorized security review,
  actual provider acceptance, platform/device tests and certification work.

Windows executable (retain adjacent DLLs and data directory):

```text
C:\Delvane\Delvane-Development\apps\delvane_business\build\windows-vs2026\x64\runner\Release\delvane_business.exe
```

Use the existing isolated launcher only: from the repository root run
`.\.venv\Scripts\python -B run_development_workspace.py`, enter a disposable
password, keep that terminal open and sign in using the synthetic role accounts
described below. Do not substitute an operational launcher/database.

## Historical pass — Properties, Operations, Team and Administration

Updated 2026-11-11. This section supersedes the remaining-work list in the
historical Reservations/Reception report below. Earlier uncommitted work was
preserved. No backend application code, operational databases, production
integrations, dependency declarations or web reference files were changed.
No commit or publication was created.

### Implemented in this pass

- Property cards now open the source property modal: address, guest capacity,
  check-in/out, same-day handoff, today's arrivals/departures, current/next stay,
  cleaning owner/window/status, sellable room types and calendar/reservation links.
  The Add room type form submits name, code, whole units and maximum guests to
  FastAPI. Duplicate codes and capacity bounds remain server validation. Empty
  properties and missing cleaning/stays display explicit empty states.
- Cleaner My day/Schedule retains its assigned-task filtering and checklist API.
  Start now recognizes the server's `open` state as well as legacy `pending`.
  Completed checklist items enable the original finish-note workflow, including
  an empty optional note, followed by the existing finish endpoint and reload.
  Arrival/checkout windows, preparation requests and next guest count are shown.
- Maintenance has report forms, property/severity/details, case cards, lifecycle
  rails, ownership and timestamps, a status filter, start, resolve and owner/manager
  verification. Creation preserves automatic server assignment. Cleaners can report
  but cannot progress cases; maintenance cannot create cases or verify their work.
  Worker property selectors use `/api/operations/properties`, preserving the
  narrower API instead of granting access to the general property endpoint.
- Supplies shows live quantities, par/consumption estimates, stock bars and the
  source shopping-list calculation. Adjust stock persists a finite numeric quantity,
  including fractions. No purchasing or simulated restocking was added.
- Team & Access has People, Access & roles and Workload tabs, source member/contact
  cards, account/security indicators, server permission groups, workload and upcoming
  assignments. Managers are read-only. Owners can create/edit members, change roles,
  suspend/reactivate accounts, reset access and revoke sessions. Own role/suspension
  controls are disabled; server self-lockout safeguards remain authoritative.
- Setup passwords are shown once in the protected authenticated navigator, never
  persisted by Flutter or logged, and copied only after explicit user action.
  Session revocation removes an open credential dialog as well as the workspace.
- Train Delvane loads shared/property knowledge and category fields, saves existing
  scopes, and changes existing authority rules. Server permissions allow owners
  and managers to edit both knowledge and authority. Scope changes explicitly warn
  before discarding unsaved local edits.
- Operating mode reads actual observe/assist/autonomous state; only owners see
  mode changes, and autonomous selection requires confirmation. Existing action
  ledger/undo, notification preferences and structured memory are connected.
- Security Center shows live sessions, account indicators, audit and retention;
  only owners receive session-revoke controls. MFA/HTTPS/provider delivery are not
  claimed complete merely because account/status fields exist.
- Shared dialogs block back navigation while a request is in flight. Errors remain
  inline and inputs remain available for correction. An intermediate desktop-width
  utility-bar overflow found by the new tests was fixed using a compact search label.

### Existing API contracts used

No endpoints were added or modified.

| Area | Existing endpoints |
|---|---|
| Property | `GET /api/properties/{id}/overview`; `POST /api/properties/{id}/room-types`; existing property/calendar/reservation reads |
| Cleaning | `GET /api/worker/dashboard`; `PATCH /api/work-tasks/{id}/checklist/{item}`; `POST /api/work-tasks/{id}/start`, `/finish` |
| Maintenance | `GET/POST /api/maintenance`; `PATCH /api/maintenance/{id}/status`; worker-safe `GET /api/operations/properties` |
| Stock | `GET /api/inventory`; `PATCH /api/inventory/{id}` |
| Team | `GET /api/team/overview`; `POST /api/team/members`; `PATCH /api/team/members/{id}`; `POST .../reset-access`, `.../revoke-sessions` |
| Knowledge | `GET /api/knowledge`; `PUT /api/knowledge/{scope}`; `PATCH /api/authority/{action}` |
| Mode/preferences | `GET /api/organization`, `/api/rosa/actions`, `/api/memory`, `/api/notifications/preferences`; `PATCH /api/organization/mode`; `PUT /api/notifications/preferences`; `POST /api/rosa/actions/{id}/undo` |
| Security | `GET /api/security`, `/api/audit`, `/api/retention`, `/api/system/runtime`; `DELETE /api/security/sessions/{id}` |

### Validation

- `flutter --no-version-check analyze`: no issues.
- `flutter --no-version-check test`: **93 passed, 0 failed, 0 skipped**, including
  20 new management/worker tests. Coverage includes owner creation/edit/suspension/
  reset, manager read-only behavior, worker denial before transport, narrow/desktop
  layouts, property creation, failure/input retention, fractional stock, scoped
  knowledge/authority, cleaner start/checklist/finish and credential-dialog removal.
- Isolated real FastAPI mutations/security: **35 passed, 0 failed, 0 skipped,
  1 deselected**. Command from repository root:

  ```powershell
  .\.venv\Scripts\python -B -m pytest -q tests/test_isolation.py tests/test_flutter_operations_admin.py tests/test_flutter_reservation_reception.py tests/test_v282.py -k 'not schema_runtime'
  ```

  The unrelated historical schema/runtime assertion in `test_v282.py` was not
  selected; it was not altered or newly skipped. This is a targeted backend run,
  not a claim that all historical backend tests pass. Existing Starlette/httpx and
  AnyIO deprecation warnings remain. The root conftest installed temporary-path,
  environment, SQLite/file, migration and outbound-network guards before importing
  the application. Fixture schemas and all mutations used disposable data only.
- Windows release: **passed** using the existing `tool/build_windows.ps1`.
  Flutter 3.32's initial Visual Studio 2019 generator attempt failed as expected;
  the script's project-local Visual Studio 2026 CMake/MSBuild fallback then built
  and installed the release bundle successfully. No SDK/plugin/backend changes
  were needed. Executable:

  ```text
  C:\Delvane\Delvane-Development\apps\delvane_business\build\windows-vs2026\x64\runner\Release\delvane_business.exe
  ```

  Keep the DLLs and `data` directory beside the executable. The isolated launch
  instructions at the end of this document remain applicable. Compilation was
  verified; no claim of an interactive Windows acceptance run is made.
- `git diff --check`: passed. Existing uncommitted changes were preserved.
- No real external delivery/provider test or interactive device acceptance is
  claimed by these automated tests. No operational server was launched.

### Files changed in this pass

Paths are relative to `apps/delvane_business`, except the root Python test.
Earlier uncommitted files outside this list were preserved.

| File | Change |
|---|---|
| `lib/features/pms/property_dialog.dart` | Property overview/readiness and room-type creation |
| `lib/features/pms/operations_pages.dart` | Maintenance lifecycle/reporting/filter and supplies/stock forms |
| `lib/features/pms/operations_workflows.dart` | Role-checked team, maintenance, stock and finish contracts |
| `lib/features/pms/team_page.dart` | People/access/workload, account editing and one-time credentials |
| `lib/features/pms/administration_pages.dart` | Knowledge/authority, mode/preferences/ledger and security |
| `lib/features/pms/pms_shell.dart` | Route new screens, property modal, cleaner finish, compact utility bar |
| `lib/features/pms/pms_controller.dart` | Strict optional-object helper for nullable API relationships |
| `lib/features/pms/pms_dialogs.dart` | Optional text notes while preserving required defaults elsewhere |
| `lib/features/pms/pms_style.dart` | Prevent back navigation during dialog requests |
| `test/management_port_test.dart` | 20 role, mutation, session, failure and responsive tests |
| `test/support/management_pms.dart` | Synthetic stateful management transport, test-only |
| `../../tests/test_flutter_operations_admin.py` | 7 isolated API mutation/permission scenarios |
| `PORT_STATUS.md` | Current status, validation and remaining work |
| `README.md` | Updated current validation pointer |

### Remaining scope and visual differences

This remains an incomplete port, not a complete web replacement:

- Dedicated Channex inventory mapping, rate-plan mapping, ARI/restriction/bulk/base
  price/outbox/full-sync and integration administration dialogs remain unported.
  Existing reservation rate information and availability-delivery evidence are
  preserved; they do not constitute those pricing/distribution editors. This is
  the next implementation section, with disposable provider adapters and no real
  external calls during validation.
- General property/address/time CRUD, physical-room allocation and arbitrary room
  type/rate-plan editing are not supplied by the reference property modal. They
  were not invented. Backend-only rate-plan creation needs a deliberate reference
  workflow decision; existing read APIs remain available to reservation forms.
- Cleaning assignment is automatic/server-driven or executed through existing AI
  proposals; no direct generic assignment PATCH endpoint was found in the reference
  UI. No fake drag/drop assignment was added. Team workload and Operations remain
  read-oriented; fuller journey pagination/filter/detail presentation and the global
  Ask bar still need their remaining source controls.
- Maintenance preserves auto-assignment; a separate manual reassignment editor
  is not added. The existing status endpoint has weaker assignee validation than
  the native UI guard; backend ownership/tenant-assignee hardening would be a
  separately authorized security change, not silently patched in this port.
- Train/Simulation/Security actions are connected, but exact source tabs, score/
  progress treatments, relative dates, complete action payload presentation and
  localization still need refinement. Retention/MFA are indicators, not invented
  enrollment or policy-edit workflows. Integrations/government remain incomplete.
- Property modal width, team heading/card sizing, white/ivory cards, status rails,
  dialog form grouping and responsive grids follow inspected CSS. Exact typography,
  spacing, sticky sections, glass effects and several browser-native controls still
  differ. No new paired pixel comparison of all these screens was completed.
- Previously documented guest profile/preference editing and Reception visual gaps
  remain. No existing Reservation/Reception/Today/Intelligence functionality was
  replaced with mocks. Flutter still requires the isolated-development marker at
  authentication; production connectivity remains intentionally unavailable.

## Historical report — Reservations and Reception pass

Updated 2026-11-11 after the Reservations and Reception implementation pass.
The web PMS is authoritative. The navigation redesign proposed in the historical
FLUTTER_ROADMAP.md remains superseded. This is substantial functional progress,
not a claim of complete web parity or pixel-perfect reproduction.

The repository contained uncommitted work from earlier passes. That work was
preserved. No backend business code, web source/assets, operational paths or
production integrations were modified in this pass. No commit or publication occurred.

## Reservations now implemented

- Calendar previous/next/Today, Go to month, selected-day creation, arrival/departure
  counts, eight source property colors, stay/source labels, full overflow lists and
  checkout-exclusive occupied nights. Inquiries link to the same workspace/editor.
- Toolbar and selected-day reservation creation; edit existing stays; confirm an
  inquiry; explicit cancellation confirmation. All mutations use existing APIs.
- Source editor fields: property, room type, source, guest name, arrival/departure,
  guests, arrival time, total reservation value in HUF, reference and preparation.
- Shared date input/picker, stay-duration/checkout presentation and input-shape
  checks. Capacity, overlap, room ownership and state validation remain in FastAPI.
  HUF stays integer-valued through input, JSON and backend storage.
- Room type inventory/capacity and existing rate-plan base-rate/policy information
  are loaded from the room-type response. A reservation amount is not a nightly
  quote or collected revenue. No unsupported rate_plan_id write was invented.
- Contextual reservation modal with Stay overview, Preparation, Communication and
  Activity tabs; payment/registration/arrival/guest summary; check-in/out details,
  guest memory/preferences/history, linked cleaning and maintenance context.
- Manual arrival time, payment label and registration-status saving; internal notes,
  persisted message history and reservation event history. Manual payment labels
  do not perform charges/refunds; registration completeness is separate from identity review.
- Guest registration state, explicit secure-link generation/copy, reminder draft,
  Open reception, identity verify/reject with method/note, and verification status.
  Links are not generated on modal load and copying is not message delivery.
- Channex availability-delivery evidence and explicit retry using the existing
  reservation endpoint. Task IDs are submission evidence, not final OTA acceptance.
- Stay links from existing property/task record routes open the new reservation
  workspace. Existing authenticated operational-record readers remain available.

## Reception now implemented

- Real Inbox/Scheduled/Automations tabs, counts and backend status indicators.
- Inbox search, selection and mobile list-to-message/back behavior; sender/source,
  message content, linked stay and guest history/preferences context.
- Manual Paste message form with property detection option, linked confirmed stay,
  source, sender/contact, subject and body. A new intake opens the created record.
- Message analysis and extracted arrival/preparation/guest-count chips; unresolved
  questions; local/Luna draft provenance; smart drafting, draft editing and saving.
- Apply actions uses the existing governed backend executor for arrival/preparation
  requests and inquiry creation. Inquiry confirmation uses the reservation editor.
- Mark sent externally remains bookkeeping; Archive removes the active inbox item.
- Scheduled body editing/saving, approval, Simulate send and cancellation. Notices
  retain Communication sandbox and No live external send. No transport was added.
- Automation enabled/authority controls and manual Run Delvane scheduler. Backend
  mode/authority gates remain authoritative; running rules prepares local records.
- Unsaved draft text survives tab/page navigation within the authenticated session,
  without disk persistence. Save is explicit; approval/simulation uses the stored
  server body, so unsaved scheduled text is labeled accordingly.

## Shared components, security and failure handling

PmsWorkflows centralizes the original API contracts with owner/manager guards;
FastAPI still authorizes every request. PmsModal supports the reference header
edit action, busy close protection and scrolling. Forms share input, date, select,
confirmation, status, action/error and toggle components. The existing logo/theme
and localization catalogs are retained.

All PMS dialogs are pushed on the protected navigator, including pre-existing
settings/search/notification dialogs. A new test proves that revocation while a
reservation dialog is open removes that dialog and returns to sign-in. Session
cookies, CSRF, expiry, secure storage and the isolated-workspace gate are unchanged.
Workers are denied booking/message operations before transport and by FastAPI.

No mock fallback or fake success was introduced. Loading failures remain visible;
room-type failures disable booking submission. Mutation conflicts keep input and
show a sanitized error. Accepted Reception writes followed by a failed refresh
lock further actions until successful refresh, including scheduled approval/send.
Writes are never automatically retried. An ambiguous network failure still requires
explicit refresh/review; the existing API has no general idempotency-key contract.
Sensitive response bodies, credentials, identity values and secure links are not logged.

## Endpoints connected in this pass

All paths below are existing FastAPI endpoints. No backend endpoint was added.

| Area | API |
|---|---|
| Calendar/editor | GET /api/reservations; GET /api/properties; GET /api/properties/{p}/room-types |
| Booking mutations | POST /api/reservations; PATCH /api/reservations/{r}; DELETE /api/reservations/{r} |
| Workspace/history | GET /api/reservations/{r}/detail; GET /api/guests/{g} |
| Operational fields/notes | PATCH /api/reservations/{r}/operations; POST /api/reservations/{r}/notes |
| Registration | GET /api/reservations/{r}/guest-checkin-status; GET /api/reservations/{r}/guest-checkin-links; POST /api/reservations/{r}/registration-reminder |
| Identity review | POST /api/reservations/{r}/guests/{g}/verify |
| Availability evidence | GET /api/reservations/{r}/channex-availability-delivery; POST /api/reservations/{r}/channex-availability-delivery/retry |
| Reception | GET /api/reception/summary; GET/POST /api/inbox |
| Message actions | POST /api/inbox/{m}/analyze, /draft, /apply, /reply-sent, /archive; PATCH /api/inbox/{m}/draft |
| Scheduled | GET /api/communications/outbox; PATCH /api/communications/outbox/{o}; POST /api/communications/outbox/{o}/approve, /simulate-send |
| Automations | GET /api/automation/rules; PATCH /api/automation/rules/{a}; POST /api/automation/run |

In grouped message/scheduled rows, suffixes belong to the preceding resource path.
Existing authentication, organization, notification and operational-record APIs
continue to be used. Government/AI/provider credentials never move into Flutter.

## Validation results

| Final check | Executed | Passed | Failed | Skipped |
|---|---:|---:|---:|---:|
| Complete Flutter suite | 73 | 73 | 0 | 0 |
| Isolated Python selection | 21 | 21 | 0 | 0 |
| Unique tests in these final runs | 94 | 94 | 0 | 0 |

Flutter includes the previous 54 tests and 19 new Reservations/Reception tests.
Python includes 12 existing isolation guards and 9 new API mutation cases. Repeated
targeted runs during fixes are not counted twice. Existing assertions were not
removed or weakened. This is not a claim that the full Python suite is green;
previous runtime metadata ambiguities in TEST_VALIDATION.md were outside this selection.

Flutter analyze: no issues. Windows x64 Release: built using the existing app-local
VS 2026 compatibility fallback. The standard Flutter invocation still selects an
unavailable VS 2019 generator on this host; the reviewed fallback succeeds without
changing the SDK or machine policy. No dependencies were added or upgraded.

Commands (Flutter directory unless noted):

```powershell
flutter --no-version-check analyze
flutter --no-version-check test
powershell -NoProfile -ExecutionPolicy Bypass -File .\tool\build_windows.ps1

# Repository root, with conftest isolation installed before app import:
.\.venv\Scripts\python -B -m pytest -q tests/test_isolation.py tests/test_flutter_reservation_reception.py
```

Flutter tests use injected transports and in-memory stores. They cover actual
form/controller actions, exact integer money, modal tabs, selected-day/overflow,
new inbox intake, drafts, structured apply, scheduled approval/simulation, automation
toggles, error recovery, worker denial and protected-dialog revocation. Layouts
include 1440x1000, 390x844 and 844x390; earlier responsive checks remain in the suite.

The Python tests execute real existing ASGI handlers against fresh temporary
SQLite, including owner/manager create/edit/cancel, server conflict/date/room/tenant
validation, notes/history, worker denials, arrival/preparation updates, inquiry
creation/confirmation, manual intake, secure links, human identity review,
rule changes and scheduled local approval/simulation. Local initialization occurs
only inside the existing guards; outbound sockets, real credentials, sibling
adoption and operational database access stay blocked. Existing Starlette/httpx
and AnyIO deprecation warnings remain; no operational migrations were run.

## Visual fidelity and remaining work

The existing HTML handlers, later JavaScript overrides, final CSS and saved web
reference captures were inspected. In particular the final CSS hides Reception's
large heading; Flutter no longer renders that inactive heading. Dialog tab labels,
header editing, field order, status vocabulary, source colors and component styling
follow the reference. No pixel-perfect claim is made, and no new paired pixel
comparison for all new dialog/thread states was completed in this pass.

Remaining differences and limitations:

- Font metrics/weights, frosted layers, exact spacing, sticky modal sections and
  desktop independent-pane scrolling still need comparison/refinement. Mobile
  Reception retains accessible tabs/metrics and a Paste message action; the final
  web CSS hides some of these controls. The existing Paste message handler is
  exposed beside tabs rather than reproducing its inaccessible hidden heading.
- Custom date popup, select menus, clipboard feedback and some action placement
  differ from browser-native widgets. Full localization/date formatting and
  preference persistence are incomplete. Native UI/clipboard device acceptance
  has not been claimed by widget tests or compilation.
- Guest history/preferences can be read; the complete guest profile presentation
  and preference editor are not yet ported.
- Property room-type creation/admin and the dedicated channel ARI/rate-plan/mapping
  interfaces remain incomplete. Rate-plan information shown in a booking is not
  an invented pricing/availability quote. Physical-room allocation is not supplied
  by the reference APIs.
- Reception faithfully uses stored messages; it does not invent IMAP/OTA delivery,
  real external sending, an independent delivery scheduler or full mail threading.
- Team, knowledge, operating-mode administration, supplies, broader security,
  integrations/government interfaces and worker finish-note/actions still need
  their remaining source controls. Prior Today/Intelligence/Operations work is retained.

Next section: finish the reference guest-profile/preference and property room-type
workspaces, then the existing integrations/ARI controls, while doing paired visual
checks of reservation modal states and Reception desktop/mobile panes. This build
is not yet a complete replacement for the web PMS.

## Files changed in the historical Reservations/Reception execution

Paths in the app column are relative to apps/delvane_business. Earlier uncommitted
app composition/workspace test changes were retained, not counted as new work.

| File | Change |
|---|---|
| lib/features/pms/pms_workflows.dart | Role-guarded existing API contracts and safe mutation errors |
| lib/features/pms/pms_dialogs.dart | Shared forms/actions, confirmations, ISO dates/time checks and picker |
| lib/features/pms/reservation_dialogs.dart | Editor, workspace, registration/identity and delivery controls |
| lib/features/pms/reception_page.dart | Inbox/thread, intake, scheduled messages and automations |
| lib/features/pms/guest_history_dialog.dart | Shared authorized guest history/preferences read |
| lib/features/pms/pms_shell.dart | Calendar/create/overflow/inquiry and reservation entry points |
| lib/features/pms/pms_controller.dart | Session-only Reception selection/tab/draft state |
| lib/features/pms/pms_style.dart | Reusable controls, modal header/busy state and responsive columns |
| lib/features/workspace/record_page.dart | Existing stay links open the new workspace when supplied |
| test/reservation_reception_test.dart | 19 new workflow, security, layout and failure tests |
| test/support/workflow_pms.dart | Stateful synthetic contract double, never imported by live UI |
| ../../tests/test_flutter_reservation_reception.py | 9 isolated real-backend mutation cases |
| PORT_STATUS.md | Current implementation, validation and limitations |
| README.md | Current pass pointer; historical Milestone 1 setup remains below |

## Windows executable and isolated launch

```text
C:\Delvane\Delvane-Development\apps\delvane_business\build\windows-vs2026\x64\runner\Release\delvane_business.exe
```

From the repository root start .venv/Scripts/python -B run_development_workspace.py,
choose the disposable password, and keep that terminal open. Launch the executable
and sign in as owner/manager/cleaner/maintenance @workspace.invalid using that
password. Restarting the guarded server replaces its synthetic data. The client
still requires its isolation marker before credentials are sent. Never substitute
an ordinary operational launcher or copy an operational database into this workspace.
