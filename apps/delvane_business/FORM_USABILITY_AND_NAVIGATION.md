# Delvane AI — form usability and mobile navigation

14 November 2026. Repository: C:\Delvane\Delvane-Development.

## Implemented

Required fields use a consistent label asterisk and the existing validation rules.
One explanation appears at the start of each relevant form:

- HU: A *-gal jelölt mezők kitöltése kötelező.
- EN: Fields marked with * are required.

PmsField and PmsSelect associate their accessible input name with the visible label
and required status. PmsForm adds the explanation without changing submission or
validation. The guest website has associated labels, native required attributes,
aria-required and a single bilingual explanation. Optional fields remain optional.
Existing public required identity fields are checked before submission; errors focus
the missing field and mark it invalid. Scanner input may remain incomplete until
confirmation. No new identity requirements or government-reporting assumptions.

## Forms audited and updated

| Form/interface | Required indicators and scope |
|---|---|
| Login | Account email and password; localized explanation. |
| Reservation creation/editing | Property, guest name, arrival, departure, guest count. Source remains optional because the backend defaults blank to Direct. Room type remains optional because the backend supports default-room resolution. Arrival time, value, reference, preparation and returning-profile selection remain optional. |
| Guest web/manual identity entry | Full name, birth date, nationality, document number and document type. Auto-detect remains a valid document-type choice. Birth name/place, sex, mother's name and address remain optional under the actual endpoint rules. All labels associated with controls, including optional ones. |
| Staff creation/editing | Full name and email. Role is marked when editable; an operator's own fixed role is unmarked. Optional phone/job title unchanged; generated credentials are read-only. |
| Property configuration | Room-type name, units and capacity. Optional room code unmarked. Other property summary fields are read-only. |
| Rate-plan creation | Room selection and name. Code, meal, cancellation policy and blank-valid base rate remain optional. |
| Channel inventory mapping | Channex property and every active room/rate mapping, matching the existing Save check. |
| Distribution/base-price publishing | Dates, rate-plan selection and base nightly price for publishing. Blank-valid range prices, availability and restriction updates remain unmarked. Base-price validation stays with its publish action, so it does not newly block unrelated date-range changes. |
| Integration slot | Property is required by the existing UI Save gate; provider selection marked. Connection type remains blank-valid. |
| Cleaning creation/assignment | Creation title, date and property. Reassigning existing work permits Unassigned and has no required-field explanation. |
| Maintenance report | Property and issue title. Optional details unchanged; default severity is not falsely marked mandatory. |
| Supplies | Quantity, matching its existing finite-number validator. |
| Guest preferences | Key and value, matching existing validators. |
| Reception manual inbox | Message body required; sender/contact/subject, source fallback and automatic property/reservation association remain optional. |
| Internal reservation notes | Note required when invoking Add note; one local explanation. |
| Shared text dialogs | Required marker/explanation follow the existing required boolean, including its optional mode. |
| Sandbox fictional booking/iCal | Existing mandatory booking name/dates/count and nonempty iCal import input marked. Optional external reference remains optional. |
| Identity-review controls | Verification method marked only while an editable review exists; review note remains optional. |
| Settings/knowledge/cancellation/draft/search/AI interfaces | Audited: blank knowledge entries, cancellation reason, drafts, filters, searches and idle composers are not falsely marked mandatory. Language/authority/status controls with valid existing defaults are settings rather than incomplete required-input forms. Read-only records and historical identity data remain unmarked. |

Conditional indicators rebuild with the caller's current required state. This
covers optional shared dialogs, cleaning creation versus reassignment, staff self
role, and availability of identity-review controls. No extra mandatory fields were
introduced to match an asterisk.

## Navigation audit and new patterns

PmsSectionPicker is a shared responsive component. It measures localized labels at
the active text scale. Up to five destinations use equal-width segments only when
every label fits at its natural size with comfortable padding and >=48px targets.
Otherwise one prominent current-section control opens a compact bottom sheet.
All destinations are directly listed, with the selected one highlighted yellow and
checked. Long labels wrap. A long destination list can scroll vertically inside the
picker; users no longer scroll sideways to discover sections. Escape/Back/dismissal
do not change selection. Existing caller-owned section indices/callbacks remain.

Updated navigation:

- Reservation details: Stay overview, Preparation, Communication, Activity.
- Reception: Inbox, scheduled messages and automations, including counts/draft state.
- Team: management, workload and access/roles.
- Knowledge: shared/property scope, including arbitrary property names and existing
  unsaved-change confirmation.
- Operational desk: all existing destinations/counts, preserving busy-state actions.
- AI suggestions: one Try asking picker; selection fills the existing composer.
- Settings: two-column destination tiles replace the tall grouped list. Roles still
  determine visible destinations; current-section highlight and square vector icons
  remain. Sign-out and language stay directly available.

