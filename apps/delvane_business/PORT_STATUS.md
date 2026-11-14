# Delvane PMS Flutter port: current status
## Post-acceptance improvements (2026-11-14)

See POST_ACCEPTANCE_IMPROVEMENTS.md for the 14-item implementation report,
changed files, migration 3072, exact launch/install commands and manual checks.
Analysis clean; Flutter full suite 249 passed and final focused suite 19 passed;
backend broader run 143 passed and overlapping final focused run 37 passed;
10 guarded JavaScript files passed; persistent/disposable restart proof passed.
Final Android debug APK and Windows release bundle built successfully.
Flutter 3.50.0/Dart 3.14.0, app IDs, authentication and isolation preserved.

Original staff-close flash did not reproduce; close lifecycle regression passes
but device recheck remains. Guest-browser preview was blocked by origin approval;
browser/camera/Xiaomi checks remain manual. Apple builds/GPU performance unverified.
Legacy guest associations remain unverified; past confirmed reservations are not
physical completion/no-show evidence. No production/staging data or services
accessed, commits or pushes. NTAK/VIZA transport remains outside this change.

## Persistent local acceptance data (2026-11-14)

Confirmed that run_development_workspace.py intentionally uses a new temporary
SQLite collection.db and workspace ID each launch. Normal exit removes that tree;
force-kill may leave it behind, but a restart never reopens it. Reservation writes
commit correctly. Windows and Android USB clients use the same Windows loopback
backend/database. Closing client/helper terminals alone does not clear server data.

Added separate run_persistent_development_workspace.py. Fixed owned storage:
C:\Delvane\Delvane-Development\.development\persistent\workspace.db, with matching
workspace.json identity/encryption key. First start reuses the synthetic bootstrap
and creates the four workspace.invalid accounts once. Ordinary restarts preserve
data/passwords/edits and do not reseed or recreate accounts; existing migrations
and derived task refresh still apply. Stable workspace ID/key retain sessions and
encrypted fictional identity data. The manual store is not created by validation.

Reused isolation guards with unchanged disposable defaults: only owned SQLite,
no external ROSA/OpenAI config, dotenv or sibling adoption, outbound networking,
subprocesses or remote providers. Startup validates file ownership/DB identity,
rejects redirected/hard-linked/unrecognized storage and busy ports, and holds an
OS process lock. API demo reset is disabled; explicit --reset requires typing
RESET PERSISTENT DEVELOPMENT DATA and archives only the stopped owned store in
.development/persistent-archive-*. The whole development directory is Git-ignored.

No Flutter UI, API environment, authentication/CSRF or PMS business logic changed.
The existing USB helper accepts both isolated modes and now prints their mode.
Exact setup/switch/reset commands and limitations: [persistent local setup](../../PERSISTENT_DEVELOPMENT.md).

Validation: separate independent-process HTTP restart proof passed for persistent
reservation/details, guests/encryption, staff, assignments, marker/session and
CSRF, plus disposable fresh-data/ID/cleanup proof. All process-proof data lived in
new owned OS-temporary directories on ephemeral loopback ports; inherited poisoned
fictional production config could not select an external DB. 127 selected guarded
backend tests passed (8 new); Flutter analysis clean; all 229 Flutter tests passed.
PowerShell helper parser and git diff --check passed. Existing Starlette/AnyIO
deprecations remain; no test failures. Logs: build/persistence-{backend-tests,
analysis,flutter-tests}.txt. No new app build/installation or physical-device
acceptance is claimed. Flutter 3.50.0 / Dart 3.14.0 are retained.

Production/staging databases, infrastructure, credentials and integrations were
untouched. No commit or push was made; the pre-existing main branch was already
one commit ahead when this task began. Local acceptance only; keep DB and marker
together and use fictional identities. No cloud service or government work added.


## PMS reliability — staff permissions and guest identity (2026-11-14)

Completed the focused follow-up without repeating the broad audit. Existing dirty
main checkout, Flutter 3.50.0 / Dart 3.14.0, API environments, Hungarian default,
English support and prior cancellation/inquiry guest-link fix are preserved.
Details and acceptance steps: [PMS_RELIABILITY_RESULTS.md](PMS_RELIABILITY_RESULTS.md).

Staff: owner/manager manual-cleaning create/assignment APIs and Team → Workload
controls; active same-tenant assignee validation; cleaner checklist assignment
checks; unfinished-task property scope for cleaner maintenance reads/reporting;
maintenance own/unassigned scope, atomic claim and operator-only assignment and
verification. Legacy resolve shares the guarded status handler. AI reassignment
and undo validate current task/assignee eligibility. Current roles are enforced
by the backend; historical completed cleaning does not grant current property access.

