# API environments and future iOS/staging testing

Prepared 2026-11-14. Flutter **3.50.0**, Dart **3.14.0**. Nothing in this document
has deployed a server, opened a firewall, connected to a remote PMS, created a
database or purchased a service/account.

## Configuration contract

The same application and FastAPI backend serve all three environments. There are
no new platform projects, runtime URL selectors or alternative authentication
systems. Configure these **public build-time values** using Flutter Dart defines:

| Define | Values/default | Purpose |
|---|---|---|
| `DELVANE_ENV` | `local` (default), `staging`, `production` | Selects URL/session/environment policy |
| `DELVANE_API_ORIGIN` | `http://127.0.0.1:8765` only when local | Backend origin, without `/api`, user info, query or fragment |

`ApiConfiguration` is the sole source of defaults. Local mode accepts loopback
development origins. Staging/production require an explicitly supplied **HTTPS**
origin and reject loopback destinations, credentials in URLs and path prefixes.
Unknown environment names, missing remote URLs and invalid origins fail closed;
there is no fallback to localhost or demo data. Normal builds retain the current UI.
Remote login uses wording that does not claim its data is a disposable local workspace.

Use either a JSON file or explicit CLI defines. These are compiler inputs, not
ordinary OS environment variables. Never put passwords, database URLs, encryption
keys, provider tokens or certificates in Dart defines: compiled app configuration
is extractable. The reviewed files in `config/` contain only environment/URL values.
The example remote hostnames use `.invalid`; replace them with actual staging
origins **only when a staging service exists**. They are not running services.

## Current architecture audit

- Previously `app/app.dart` read one `DELVANE_API_ORIGIN` define with the local
  default. That composition now consumes `core/network/api_configuration.dart`.
- All native operational repositories receive the authenticated shared `ApiClient`.
  Its native `HttpClient` retains 15-second connection and 20-second request
  timeouts, an 8 MiB response limit, safe errors, same-origin `/api/` path checks,
  per-session CSRF headers and explicit cookie handling. Redirects remain disabled.
  Mutations are not automatically replayed after errors/timeouts.
- TLS certificate validation uses the platform/Dart trust implementation. There is
  no `badCertificateCallback`, custom trust-all transport or remote HTTP exception.
  No request/response bodies, passwords or guest details are added to logs.
- Backend login, `/api/me`, session expiration, logout and server role checks are
  unchanged. Passwords are never persisted. Secure session storage remains the
  existing platform credential store/Keychain/Android encrypted storage.
- The local guard `/api/development/workspace` remains required before local login
  or restore. This endpoint is still supplied only by the isolated launcher.
- Remote login/restore first requests the new public **GET `/api/client/environment`**
  without a cookie or CSRF token. It must match the selected environment, advertise
  secure cookies and supply a valid deployment ID. Remote login rejects non-Secure
  session cookies. This does not bypass backend authentication or permissions.
- Local session storage keys are unchanged. Remote keys additionally include
  `staging`/`production` and the origin. Stored sessions bind to deployment ID and
  origin, and restoration still revalidates `/api/me`. The UI language preference
  remains shared deliberately; it contains no credential or guest data.

The environment handshake prevents accidentally signing a staging build into an
advertised production server. It is **not** proof that an operator configured a
separate database, and it is not authorization or tenant isolation. A deployment ID
change discards old client credentials on restore; it does not revoke server-side
sessions by itself.

## Existing local Windows and Android USB workflow

No arguments are required to retain the current workflow. From the repository root:

```powershell
.\.venv\Scripts\python.exe -B run_development_workspace.py
```

Keep the isolated server terminal open and enter a disposable password at its
prompt. The launcher still owns temporary synthetic data, blocks outbound services
and binds only `127.0.0.1:8765`. Do not substitute an ordinary app launcher or an
operational database.