The former PmsTabs scrolling strip now delegates to the new component; obsolete
scroll arrows disappear from these section menus. Existing desktop primary sidebar,
mobile main navigation and roomy page actions were retained. AI metric cards still
use the existing horizontal data carousel: they are data, not hidden destinations.
Necessary vertical content scrolling retains its dedicated scrollbar.

Styling reuses Delvane's white/black/yellow tokens, restrained translucent surfaces
and rounded corners. No additional blur or decorative shadows were added. Native
keyboard activation, selected semantics, SafeArea and reduced-motion sheet settings
are supported. Selection survives presentation changes and resizing.

## Validation

- Flutter analysis: no issues.
- Complete Flutter suite: 256 passed (249 existing plus 7 new).
- New tests cover required/optional/conditional indicators, HU/EN explanations,
  280/320/393/1440 widths, section switching, selected semantics, dismissal/resize,
  large text and picker reachability.
- Existing regression tests now follow the visible responsive picker or segments;
  checks for role restrictions, draft preservation, identity-review permissions,
  mutation payloads and protected navigation remain intact.
- Guarded JavaScript: 10 files passed, including new executed form-render checks for
  required and optional controls, web semantics and bilingual copy, plus existing
  localization/OCR/MRZ regressions.
- Isolated backend regression: 60 passed, 2 existing deprecation warnings. Covers
  guest registration, reservation validation, identity review, permissions and
  persistent-data compatibility. No backend rule was changed.
- Phone form/details/section-picker rendered with installed fonts and inspected.
  These are widget previews, not a physical-device or live-browser test.
- Android debug APK: built successfully. Windows release bundle: built successfully.
- Final git diff --check: passed.

Intermediate checks exposed stale test assumptions about exact labels/always-visible
tabs, a missing web-render test fixture, and a semantics assertion for the collapsed
selector. Those were corrected and the full suite rerun. An initial screenshot
capture stalled and was rerun with proper asynchronous image capture and phone
viewport configuration. No exceptions were suppressed. Existing Kotlin migration
and Starlette/AnyIO warnings remain.

## Backend, data and compatibility

No new backend/API/schema changes or migrations in this follow-up. Existing
migration 3072 and persistent launcher remain unchanged. No reset is required.
Flutter 3.50.0 / Dart 3.14.0, authentication, CSRF, package/application identities,
Windows/Android connection behavior and local/staging/production isolation retained.
Only fictional guarded test data used. No production/staging data, credentials,
services or infrastructure accessed. No commits or pushes made by this task.
The earlier acceptance work was saved externally in commit 0eb6831 (Save) during
this session; it was preserved. Current follow-up edits remain uncommitted.

## Run the updated application

Stop the existing backend with Ctrl+C before restarting. From PowerShell:

```powershell
Set-Location C:\Delvane\Delvane-Development
.\.venv\Scripts\python -B run_persistent_development_workspace.py
```

Normal startup preserves existing fictional acceptance data and accounts. Storage:
C:\Delvane\Delvane-Development\.development\persistent\workspace.db with its
matching workspace.json identity/key. Keep the backend terminal open.

In a second terminal, connect the Xiaomi by USB and authorize USB debugging:

```powershell
Set-Location C:\Delvane\Delvane-Development
powershell -NoProfile -ExecutionPolicy Bypass -File .\apps\delvane_business\tool\connect_android.ps1 -Install
```

The helper reinstalls with adb install -r; do not uninstall the application.
With multiple authorized devices, add -DeviceId SERIAL. Reapply the helper after
USB reconnection. This task did not install on or test a physical phone.

Android artifact: apps\delvane_business\build\app\outputs\flutter-apk\app-debug.apk.
Windows uses the entire release directory (including adjacent DLLs and data):

```powershell
Set-Location C:\Delvane\Delvane-Development
& .\apps\delvane_business\build\windows-vs2026\x64\runner\Release\delvane_business.exe
```

## Remaining manual verification

Check actual Xiaomi/Windows touch, keyboard, Back/Escape and TalkBack/Narrator;
large-text and landscape layouts; keyboard-open form scrolling; HU/EN language
switching while guest values are entered; camera/scanning, focused validation and
browser-native date/permission UI. Check Settings tiles and section switching keep
existing edits/drafts. A large property list still scrolls vertically in one picker.
Apple builds and physical GPU/performance checks were not performed. The previously
reported staff-editor flash was not reproduced by this task; prior manual recheck
remains applicable. NTAK/VIZA transport is outside this interface-only follow-up.

Guest web verification here used guarded JavaScript and backend tests, not live
browser automation. No browser-origin permission bypass was attempted.

A complete changed-file manifest accompanies this report. Relevant areas are shared
PMS style/form controls and the new section picker; form call sites; Settings/desk/AI
navigation; native Hungarian strings and login; guest HTML/CSS/JS/localization; and
Flutter/web regression tests. PORT_STATUS.md carries a focused summary. Logs are in
apps/delvane_business/build/form-nav-*.txt.