Identity: registration derives from expected guest slots, completeness and human
review, not an editable completion label. Booking changes/cancellation revoke
active links; reconfirmation cannot revive them. Row locks serialize guest-slot
creation, public token consumption and booking edits. Duplicate/public concurrent
submissions cannot duplicate guest writes. Scanner/sensitive-data identical retries
preserve verification; actual edits require review. Partial/invalid scans remain
incomplete, rejected guests can correct their registration, and government queue
events reflect real local verification transitions only. Scanner event logs now
record field names, not full document input. No government transport was added.

Metadata: health/runtime/FastAPI share APP_VERSION=2.10.59, replacing conflicting
hard-coded values. Historical tests use actual version/schema/test environment
contracts and explicit reviewed guest fixtures. The previous test failure is fixed.

Final validation: clean Flutter analysis; 229 Flutter tests passed (8 new); 119
isolated backend tests passed (30 new reliability cases). Earlier focused 46-test
pass overlaps that total. Android debug APK and Windows release both succeeded;
Windows used config/local.json and the existing VS2026 helper. Android used only
the documented process-local TEMP workaround; existing Kotlin migration warning
and Starlette/AnyIO deprecations remain. Evidence: build/pms-reliability-*.txt.

Ready for physical-device acceptance in the guarded disposable workspace; no
physical device, native GUI-to-server acceptance, iOS, live provider or PostgreSQL
concurrency validation is claimed. No physical-arrival/checkout state machine or
new property ACL was invented. Submitted guest-count reductions require explicit
record review; historical identity logs/storage were not migrated. NTAK/VIZA stays
on hold pending core device acceptance, official test packages/module, identifiers,
certificates/endpoints and a separate isolated test deployment. Operational databases,
production providers/credentials and integrations were untouched; no commit/merge/push.

## PMS workflow audit and guest-link lifecycle safety (2026-11-14)

Inspected current `main` branch/dirty working tree and preserved all pre-existing
environment/UI/IDE/platform changes. Reviewed the nine PMS workflow families,
current adapters/API handlers and associated native/isolated tests. Full findings,
classifications, priorities and NTAK/VIZA prerequisites: [PMS_WORKFLOW_AUDIT.md](PMS_WORKFLOW_AUDIT.md).
The existing 78 F / 21 P / 13 M / 11 B / 2 S ledger is retained; this pass does not
claim a full PMS replacement or promote unrelated workflow rows. The historical
mock-only scope prose at the end of FEATURE_PARITY.md is stale; current app
composition defaults to the authenticated PMS and uses mocks only in explicit demo.

Critical batch: public guest-check-in GET/POST now checks the current booking is
confirmed before exposing or persisting identity data. Cancelled/inquiry stays
return 410; issuing links for non-confirmed stays returns 409 before token creation.
Added two real API lifecycle tests covering cancellation and inquiry demotion,
rejected unauthenticated reads/submissions, and no sensitive/scan persistence.
Existing confirmed guest submission/review remains passing. New source changes
are limited to app.py and tests/test_guest_checkin_lifecycle.py, plus this section
and the new audit. No schema, dependencies or toolchain changes.

Validation: Flutter 3.50.0 / Dart 3.14.0 retained; clean analysis; 221 Flutter tests
passed. Main isolated backend suite: 60 passed. Additional AI/channel suite:
19 passed, 1 pre-existing failure in test_v281 runtime metadata (expected 2.10.27,
actual 2.10.55); subsequent context assertions were not reached. Existing
Starlette/AnyIO warnings and an optional pytest-cache permission warning remain.
Android debug APK and Windows release both built successfully. Android used the
documented process-only TEMP workaround and retains the Kotlin migration warning.
Windows used tool/build_windows.ps1 with config/local.json and existing VS2026
fallback. Build logs: build/pms-audit-android.txt and build/pms-audit-windows.txt.
No physical-device or complete native GUI-to-server acceptance is claimed.

Next critical work: server checklist/maintenance assignment authorization,
registration-versus-identity consistency, version metadata, booking concurrency,
complete status browsing/reassignment and native-to-isolated-server acceptance.
Real Channex delivery, property/room CRUD, invoicing/NAV and payment execution
remain partial or backend-blocked. NTAK/VIZA was not begun: core PMS still needs
acceptance and official test packages/module, identifiers/certificates/endpoints
and a separate isolated test deployment remain prerequisites. Repository notes
about government interface versions were not treated as current specifications.
Operational databases/production integrations were untouched. No commit/push.

## Current pass — API environments and future iOS/staging preparation (2026-11-14)

Added public build-time `DELVANE_ENV=local|staging|production` configuration, with a
central `DELVANE_API_ORIGIN`. Local remains `http://127.0.0.1:8765` and retains the
isolated workspace guard, session keys, Windows workflow and Android USB reversal.
Explicit staging/production builds require HTTPS and matching, pre-login metadata
from the new `/api/client/environment` endpoint. Session credentials are namespaced
by environment/origin and bound to the deployment ID. Existing cookie/CSRF/role
authorization is reused; remote cookies must be Secure. No TLS bypass was introduced.