From `apps/delvane_business`, build Windows using the existing VS2026 helper:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tool\build_windows.ps1
.\build\windows-vs2026\x64\runner\Release\delvane_business.exe
```

For an authorized USB Android device, retain the existing guarded helper:

```powershell
flutter build apk --debug
.\tool\connect_android.ps1 -Install
```

That helper checks the local isolation marker and configures `adb reverse
tcp:8765 tcp:8765`. It does not expose the API on the LAN or internet. The explicit
equivalent build configuration is `--dart-define-from-file=config/local.json`.
Existing local `--dart-define=DELVANE_API_ORIGIN=http://127.0.0.1:<port>` overrides
still work. Profile/release Android retains its existing cleartext prohibition;
USB loopback HTTP is a **debug-only** exception, unchanged by this work.

## Future staging backend: required operator work

No staging endpoint has been contacted or configured. Before future deployment:

1. Allocate a dedicated staging installation and PostgreSQL database, with separate
   database users, user accounts, encryption keys, storage/data directory and
   provider configuration. Do not copy operational guest data or production `.env`
   files. Review the existing app's local-env loading/adoption paths before startup;
   do not mount an operational checkout, database or desktop configuration directory.
2. Supply server-side settings through a deployment secret manager/environment.
   Keep secrets out of this repository and the Flutter config. The existing backend
   has no `ROSA_APP_ENV=staging`: staging uses **production runtime hardening** with
   a distinct deployment role and resources:

   ```text
   ROSA_APP_ENV=production
   ROSA_DEPLOYMENT_ENVIRONMENT=staging
   ROSA_DEPLOYMENT_ID=<stable-public-staging-id-8-to-128-letters-digits-dashes-underscores>
   ROSA_DATABASE_URL=<dedicated-staging-PostgreSQL-connection-secret>
   ROSA_DATA_DIR=<dedicated-staging-data-directory>
   ROSA_SECURE_COOKIES=1
   ROSA_DEMO_MODE=0
   ROSA_ENCRYPTION_KEY=<separate-staging-Fernet-key>
   ROSA_AI_PROVIDER=local
   ```

   This is a configuration checklist, not an active env file or startup command.
   Existing startup validation still requires PostgreSQL, secure cookies, disabled
   demo mode and a valid encryption key. Provider workers/integrations retain their
   existing behavior: leave real provider credentials absent and review any existing
   outbox before starting a staging service. No integration is enabled by this work.
3. Terminate HTTPS with a valid, publicly trusted certificate/full chain at a DNS
   name usable by test devices. Keep the backend private behind its TLS ingress;
   restrict forwarded-header trust to the actual ingress. Do not disable certificate
   validation or broaden Android/iOS HTTP policies to make a certificate work.
4. Configure `ROSA_DEPLOYMENT_ID` as a stable **non-secret** installation identifier,
   separate for staging and production. It is intentionally visible before login.
   The new endpoint returns exactly:

   ```json
   {"environment":"staging","deployment_id":"public-stage-001","secure_cookies":true}
   ```

   Unconfigured deployments return 404. Invalid/unsafe metadata configuration returns
   503 with a fixed message; no database path, provider secret or account is exposed.
   Browser PMS behavior and the local development marker do not change.
5. Verify the endpoint, Secure/HttpOnly session cookie, CSRF, login, role restrictions,
   session expiry/logout and database isolation against disposable staging records.
   Native clients do not need browser CORS relaxations. Only then configure and
   install a staging build. Production uses the same process with separate resources
   and `ROSA_DEPLOYMENT_ENVIRONMENT=production`.

## Permanent Android UAT release

Run `powershell -NoProfile -ExecutionPolicy Bypass -File .\tool\build_android_uat.ps1`
from the Flutter app directory. The ARM64 release uses the local debug signer for
UAT and connects directly to `https://api.delvane.app` over HTTPS. The named APK is
`build/app/outputs/flutter-apk/delvane-business-uat-v2-arm64.apk`. It can be opened on
the Xiaomi through Files or installed with `adb install -r` over USB. USB reverse
forwarding is unnecessary. Only the authenticated session is stored. Passwords
and integration secrets stay out of the APK.

