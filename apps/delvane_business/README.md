# Delvane Business

An offline Flutter preview of Delvane's hospitality workspace. Targets Windows
first, with Android, iOS, and macOS runners in this same repository.

## Run and validate

Use Flutter 3.32.2 / Dart 3.8.1. From this directory:

```powershell
flutter --no-version-check pub get
flutter --no-version-check analyze
flutter --no-version-check test
.\tool\build_windows.ps1
```

### Windows / Visual Studio 2026 compatibility

Flutter 3.32.2's Doctor accepts VS 2026, but its Windows builder only recognizes
VS 2019/2022 generator names. A direct `flutter build windows --release` selects
`Visual Studio 16 2019` and fails on this VS-2026-only host. The script above first
tries that standard command (preparing Flutter's generated configuration), then
handles only this known generator mismatch using installed VS 2026 CMake/MSBuild
and Flutter's normal assemble/install targets. Other build errors still fail.
No Flutter SDK or system installation is modified. The fallback uses a separate
ignored build directory, so it never deletes or reuses the old generator's cache.

Verified release bundle on this machine:

```text
build/windows-vs2026/x64/runner/Release/
  delvane_business.exe
  flutter_windows.dll
  data/
```

Open `delvane_business.exe` in that folder to use the offline preview. On a
compatible Flutter/Visual Studio pair, the standard `flutter run -d windows` and
`flutter build windows --release` commands work normally, and the script returns
after the standard build. Their usual output is `build/windows/x64/runner/Release`.

Keep `pubspec.lock` in Git for reproducible dependency resolution. No runtime
packages beyond the Flutter SDK are used; `flutter_lints` is a dev dependency.
The generated build directory is ignored. Distribute the entire release bundle,
including DLLs and `data/`, rather than the executable alone.

iOS/macOS builds require a Mac with Xcode and the corresponding Flutter setup.
Their runners are generated here but cannot be validated on Windows. Android
device/emulator verification and store signing are later development steps.

### Validation of this initial version

- `flutter analyze`: no issues.
- `flutter test`: 19 passed, none failed or skipped.
- All seven screens checked at seven phone/tablet/desktop viewport sizes,
  including short landscape windows; navigation switches to a drawer when needed.
- Fake-transport API tests cover HTTPS/origin/path validation, status errors,
  malformed JSON, timeouts, injected session headers, and native integer precision.
- Interaction tests cover reservation search/details, mobile navigation, local
  drafts, scripted AI, settings, and shared session state.
- Desktop/mobile raster previews are regenerated under ignored `build/previews/`.
- Windows x64 Release bundle built successfully through the compatibility script
  with MSVC 19.52 and the installed Windows SDK. Native launch/device smoke testing,
  other platform builds, store signing, and deployment are not claimed by these checks.

## Mock-mode boundary

Every screen displays a demo notice. All names, properties, reservations, values,
messages, chart values, task assignments, and notifications are synthetic.
The illustrative workspace date is 11 November 2026. Occupied-unit totals and
the reservation list are separate sample datasets, not a reconciliation report.

- Reservations: search, status filters and read-only detail previews.
- Reception: select conversations and save drafts in memory; no send operation.
- Properties: illustrative readiness/occupancy and read-only previews.
- Operations: local task completion, shared with the dashboard.
- AI: explicitly scripted mock answers; no model, tools, or autonomous actions.
- Settings: in-memory preview preferences; no authentication or real delivery.

The app does not open backend files, read SQLite, contact the FastAPI server,
invoke integrations, send guest messages, or persist guest information. Drafts,
task completion and preferences reset on restart. There is no hidden live-mode
flag. No API client is instantiated by the mock app.

## Structure

```text
lib/
  app/                  composition, controller, navigation and theme
  core/network/         injectable native HTTP transport and safe API errors
  domain/               immutable models and repository interface
  data/                 synthetic repository implementation
  features/             dashboard, reservations, reception, properties,
                        operations, AI and settings screens
  shared/               responsive shell and reusable visual components
test/                   responsive/widget, local-state and API-contract tests
windows/ android/ ios/ macos/   native platform runners
```

`BusinessRepository` isolates presentation from data access. `BusinessController`
owns session-only UI state with Flutter's ChangeNotifier, without a third-party
state-management dependency. Desktop uses a sidebar, medium windows a navigation
rail, and mobile a drawer plus bottom navigation. Theme tokens live in one file.

`ApiClient` accepts an injected transport and future session-header provider.
It handles JSON collections/maps, request timeouts and sanitized errors, requires
HTTPS by default, and rejects cross-origin request paths. HTTP loopback is an
explicit development-only opt-in. API tests use fake transports, never sockets.

Before connecting to FastAPI, implement a remote repository and documented DTO
mapping, then design authentication/session storage and per-session CSRF handling.
The preserved backend uses HttpOnly sessions and `X-Rosa-CSRF`; this foundation
does not pretend a bearer-token login, secure credential storage, refresh flow,
or production integration already exists. Do not put secrets in source or
`--dart-define` values. Keep sensitive registration documents outside generic
operational state. No backend modification is needed for this preview.

## Product scope

This is an initial working client, not a production PMS replacement. Browser
camera/identity scanning, government reporting, invoicing, channel management,
offline synchronization, real AI, account onboarding, and deployment remain
backend/integration work. Native app icons and signing remain release work.