The backend change is one metadata-only endpoint, configured with
`ROSA_DEPLOYMENT_ENVIRONMENT` and public `ROSA_DEPLOYMENT_ID`. It requires the existing
production-hardening runtime; staging still needs its own future PostgreSQL database,
credentials and storage. No infrastructure, remote server, database, signing account
or integration was created, exposed or contacted. No operational data or production
migration was accessed. Browser PMS/business logic and integration behavior remain.

Validation: clean Flutter analysis; **221 Flutter tests passed**, plus staging and
production define-file compilation checks; **31 isolated backend tests passed** with
clean exit. Android debug and Windows release builds succeeded. Android needed a
process-scoped normal-path TEMP directory for a host JDK loopback-pipe error; no
persistent toolchain/network-policy change was made. The existing Kotlin migration
warning remains. Two minimal pre-existing validation fixes restored the English
`confidence` caption and test lint; Windows pytest now cleans only its own guarded
temporary symlink aliases. Existing UI and Hungarian translations are preserved.

iOS configuration was inspected and its plist validated; no iOS changes were needed.
Compilation/signing and actual HTTPS staging/device tests remain for a future Mac
and deployed staging backend. Preparation does not require paid Apple membership.
Full configuration/build instructions, changes and exact validation limitations:
[API_ENVIRONMENTS.md](API_ENVIRONMENTS.md).

Artifacts: `build/app/outputs/flutter-apk/app-debug.apk` and
`build/windows-vs2026/x64/runner/Release/delvane_business.exe` (keep the full bundle).
No commits, pushes or publication were performed.

## Current pass — mobile polish and Hungarian localization (2026-11-13)

Flutter **3.50.0 / Dart 3.14.0** and the earlier SDK/platform upgrades are retained
on `flutter-upgrade`. The backend, databases, integrations and authentication
contracts were not changed. No commits, pushes or publication were performed.

### Mobile UI and interaction results

- Retained the existing removal of yellow metric-leading lines and grouped
  calendar workspace navigation. Hungarian metric labels fit the two-column pills.
- Corrected asymmetric mobile content padding: the original-asset/Inter wordmark
  now centers on the viewport independently of menu/search/settings widths. The
  desktop content padding remains unchanged. Bundled Inter at the reference CSS
  size/weight/spacing for consistent Android rendering; no runtime font downloads.
- Kept the existing official PNG on the login screen. Kept mobile Intelligence's
  redundant secondary header removed, with larger metric labels and live actions.
- Shared settings/integration symbols use the existing outlined vector system;
  search, notifications and dropdown chevrons now also use vector drawing. Fixed
  the down-chevron direction and stopped translating internal icon names.
- All native text fields now explicitly unfocus on an outside touch. Intelligence
  sizes itself from its actual SafeArea/IME viewport, keeping the composer visible
  normally and above the keyboard. Draft text survives keyboard dismissal.
- Android scrollbars are 2.5px; desktop scrolling retains its 9px treatment.
- Android's bottom operator account display has no action or menu arrow. Windows
  retains its account menu, including narrow windows. The mobile header settings
  control retains language, account, authorized destinations and logout.

### Calendar

The phone uses 18px day numbers, 12px property-color bars, a 40px date-create area
and a separate approximately 60px stay-selection area inside a compact 112px cell.
Property/guest names are not squeezed into cells. The existing ordered property
palette is supplied by the caller. Up to three bars and an overflow count are
shown; a date with several stays opens a scrollable list with full names, dates,
arrival/departure counts and real reservation navigation. Empty dates also expose
their day summary and creation action. Single stays open the actual record.

Confirmed-only filtering, checkout-exclusive occupied nights, month navigation,
property IDs, reservation mutations and backend availability rules are preserved.
Inquiry records do not contribute to occupied stays or arrival/departure counts.
Desktop calendar cards remain unchanged.

### Hungarian and English

Added **703 native Hungarian translations/templates** to the previously empty
`native-hu.json`, extending the existing `WebStrings`/web catalog architecture.
Coverage includes main navigation, Today, Intelligence, Reservations, Reception,
Operations, Team, settings, integrations, security, forms, confirmations, status
enums, validation, safe client errors and explicit demo UI copy. Corrected inherited
Rosa wording in key Delvane headings/composer prompts. Known status fields and
record-link captions are localized at presentation, without changing wire values.

Hungarian remains the production default. English is selectable in settings and
explicit demo preferences; the choice persists in the platform secure store. App
composition waits for preference initialization, and save failures are surfaced.
Queued preference writes recover after failure. Tests use an in-memory credential
vault rather than the host's secure store.

Hungarian date symbols are initialized with the catalog; captions use Hungarian
month/day order. Number and decimal-price display supports Hungarian separators.
Decimal wire strings are formatted without floating-point conversion. Date/time
and numeric form/API formats and validation rules are preserved. Compiled template
patterns prioritize specific phrases; single-pass substitution preserves inserted
names, braces and identifiers verbatim.

