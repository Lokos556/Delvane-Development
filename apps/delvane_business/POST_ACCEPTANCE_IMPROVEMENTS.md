# Delvane AI — post-acceptance improvements

14 November 2026. Repository: `C:\Delvane\Delvane-Development`.
Started on a clean `main` already two commits ahead of `origin/main`; no commit or
push was made by this task. Flutter 3.50.0 / Dart 3.14.0 and existing environment,
authentication, CSRF, application identifiers and persistent local storage remain.

## Results for the 14 requested improvements

| # | Improvement | Implementation and acceptance boundary |
|---|---|---|
| 1 | Mobile New Reservation | Uses the full-size shared primary button instead of its compact variant. Its touch target is at least 48px in the phone test; the responsive header still wraps without overlap. Desktop uses the existing proportioned primary treatment. |
| 2 | Precise reservation errors | FastAPI emits stable error codes/field identifiers for availability conflicts, date errors, required fields, invalid guest counts, capacity, unavailable property/room/profile, missing reservations and identity-review restrictions. No conflicting guest name/date details are disclosed. Flutter preserves these codes, maps them to Hungarian/English and shows field context for name/count errors. Existing auth, permission, timeout and connection messages remain safe; server failures advise refreshing before retrying. The existing browser PMS understands structured errors too. No unsupported “booking locked” state or distinction between full inventory and overlap was invented. |
| 3 | Sex selection | Only Male/Female and the empty Select state are visible. Unsupported/unknown OCR values do not add a new visible option or become M/F automatically. Empty and legacy internal X values remain representable; no historical record conversion or government mapping was fabricated. |
| 4 | Nationality order/search | Magyar/Hungarian appears first, with all original distinct nationalities retained, localized region labels, locale sorting and a search field. Canonical stored/scanner values stay unchanged. Reordering explicitly preserves the selected value, including empty; Hungarian is never selected merely because the language is Hungarian. |
| 5 | Birth-date bounds | Native date input uses 1920-01-01 through the current browser-local day; backend submission checks valid calendar dates from 1920-01-01 through the backend-local current day. Partial/invalid scanner dates remain incomplete rather than verified. A localized date-range error is supplied. Reservation date/timezone semantics were not changed. |
| 6 | Guest-flow language | Visible accessible Hungarian/English selector, Hungarian default for a new session, explicit choice retained in tab session storage. Shared text localization covers loading/form, document/camera instructions, capture/back/flash controls, scanner progress/failures, validation, link errors and the final success state. Switching language preserves input/camera state instead of rebuilding the form. Dates and country labels follow the selected language. Raw OCR/document text and guest/property values remain data; browser-owned permission dialogs/date-picker chrome follow the browser/OS language. |
| 7 | Active Settings item | Current `PmsController.page` drives a restrained yellow selected surface, checkmark and selected accessibility semantics when the settings panel opens. It follows existing native navigation state; no separate browser-history router was introduced. |
| 8 | Scroll discovery | Measured horizontal overflow produces forward/back controls that disappear at the corresponding edge and do not appear when content fits. Tabs, Intelligence context selectors and desk selectors reuse it. Touch, wheel and keyboard controls remain available; reduced motion uses immediate scrolling. Dialogs, settings panels, Reception panes and the operational desk use dedicated vertical scrollbar controllers. Page scrolling is kept separate. |
| 9 | Returning-guest/cancellation history | Existing guest profiles/history were extended. New reservations/imports get separate profiles rather than name-only merging. Owners/managers can explicitly link a returning profile by tenant-scoped ID from the booking editor. Summary counts include only explicit associations; host cancellations are separate from guest cancellations, and unknown remains unknown. Dates, locally recorded cancellation time, source and available reason are retained. Direct cancellation asks for initiator/reason; normalized channel metadata is preserved only when explicitly provided. Existing sync/ARI/outbox paths remain. **The backend has no physical completed-stay/no-show state:** it displays past confirmed reservations with an explanation and does not invent completion or no-show evidence. |
| 10 | Staff-account closing flash | Parent reload now waits for the dialog route’s reverse transition/disposal to finish. Closing a focused staff form is covered by a regression test checking subsequent frames for exceptions. **The original red/yellow flash did not reproduce before the change**, so its precise original cause is not proven. This lifecycle improvement is implemented, but the reported device symptom requires another Windows/Xiaomi check and the actual exception text if it returns. No ErrorWidget/exception suppression was added. |
| 11 | Cleaner sign-out | Main-menu sign-out uses the normal-size shared control; the phone test checks at least 48px and verifies that tapping it clears the same authenticated session. No role permissions changed. |
| 12 | Date-first reservation details | Check-in/checkout lead the detail content in 22px mobile/32px desktop type, with localized dates including year. Guest-name title uses 18px mobile/22px desktop; property and status remain visible. Tabs were moved before secondary metrics so they remain reachable in short windows. Layout tests cover 320px, 393px and 1440px widths and a long guest name. |
| 13 | Liquid-glass refinement | Reuses the existing shared glass/card tokens for small tab surfaces alongside the existing modal/navigation treatment. It is not applied to every card. Blur is disabled for reduced-motion/accessibility navigation settings; overflow animations also respect reduced motion. Contrast and the existing white/black/yellow identity are retained. Real Xiaomi/Windows GPU performance was not measured. |
| 14 | Delvane AI branding | Android label, Windows window/resource product names, Flutter display titles and iOS/macOS display/product names now say Delvane AI. Android, Windows, iOS and macOS icons and applicable splash assets are derived from the existing official `assets/delvane-icon.png`; no replacement logo was invented. iOS app-icon exports are RGB without alpha. Android/Windows builds verify their platform changes; Apple compilation/signing remains untested on this Windows host. App/package/bundle IDs, signing settings, Windows executable basename and session storage keys are preserved. |