Verify sign-in, relaunch, Wi-Fi to mobile data recovery, Reception back navigation,
guest profiles and role-specific operations using UAT accounts. Camera access is
requested by the browser on the existing guest registration link. The native
workspace can review the submitted scan data. Native push and App Links are
inactive. Future external notification or link intents should pass through the
same authenticated navigator and server authorization before opening a record.

## Build against another staging origin

After replacing the placeholder origin in a reviewed copy of
`config/staging.example.json`, from the Flutter app directory:

```powershell
flutter build apk --debug --dart-define-from-file=config/staging.example.json
powershell -NoProfile -ExecutionPolicy Bypass -File .\tool\build_windows.ps1 -DartDefineFromFile config/staging.example.json
```

Or use explicit values, without creating another file:

```powershell
flutter build apk --debug --dart-define=DELVANE_ENV=staging --dart-define=DELVANE_API_ORIGIN=https://your-staging-host.example
```

The Windows helper forwards configuration through its normal Flutter invocation
and existing VS2026 CMake fallback. Copy the **whole** Windows Release bundle when
keeping different environment builds; builds share the usual output directories.
Do not mix DLL/data folders from different builds. Remote HTTPS testing does not
use `adb reverse`. Production requires explicit production defines; it never inherits
the local/staging URL. Production example config is not a working deployment.

## iOS preparation without a paid membership