**Localization limit:** this is not certification that every server-controlled
string is Hungarian. Guest messages, property/person names, notes, editable
knowledge, configurable checklist labels, provider diagnostics, audit summaries and
server-owned automation labels/descriptions retain their source text. Unknown
server enum codes also remain visible rather than receiving an invented meaning.
Backend-owned English display copy needs an explicit localization contract or
reviewed mappings. A source copy scan and 12 screen captures do not prove every
possible dialog/data state. Brands, API identifiers and ISO/time entry hints are
intentionally not translated as ordinary prose.

### Validation and evidence

- `flutter analyze`: **no issues**.
- `flutter test --reporter expanded`: **193 passed, 0 failed, 0 skipped** (170
  previous tests plus 23 mobile/localization regressions). Includes Hungarian
  screens, header alignment, drawer selection, Android/Windows account behavior,
  settings language persistence, write failure/recovery, decimal precision, template
  captures, keyboard dismissal, checkout exclusion, inquiry exclusion and overflow
  selection. Existing authentication/authorization/workflow tests are retained.
- Android debug APK and Windows release: **both builds succeeded** using the
  existing VS2026 compatibility workflow for Windows. Validation logs are
  `build/mobile-hu-android-build.txt` and `build/mobile-hu-windows-build.txt`.
  The SDK-upgrade Kotlin migration warning remains; no dependency downgrade.
- Twelve **host-rendered** Hungarian 393x852 screenshots are generated in
  `build/mobile-polish-hu/`. Existing paired 390x844 web/Flutter and 1440x1000
  references remain in `build/visual-reference/`. Today and Intelligence were
  visually inspected; these different-size/locale captures are not pixel-perfect
  comparisons. The logical phone viewport is representative, not measured on the
  user's Xiaomi. Windows baseline screenshot tests still run.
- `adb devices -l`: no device connected during this pass. No phone install,
  emulator launch or physical HyperOS verification is claimed. No live API was
  contacted by these tests. No backend tests/migrations were needed because no
  backend source changed.

### Files changed in the UI/localization pass

All paths below are relative to this Flutter project. Pre-existing SDK/platform
changes remain separately listed in `FLUTTER_UPGRADE.md` and were preserved.

- Assets/configuration: `assets/native-hu.json`, `assets/fonts/Inter-Variable.ttf`,
  `assets/fonts/Inter-OFL.txt`, `pubspec.yaml` (font/asset registration only).
- Composition/formatting: `lib/app/app.dart`,
  `lib/core/localization/web_strings.dart`, `lib/domain/models.dart`,
  `lib/shared/app_shell.dart`, `lib/shared/components.dart`.
- PMS UI: `lib/features/pms/administration_pages.dart`, `ask_bar.dart`,
  `distribution_dialog.dart`, `guest_history_dialog.dart`, `integrations_page.dart`,
  `intelligence_workspace.dart`, **`mobile_calendar_day.dart` (new)**,
  `operations_pages.dart`, `pms_controller.dart`, `pms_dialogs.dart`, `pms_icons.dart`,
  `pms_shell.dart`, `pms_style.dart`, `property_rates_dialog.dart`,
  `reception_page.dart`, `reservation_dialogs.dart`, `team_page.dart`.
- Other client surfaces: `lib/features/ai/ai_page.dart`,
  `lib/features/reception/reception_page.dart`,
  `lib/features/reservations/reservations_page.dart`,
  `lib/features/settings/settings_page.dart`,
  `lib/features/workspace/login_page.dart`, `record_page.dart`,
  `workspace_page.dart`, `workspace_repository.dart` (display captions only).
- Tests: **`test/mobile_polish_test.dart` (new)**, `test/flutter_test_config.dart`,
  `test/support/visual_fonts.dart`, `test/visual_interactions_test.dart`,
  `test/visual_parity_test.dart`. Minor formatter changes also accompany preserved
  SDK import changes in other existing UI files.
- Documentation: `PORT_STATUS.md`, `ANDROID_TESTING.md`.

Inter was obtained from the Google Fonts `ofl/inter` distribution with its SIL OFL
license bundled. Font SHA-256:
`29160a80ff49ddcab2c97711247e08b1fab27a484a329ce8b813d820dc559031`.

Remaining acceptance work: physical Xiaomi/HyperOS font scaling, GPU/glass rendering,
keyboard types, landscape layouts, gesture insets, secure-store restore and lifecycle
behavior. Existing backend-blocked features/parity limitations below remain.

## Latest pass — Flutter 3.50 stable / Codemagic preparation

Updated 2026-11-13 on `flutter-upgrade`. Local SDK upgraded in place from Flutter
3.32.2 / Dart 3.8.1 to **Flutter 3.50.0 / Dart 3.14.0**, without force or discarding
SDK source edits. Generated SDK Gradle output was preserved in an ignored backup.