## Backend/API and migration

Automatic additive migration **3072** (`guest_history_cancellation_provenance`):

- `reservations`: `cancelled_at`, `cancellation_initiator` (default `unknown`),
  `cancellation_reason`, `cancellation_source`.
- `guest_reservations`: `association_source`, default `legacy_unverified` for
  existing rows. Old cancellation times are backfilled only where an actual
  stored cancellation event supplies one; otherwise they remain missing.
- No destructive data replacement, name-based deduplication or operational DB
  conversion. The migration is idempotent and tested against the former schema.

Start/restart the existing persistent launcher normally; its existing initialization
applies the migration. **No reset command is needed.** For a retained acceptance
workspace, keep a stopped snapshot of the whole `.development\persistent` folder
(database plus its matching `workspace.json` key) before upgrading.

`POST/PATCH /api/reservations` accepts optional `guest_id`. It must identify a
profile in the operator’s organization; this is an explicit association, not
automatic identity verification. Primary relinking preserves secondary guest
associations. Existing reservation-only associations for that known profile can
be confirmed; legacy name-derived groups are not automatically trusted. Review
older reservations individually before linking them. Imported bookings without
a reliable guest identifier remain separate profiles.

`DELETE /api/reservations/{id}` still works without a body and records unknown
initiator. Optional JSON: `{"initiator":"guest|host|platform_system|unknown",
"reason":"..."}`. Known initiator/reason evidence is not erased by an empty retry.
Cancellation source and locally recorded timestamps are not asserted to be an
OTA’s original event time. Unknown channel provenance stays unknown; existing
normalized payloads may provide explicit `cancellation_initiator` and
`cancellation_reason` fields. No new Channex credentials or provider calls were used.

Guest-history/detail responses now carry `history_summary` and cancellation
metadata. Only owner/manager roles can view them. Identity-document numbers/images
are not added to history. No automatic accusation, score, penalty or financial
action is attached to cancellation history.

Structured reservation error codes include `availability_conflict`,
`invalid_dates`, `departure_not_after_arrival`, `guest_name_required`,
`invalid_guest_count`, `capacity_exceeded`, `property_unavailable`,
`room_unavailable`, `reservation_not_found`, `guest_profile_unavailable`,
`guest_records_review_required`, `registration_review_required` and
`invalid_fields`. Invalid request values are not echoed in structured validation
responses. Public birth-date validation uses `invalid_birth_date`.

## Validation

Final verification completed successfully. Results:

- Flutter static analysis: **no issues**. Full Flutter suite: **249 passed**; final scrolling-focused suite: **19 passed** after the last adjustment.
- Android debug APK and Windows release bundle: **built successfully**.
  APK: `apps/delvane_business/build/app/outputs/flutter-apk/app-debug.apk`.
  Windows: `apps/delvane_business/build/windows-vs2026/x64/runner/Release/`.
- Broader guarded backend regression run: **143 passed**.
- Later focused backend run: **37 passed**. Cases cover migration from the old schema, cancellation
  retries, preservation of secondary associations and identity-review errors;
  these overlap the broader run and must not be added as wholly separate coverage.
- Independent-process persistent/disposable restart proof: **passed**, preserving
  reservation details, guests, encrypted data, staff, assignments, sessions and
  workspace identity; disposable cleanup remains intact.
- **10 guarded JavaScript test files passed**, including all existing MRZ/OCR
  parser regressions and new language/country/date/privacy contracts.
- Android helper PowerShell parsing, `git diff --check` and iOS marketing-icon
  RGB/no-alpha checks passed.
- Logs are under the app's ignored `build/`: `post-acceptance-analysis.txt`,
  `post-acceptance-flutter-tests.txt`, `post-acceptance-backend-final.txt`,
  `post-acceptance-focused-final.txt`, `post-acceptance-js.txt`,
  `post-acceptance-persistence.txt`, `post-acceptance-android.txt`, and
  `post-acceptance-windows.txt`.

Intermediate checks caught and corrected a stale English HTML assertion, direct
dialog date-format initialization, tabs pushed off short windows, reduced-motion
scrolling/type handling, and the JavaScript runner’s obsolete permission flag on
Node 24. The runner now selects the supported permission flag while retaining its
filesystem/process/network guards. Existing Kotlin migration and Starlette/AnyIO
deprecation warnings remain. Final failures/remaining verification limits are
listed below; interim failures were not hidden or counted as passing.