The existing iOS project, iOS 15 target, scene lifecycle and secure-storage plugin
are retained. `Runner/Info.plist` has no ATS bypass; no platform changes were needed.
HTTPS configuration and the shared native transport apply identically on iOS.
Apple documents secure-network policy in
[Preventing insecure network connections](https://developer.apple.com/documentation/security/preventing-insecure-network-connections).

On a future Mac with Xcode/CocoaPods and the pinned Flutter SDK:

```sh
flutter pub get
flutter build ios --simulator --debug --dart-define-from-file=config/staging.example.json
flutter build ios --release --no-codesign --dart-define-from-file=config/staging.example.json
```

Simulator/unsigned compilation does not require purchasing Apple Developer Program
membership. An unsigned build is not an installable signed iPhone/TestFlight build.
Personal-device testing can use a free personal Apple developer account and Xcode
signing, subject to its limits; see Flutter's
[iOS setup guidance](https://docs.flutter.dev/platform-integration/ios/setup).
App Store/TestFlight distribution is a separate future signing/distribution task.
No Apple account, team, certificate, purchase or remote CI build was configured here.

A physical iPhone's `127.0.0.1` is the phone, not this Windows machine. Use the future
HTTPS staging origin rather than exposing the Windows development server or trying
to reuse Android's ADB forwarding. iOS compilation, signing and physical-device
networking cannot be validated on this Windows host and remain untested.

## Regression commands

```powershell
flutter analyze
flutter test
flutter test --dart-define-from-file=config/staging.example.json test/api_environment_test.dart --plain-name "actual build-time values"
flutter test --dart-define-from-file=config/production.example.json test/api_environment_test.dart --plain-name "actual build-time values"
flutter build apk --debug
powershell -NoProfile -ExecutionPolicy Bypass -File .\tool\build_windows.ps1
```

The two define-file tests only parse build configuration; their reserved hosts are
never contacted. Network/auth tests use an in-memory transport, not a real server.
Backend metadata/local-workspace tests run from the repository root under the
existing isolation guards:

```powershell
.\.venv\Scripts\python.exe -B -m pytest -q -p no:cacheprovider --capture=sys tests/test_client_environment.py tests/test_flutter_workspace.py tests/test_isolation.py
```

No deployment, HTTPS round-trip, actual staging/production database or iOS runtime
has been verified by these commands. Those are deliberate future acceptance steps.

## Validation results — 2026-11-14

- Flutter 3.50.0 / Dart 3.14.0 retained; no dependencies were installed or upgraded.
- `flutter analyze`: no issues.
- Full Flutter suite: **221 passed, 0 failed, 0 skipped**. The 13 environment tests
  cover local compatibility, invalid URLs, missing remote config, metadata mismatches,
  Secure cookies, cookie/CSRF authentication, deployment binding, restore/logout and
  environment-separated secure storage. Existing UI/Hungarian tests remain enabled.
- The actual staging and production define-file compilation checks each pass.
  These use only the configuration factory and never open a connection.
- Isolated Python suite above: **31 passed**, clean process exit. Existing FastAPI/
  Starlette deprecation warnings remain; no dependency changes were made.
- Android debug APK: built successfully at
  `build/app/outputs/flutter-apk/app-debug.apk` using default local API configuration.
- Windows release: built successfully with `-DartDefineFromFile config/local.json`
  through the VS2026 helper. The generated CMake environment was checked to contain
  `DELVANE_ENV=local` and `DELVANE_API_ORIGIN=http://127.0.0.1:8765`. Bundle:
  `build/windows-vs2026/x64/runner/Release/`.
- iOS plist parsed successfully, minimum iOS 15 retained, no ATS exceptions added.
  iOS compilation, signing, device tests and actual remote TLS remain unverified.

Validation also exposed two existing issues. The English `confidence` caption was
restored to its original lowercase spelling while retaining its Hungarian mapping;
one pre-existing test lint received braces. Windows pytest cleanup now unlinks only
its optional `current` symlink aliases inside the guarded temporary root, preventing
Python 3.14's WinError 145 without disabling any isolation/database/network guards.
Earlier test assertions passed but teardown failed; the final 31-test run exits zero.

The initial Android build hit a host JDK Unix-domain loopback-pipe error before
compilation. The installed JDK sources show that its selector pipes use `%TEMP%`.
Gradle succeeded when only the build process used an ignored, normal-path temporary
directory instead of the host's short-name temp path. No JDK, SDK, firewall, TLS,
Gradle project configuration or persistent OS environment setting was changed.
If this host issue recurs, from the app directory use this scoped workaround:

```powershell
$buildTemp = Join-Path (Get-Location).Path 'build\jvm-tmp'
New-Item -ItemType Directory -Path $buildTemp -Force | Out-Null
$previousTemp = $env:TEMP
$previousTmp = $env:TMP
try {
    $env:TEMP = $buildTemp
    $env:TMP = $buildTemp
    flutter build apk --debug
} finally {
    $env:TEMP = $previousTemp
    $env:TMP = $previousTmp
}
```

The existing Kotlin/Gradle deprecation warning remains. Validation logs live under
`build/api-environment-*.txt`; those generated logs are not tracked.

## Files changed for environment preparation

- `lib/core/network/api_configuration.dart`: environment parsing/URL policy.
- `lib/core/auth/auth_controller.dart`: remote metadata gate, cookie policy and
  environment-bound session storage; existing auth/roles remain authoritative.
- `lib/app/app.dart`, `lib/features/workspace/login_page.dart`,
  `assets/native-hu.json`: configuration wiring, safe configuration errors and an
  accurate remote login caption in both languages.
- `config/local.json`, `config/staging.example.json`,
  `config/production.example.json`: public build examples only.
- `tool/build_windows.ps1`: optional define-file forwarding, existing default retained.
- `test/api_environment_test.dart`, `../../tests/test_client_environment.py`:
  offline environment/auth contracts and isolated metadata endpoint tests.
- `../../app.py`, `../../client_environment.py`: one public metadata endpoint and
  configuration-only validation; no business routes, migrations or database changed.
- `../../conftest.py`: bounded Windows temporary-symlink cleanup described above.
- `lib/features/pms/administration_pages.dart`, `test/localization_followup_test.dart`:
  the two minimal pre-existing validation corrections described above.
- `API_ENVIRONMENTS.md`, `README.md`, `PORT_STATUS.md`, `ANDROID_TESTING.md`:
  configuration, launch/build instructions, evidence and limitations.

Pre-existing IDE/generated plugin-file changes were retained. No commit or push
was made. There is still only one application and one Git repository.