`intl` is now **0.20.3**, matching the new SDK localization constraint. Material
imports/delegates moved to official `material_ui 1.11.0`; secure-storage 9.2.4 is
retained. Existing Hungarian/English behavior and catalogs are preserved. Narrow
SDK compatibility fixes cover dropdown initialization, ListTile ink surfaces and
an existing import-alias collision. Tests use an explicit English fixture locale;
new tests verify production Hungarian default and language persistence.

Android uses Gradle 9.5.0 / AGP 9.3.1 / Kotlin 2.4.20, SDK 36, NDK 28.2.13676358,
Java 17 and minimum SDK 24. Legacy plugin compatibility flags were added by Flutter;
a non-fatal built-in-Kotlin migration warning remains. Existing loopback-only debug
network policy, app identity, session storage and backend safeguards are preserved.

iOS files already existed. Added missing CocoaPods wiring, aligned the minimum to
iOS 15, and adopted the SDK scene lifecycle/plugin registration. Plists and source
references pass static checks. iOS compilation, signing and device acceptance were
**not** run on this Windows host. Recommend pinned Flutter 3.50.0, Xcode 27.2 and
CocoaPods 1.17.0 for the first Codemagic validation build; no remote build was started.

Validation: doctor clean, pub get passed, analysis clean, **170 Flutter tests passed**,
Android debug APK built and Windows release built through the existing VS2026
compatibility workflow. Full versions, commands, dependency changes, evidence,
remaining limitations and the exact file list are in
[FLUTTER_UPGRADE.md](FLUTTER_UPGRADE.md).

No backend source or operational database changed; no production integrations,
commits, pushes or publication. Functional parity counts below remain unchanged.

## Latest pass — Android USB development readiness

Updated 2026-11-12. The existing Git tree was clean at the start. An IDE-generated
`.vscode/settings.json` change appeared during the work and was left untouched.
This is the same Flutter client, not a second Android codebase. Backend source,
operational databases, provider integrations, dependencies and Windows source
configuration were preserved. No commits/publication.

### Configuration and runtime changes

- Android debug APK builds with Gradle 8.12, existing AGP 8.7.3 / Kotlin 2.1.0,
  configured JDK 17 and installed NDK 27.0.12077973. Gradle 9.7.1 failed compiling
  Flutter 3.32.2's Gradle plugin; Flutter's default NDK 26.3 mismatched the existing
  secure-storage/path-provider requirements. No SDK/plugin upgrade was performed.
- Debug-only Network Security Configuration permits HTTP for exactly loopback
  `127.0.0.1` / `localhost`. Main profile/release policy denies cleartext. The
  default API remains `http://127.0.0.1:8765`, forwarded over USB to Windows loopback.
  No LAN listener, firewall opening or production bypass was added.
- `tool/connect_android.ps1` selects an authorized device, verifies the local
  isolated-workspace marker without HTTP redirects, refuses conflicting forwards,
  configures `adb reverse`, and optionally installs/launches the debug APK. It does
  not start the backend, uninstall an existing app or clear device data.
- Session cookies, CSRF, server roles, expiration/logout and the workspace marker
  remain unchanged. Existing Android encrypted preferences/Keystore session storage
  is retained; passwords are never persisted. Cloud backup is disabled; Android 12+
  device-transfer/cloud rules also exclude shared preferences to prevent keyless
  restoration of encrypted sessions.
- Intelligence's fixed workspace height now subtracts keyboard insets, preserving
  composer access with the Android IME open. Existing responsive navigation, forms,
  `adjustResize`, SafeArea, tables and page APIs remain in place. No visual redesign.

### Files changed

All within `apps/delvane_business/`:

- `android/gradle/wrapper/gradle-wrapper.properties`, `android/app/build.gradle.kts`.
- `android/app/src/main/AndroidManifest.xml`, `android/app/src/debug/AndroidManifest.xml`.
- New `android/app/src/debug/res/xml/development_network_security.xml` and
  `android/app/src/main/res/xml/session_data_extraction_rules.xml`.
- `lib/features/pms/intelligence_workspace.dart`.
- New `test/android_readiness_test.dart`, `tool/connect_android.ps1`,
  `ANDROID_TESTING.md`; updated `README.md` and `PORT_STATUS.md`.

### Validation

- `flutter --no-version-check analyze`: **no issues**.
- Complete `flutter test`: **168 passed, 0 failed, 0 skipped**. Eight new host
  Android-theme tests cover seven principal page families, system insets, drawer
  opening and a keyboard-resized Intelligence composer. Existing session/logout,
  role, reservation, Reception, operations/staff and desktop tests remain passing.
  These are simulated Android widget layouts, not actual phone execution.