## Start and install

Stop the running acceptance backend with Ctrl+C first, then:

```powershell
Set-Location C:\Delvane\Delvane-Development
.\.venv\Scripts\python -B run_persistent_development_workspace.py
```

Use the existing development accounts/password. The persistent workspace and its
records are retained; normal migrations run. First-ever setup still prompts for a
fictional-account password. Keep the backend terminal open.

In another terminal, with the Xiaomi connected and USB debugging authorized:

```powershell
Set-Location C:\Delvane\Delvane-Development
powershell -NoProfile -ExecutionPolicy Bypass -File .\apps\delvane_business\tool\connect_android.ps1 -Install
```

The helper uses `adb install -r`; do not uninstall the app to refresh its icon.
Reapply the helper after USB reconnects. With several authorized devices, add
`-DeviceId SERIAL`. This task did not install the APK or access a physical device.

Windows uses the complete release bundle:

```powershell
Set-Location C:\Delvane\Delvane-Development
& .\apps\delvane_business\build\windows-vs2026\x64\runner\Release\delvane_business.exe
```

Keep its adjacent DLLs and `data/` folder. The executable basename intentionally
remains unchanged for compatibility; the visible title/product branding is
Delvane AI. Existing pinned shortcut names/icon caches may need a shell refresh.

## Manual verification and remaining limits

1. Recheck staff-account X/Back with a focused field on Windows and Xiaomi, in
   debug and release if possible. If the red flash returns, capture the actual
   Flutter exception text. The automated reproducer did not establish the original
   cause; a physical fix claim would be premature.
2. Verify Hungarian/English guest registration from a new session through manual
   entry, front/back scanning, validation, expired links and success. Switch
   language after entering data and confirm it stays intact. Check a blank
   nationality remains blank and unknown sex is not fabricated. Browser-native
   camera permissions/calendar UI follow browser/OS localization.
3. Exercise same-name distinct guests, explicit returning-profile links and guest,
   host and unknown cancellations. Confirm host/unknown cancellations do not enter
   the guest-cancellation count. Review legacy associations before trusting them.
4. Check date hierarchy and internal scroll indicators with large text, reduced
   motion, keyboard/Back and narrow/landscape windows. Check menu selected state
   when revisiting Settings sections and sign-out session clearing for workers.
5. Check updated label/icon/splash and retained app data after Android `-r` install.
   Test actual frosted-surface GPU performance on Xiaomi and Windows. Apple build,
   signing and device validation remain for a Mac.

The existing backend does not provide verified physical stay completion or
no-show records. Past confirmed reservations are displayed honestly; those new
business lifecycle states were not invented. Certified NTAK/VIZA transport remains
outside this task. No real identity, production/staging database, production
Channex/NTAK/VIZA service, credentials or infrastructure was accessed or modified.

The browser approval gate rejected opening the temporary localhost guest preview
because access to that origin was declined. No alternate browser path was used.
Browser inspection and physical-device acceptance therefore remain manual.

## Changed files

Backend/domain: `app.py` (structured errors, birth-date checks, migration,
explicit profile association and cancellation history).

Guest website: `static/guest-checkin.html`, `guest-checkin.css`,
`guest-checkin.js`; new `static/guest-checkin-i18n.js`. `static/app.js` retains
compatibility with structured reservation errors in the existing browser PMS.

Flutter networking/shared UX: `lib/core/network/api_client.dart`;
`lib/features/pms/pms_workflows.dart`, `pms_dialogs.dart`, `pms_controller.dart`,
`pms_style.dart`, `pms_shell.dart`, `reservation_dialogs.dart`,
`guest_history_dialog.dart`, `team_page.dart`, `reception_page.dart`,
`operational_desk.dart`, `intelligence_workspace.dart`; new
`cancellation_dialog.dart`, `guest_link_picker.dart`, `overflow_row.dart`.

Copy/branding: `assets/native-hu.json`, `lib/app/app.dart`,
`lib/features/workspace/login_page.dart`, `lib/features/settings/settings_page.dart`;
Android manifest, launcher PNGs and launch backgrounds plus new splash PNG;
Windows `runner/main.cpp`, `Runner.rc`, `resources/app_icon.ico`; iOS Info.plist,
AppIcon PNGs and LaunchImage PNGs; macOS AppInfo.xcconfig and AppIcon PNGs;
`tool/connect_android.ps1` console branding. No app/bundle/package/signing identity
or dependency/toolchain version changed.

Tests: new `tests/test_post_acceptance.py`, `tests/test_guest_registration_ui.js`,
`test/post_acceptance_test.dart`, `test/staff_close_regression_test.dart`;
updated `tests/test_guest_checkin.py`, `tests/test_v21094_name_retry.js` and
`run_js_tests.py`. Documentation: this focused report and `PORT_STATUS.md`.