- `flutter --no-version-check build apk --debug`: **succeeded** after final NDK and
  policy changes. APK: `build/app/outputs/flutter-apk/app-debug.apk`, 94,421,196 bytes;
  application `com.delvane.delvane_business`, version 0.1.0+1, min SDK 21 / target and
  compile SDK 35, including `arm64-v8a` for Xiaomi 15.
- Packaged manifest/XML inspected using SDK `aapt`: backup disabled, extraction
  exclusions, loopback-only cleartext exception and `adjustResize` confirmed.
  `zipalign -c -P 16 4` passed; packaged ARM64 libraries have 65536-byte ELF LOAD
  alignment. No physical 16 KB device compatibility claim is made.
- `.venv` isolated `tests/test_flutter_workspace.py`: **9 passed**, with two existing
  Starlette/httpx/AnyIO deprecation warnings. No ordinary backend was launched.
- No Android device was listed by `adb devices -l`. No APK installation, launch,
  actual USB API request, Keystore device round trip or HyperOS acceptance occurred.
  The helper's safe no-device refusal was verified.
- Windows release regression: **succeeded** using installed VS 2026 CMake/MSBuild
  in `build/windows-android-regression/x64/runner/Release/`. The ordinary wrapper
  reached the expected VS fallback but linking failed with LNK1104 because the
  standard release executable was running. That user application was not stopped
  or replaced; the separate ignored output tree avoids its lock. Logs are in
  `build/android-windows-regression-build.txt` and
  `build/android-windows-regression-alternate.txt`.

### Testing next

Use [ANDROID_TESTING.md](ANDROID_TESTING.md): start the guarded temporary backend,
connect/authorize the Xiaomi, then run the USB helper with `-Install`. All four
synthetic role accounts are supported. Reapply forwarding after USB reconnect.
HyperOS permissions, Keystore restore, gesture bars, fonts/scaling, landscape/IME,
system Back and GPU rendering still require real-device acceptance. Keep provider
credentials absent and use only disposable data. Existing parity limitations and
backend-blocked/simulated workflows remain as documented below.

## Latest continuation — Operational desk, administration and visual depth

Updated 2026-11-12. Previous uncommitted work, including the original visual pass,
was preserved. This section supersedes the counts below. No backend application
code, architecture, dependencies or operational data changed. No real Channex,
government, messaging or AI provider was contacted. No commit/publication.

### Work completed

- Intelligence pulse/brief controls now open the original **Live context** desk:
  At a glance, Needs you, Exceptions and Next 48h. It reads the already loaded
  `/api/intelligence` contract, uses the existing backend task/arrival/exception
  summaries, and preserves the original distinctions between handled counts and
  real action execution. Desktop workspace insets and mobile full-width geometry
  are based on computed reference styles, not a new navigation concept.
- Approve/Decline uses `POST /api/approvals/{id}/resolve` with existing session/CSRF
  and operator checks. This resolves/logs an approval record, not an arbitrary
  business transaction. Accepted actions close before refresh. A session-only
  snapshot prevents the closing route from reading cleared parent data; failed
  mutations retain the decision and error. Worker opening is denied.
- Security Center now renders actual `/api/system/runtime` environment, database,
  schema and version, six posture indicators and `/api/security` role permissions.
  Sessions and permissions share desktop columns. No database filesystem path or
  credentials are displayed, and no fixed version is substituted for server data.
  Existing owner-only session revocation remains intact.
- Train Delvane now includes original scope tabs, prototype warning, configured
  field indicators, persisted completeness and property/shared context. Existing
  knowledge and authority mutations remain unchanged; unsaved scope-change
  confirmation is retained. Full localization/legend/savebar fidelity remains.
- Simulation displays simulated/awaiting/executed counts, source payload labels
  and operating mode/time. Business memory preserves structured values when no
  note/topic exists and shows subject/confidence. Existing Undo and notifications
  remain connected; these records do not imply unrestricted autonomous execution.
- Identity review adds explicit loading/empty feedback and the original 1000-character
  note limit. Actual owner verification/rejection and secure link workflows were
  retained. Public native camera/OCR and sensitive vault editors were not invented.
- Property context now includes original arrival/departure timing and primary stay
  source/reference/registration badge. Shared dialogs have source blur/saturation;
  settings saturation is corrected; narrow reservation detail is bottom aligned.

### Files changed in this continuation

Within `apps/delvane_business/`:

- `lib/features/pms/operational_desk.dart` (new), `intelligence_workspace.dart`,
  `administration_pages.dart`, `pms_style.dart`, `reservation_dialogs.dart`,
  `property_dialog.dart`.
- `test/operational_desk_test.dart` (new), `test/visual_parity_test.dart`,
  `test/fixtures/web_reference.json`, `tool/capture_web_reference.py`.
- `PORT_STATUS.md`, `VISUAL_REFERENCE.md`, `FEATURE_PARITY.md`, `README.md`.

Repository root: `tests/test_flutter_visual_contracts.py`. These 15 files are this
continuation's changes; older dirty files and user Gradle/IDE edits are preserved.

### Verification and evidence

- Flutter analysis: **no issues**.
- Complete Flutter suite: **160 passed, 0 failed, 0 skipped**. New desk tests cover
  both decisions, failure retention, worker exclusion, mobile tabs, server runtime
  mapping, action counts/labels and structured memory. Existing auth/session/role,
  reservation, reception, operations, staff and distribution tests also pass.
- Selected isolated Python suite: **48 passed, 0 failed, 0 skipped**, with two
  existing Starlette/httpx/AnyIO deprecation warnings. Command from repository root:

  ```powershell
  .\.venv\Scripts\python -B -m pytest -q tests/test_isolation.py tests/test_flutter_visual_contracts.py tests/test_flutter_reservation_reception.py tests/test_flutter_operations_admin.py tests/test_flutter_distribution.py tests/test_flutter_workspace.py tests/test_guest_checkin.py
  ```

  This exercises create/edit/cancel and booking validation, Reception drafting/
  arrival/request/scheduled approvals, guest link/verification, cleaning checklist/
  completion, maintenance transitions, staff permissions and guarded workspace/
  session behavior. Channex adapters are stubbed, or setup/role failures are
  asserted before provider access. All SQLite work stays under root test isolation.
  These are real in-process ASGI API workflows plus native mapping/widget tests;
  a full Win32 GUI-to-server automation run was **not** performed.
- Captures expanded from 30 to **38 web / 38 Flutter images**, including all four
  desk tabs on desktop/mobile, with synthetic shared fixture data. Selected paired
  desk, property and Security images were inspected; all captured layouts pass.
  Source bug `wireRosa` remains recorded without modifying the web reference.
- Windows release build: **succeeded** using `tool/build_windows.ps1` and the
  existing VS 2026 fallback after Flutter's incompatible VS 2019 generator attempt.
  Executable: `build/windows-vs2026/x64/runner/Release/delvane_business.exe`.
  Keep its adjacent DLLs and `data/` directory together.
- Logs/evidence are ignored under `build/visual-reference/`: `migration-tests.txt`,
  `backend-migration-tests.txt`, `migration-windows-build.txt`, paired PNGs and CSS JSON.

### Acceptance readiness and remaining work

The 125-row ledger now reports **78 F / 21 P / 13 M / 11 B / 2 S**. Five rows
advanced on implementation/test evidence; visual improvements did not automatically
promote unrelated workflows. Missing native workflows remain identified separately
from backend limitations. In particular, public native guest OCR/check-in, credential/
commercial onboarding, sensitive vault/scanner ingestion, API-only government setup/
preview, recovery tokens, maintenance reassignment and welcome/reset remain absent.
The existing browser guest journey is preserved.

Backend blockers remain property CRUD, physical-room allocation, certified government
transport, invoicing/NAV, card processing, transactional invitation/email delivery,
working MFA/passkeys, direct additional OTA adapters, payroll/purchasing and durable
offline/push. Original sandbox and simulate-send stay explicitly simulated.

This build is ready for **comprehensive manual acceptance of implemented workflows
in the disposable workspace**, not a production cutover or a completed migration.
Use the guarded README launcher and synthetic accounts. Check desktop/mobile-sized
windows, keyboard/Back/Escape, pending/failure/session-expiry behavior and each role;
create/edit/cancel a synthetic stay, check calendar/readiness/cleaning derivation,
exercise Reception drafts/approvals, finish assigned cleaning, resolve/verify
maintenance, inspect staff access and unconfigured/sandbox Channex states. Never
enter real credentials or enable provider networking. Preserve the browser PMS
until missing/partial rows and device acceptance are resolved.

Pixel-perfect parity is not claimed. Remaining differences include font metrics,
Security card density/decoration, property dialog borders/chips/scroll structure,
some mobile reception/forms and native menus/scrollbars. See VISUAL_REFERENCE.md.

## Latest pass — Source-based visual and interaction fidelity

Updated 2026-11-12. This section supersedes validation counts and visual notes in
the historical passes below; their functional coverage and limitations still
apply. Backend source, dependencies, operational databases and production services
were not changed or accessed. Existing Android Gradle and `.vscode/` changes were
preserved. No commits or publication.

### Corrected components and pages

- Shell: measured 235px sidebar, source logo/brand typography, 54px desktop / 60px
  mobile navigation, yellow selection gradient, original symbol controls, compact
  utility bar, scrolling navigation and account footer. Main content now starts
  at the top even on short pages. Mobile navigation closes on selection.
- Shared design: source font fallback and text sizes, responsive headings, cards,
  shadows, buttons, forms, pills/counts, lifecycle rail, tabs, menus and dialogs.
  Long mobile dialog titles/actions wrap instead of overflowing. Existing busy
  close guards and submission behavior remain intact.
- Settings: original grouped labels in a right-hand glass sheet, source dimensions
  and responsive margins, existing role-filtered routes and logout/language
  controls. The sheet is removed with the protected navigator on session expiry.
- Today: source heading/urgency, 66px metrics, registration strip, compact queue
  panels, time/severity hierarchy, property readiness and aligned actions. Worker
  task columns retain real start/checklist/finish callbacks.
- Intelligence: active v264 compact workspace rather than legacy oversized metric
  blocks; pulse, centered empty state, bottom prompts/composer and message scroll.
  Existing chat/proposal APIs, errors and session safeguards remain in use.
- Reservations: original calendar heading, padding, weekday labels, elastic cell
  heights, translucent stay cards with property-color dots and contextual actions.
  Existing creation/edit/cancellation/date navigation workflows were preserved.
- Reception: measured list/detail widths, independent pane scrolling, metrics and
  empty detail panel; no changes to draft, approval, schedule or rule APIs.
- Team: person-card hierarchy, 48px avatars, contact panels, security chips, compact
  statistics and plain tabs; existing management permissions preserved.
- Operations, maintenance, supplies, property dialogs, administration, integrations
  and worker pages use the corrected shared controls/headers. Maintenance now uses
  the original numbered lifecycle rail.
- Restored the original floating Ask bar on Reservations, Reception, Team and Train
  only, using `POST /api/rosa/ask`. Its local-answer contract and CSRF enforcement
  were verified against disposable data. It does not claim provider delivery.

### Files changed in this pass

Within `apps/delvane_business/`:

- `lib/features/pms/pms_style.dart`, `pms_shell.dart`, `reception_page.dart`,
  `team_page.dart`, `operations_pages.dart`, `administration_pages.dart`,
  `integrations_page.dart`.
- New `lib/features/pms/intelligence_workspace.dart` and `ask_bar.dart`.
- `test/fixtures/web_reference.json`, `test/pms_port_test.dart`; new
  `test/support/visual_fonts.dart`, `test/visual_parity_test.dart` and
  `test/visual_interactions_test.dart`.
- `tool/capture_web_reference.py`, `README.md`, `PORT_STATUS.md`; new
  `VISUAL_REFERENCE.md`.

Repository root: new `tests/test_flutter_visual_contracts.py`. No backend application
files changed. These are 19 files; the pre-existing Gradle/IDE changes are excluded.

### Comparison evidence and limits

[VISUAL_REFERENCE.md](VISUAL_REFERENCE.md) records measured source values,
breakpoint/context overrides, capture instructions and limitations. The ignored
`build/visual-reference/` folder contains 30 web and 30 final Flutter screenshots:
15 states at 1440 × 1000 and 390 × 844, plus browser CSS and native geometry JSON.
Both renderers use the same synthetic fixture; the original static frontend was
served through an isolated read-only fixture server without importing the backend.
No operational database or real external integration was used.

The Today desktop metrics row is x307/y208, 1046 × 66 in Flutter versus
x307/y208.89, 1046 × 66 in the web reference. This is useful geometry evidence,
not a whole-page pixel match. Remaining differences include font kerning/weights,
lower-page row positions, glass saturation/inset highlights, native menus and
scrollbars, some mobile layouts and uncaptured expanded/error/dialog states.
The original Team/Train source calls missing `wireRosa`; capture records that
reference error without a shim. Native working controls were not broken to match it.
Captures are renderer tests, not end-to-end Win32/mobile acceptance. No pixel-perfect
claim or automated image-diff threshold is made. Functional parity counts from the
previous pass are not promoted based solely on these appearance changes.

### Validation — completed 2026-11-12

- `flutter --no-version-check analyze`: **no issues**.
- `flutter --no-version-check test --reporter expanded`: **145 passed, 0 failed,
  0 skipped**. Includes 30 desktop/mobile render tests and 5 new interaction tests;
  existing reservation, reception, distribution, property, staff, worker, auth,
  session and role-navigation tests remain in the complete run.
- `python -B -m pytest -q tests/test_isolation.py tests/test_flutter_visual_contracts.py`
  through the repository `.venv`: **14 passed, 0 failed, 0 skipped**. The new Ask
  contract and missing-CSRF tests use root isolation guards and temporary SQLite.
  Two existing Starlette/httpx/AnyIO deprecation warnings remain; no dependency
  installation or upgrade was needed. The full backend suite was not rerun because
  backend application code did not change.
- `tool/build_windows.ps1`: **Windows release succeeded** through its existing
  VS 2026 CMake/MSBuild fallback after Flutter's incompatible VS 2019 generator
  attempt. Bundle: `build/windows-vs2026/x64/runner/Release/`; executable
  `delvane_business.exe`. Keep the DLLs and `data/` alongside it.
- Build/test logs: ignored `build/visual-reference/regression-final.txt` and
  `windows-build-final.txt`. Setup and guarded launch remain in [README.md](README.md).

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
