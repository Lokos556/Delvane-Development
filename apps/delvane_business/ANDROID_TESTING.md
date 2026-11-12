# Android USB development testing

This is the same Flutter application and FastAPI backend as Windows. No LAN API,
production credentials or operational database is required. Use the debug APK for
local testing only. The default client API remains `http://127.0.0.1:8765`.

## Connect the Xiaomi 15

1. On the phone, enable Developer options and USB debugging. Xiaomi documents
   tapping **OS version** seven times to enable Developer options; menu labels vary
   by HyperOS build. Connect with a data-capable USB cable, unlock the phone and
   accept this computer's USB debugging authorization.
2. Verify that the phone appears as `device`, not `unauthorized` or `offline`:

   ```powershell
   & "$env:LOCALAPPDATA\Android\sdk\platform-tools\adb.exe" devices -l
   ```

   If nothing appears, check the cable/USB mode and Windows device driver. If
   HyperOS blocks installation, approve the installation on the unlocked phone and
   check its developer-option installation controls. Do not disable unrelated
   security settings or configure wireless debugging for this workflow.

## Start the isolated backend

In a Windows terminal:

```powershell
Set-Location C:\Delvane\Delvane-Development
.\.venv\Scripts\python -B run_development_workspace.py
```

Choose a disposable password of at least 12 characters at the hidden prompt. Keep
this terminal open. The launcher creates temporary SQLite data, blocks provider
networking and credential loading, and binds **only** `127.0.0.1:8765`. Do not use
`uvicorn app:app`, `0.0.0.0`, production launchers, firewall exceptions or a live DB.

## Install and open the debug APK

In a second terminal:

```powershell
Set-Location C:\Delvane\Delvane-Development\apps\delvane_business
flutter --no-version-check build apk --debug
powershell -NoProfile -ExecutionPolicy Bypass -File .\tool\connect_android.ps1 -Install
```

The helper selects one authorized device, checks the backend's isolated-workspace
marker, establishes `adb reverse tcp:8765 tcp:8765`, installs with `adb install -r`
and launches `com.delvane.delvane_business/.MainActivity`. With multiple authorized
devices, add `-DeviceId SERIAL`. It refuses to replace an existing different port
forward, never uninstalls/clears data and never starts an ordinary backend.

APK: `build\app\outputs\flutter-apk\app-debug.apk`.
An installed APK alone cannot reach the Windows backend: the USB connection,
running backend and reverse forwarding are required. There is no need to enter
the computer's Wi-Fi address. The identical loopback URL resolves through USB.

Sign in with `owner@workspace.invalid`, `manager@workspace.invalid`,
`cleaner@workspace.invalid` or `maintenance@workspace.invalid`, using the disposable
password from terminal 1. Never enter actual staff or guest data. Restarting the
backend discards test data and invalidates saved sessions. The app detects a
different workspace before restoring credentials; Reconnect and sign in again.

For hot reload after forwarding, use `flutter run -d SERIAL`. After a USB reconnect,
repeat the helper (without `-Install` if already installed). To remove this mapping:

```powershell
& "$env:LOCALAPPDATA\Android\sdk\platform-tools\adb.exe" -s SERIAL reverse --remove tcp:8765
```

## Security and build configuration

- Debug-only Network Security Configuration permits HTTP for exactly `127.0.0.1`
  and `localhost`; all other cleartext origins are denied. Profile/release do not
  contain this exception. No TLS checks are bypassed. The current Android release
  is not configured for the development HTTP connection or production distribution.
- Existing FastAPI session cookie, per-session CSRF, role enforcement, expiration,
  logout and isolated-workspace marker are unchanged. Android stores only session
  credentials through `flutter_secure_storage` encrypted preferences backed by
  Android Keystore; passwords and guest records are not persisted there. Backup is
  disabled and shared preferences are excluded from device transfer/cloud rules.
- Gradle 8.12 is used with existing AGP 8.7.3 / Kotlin 2.1.0 and JDK 17. Gradle
  9.7.1 failed compiling this Flutter 3.32.2 Gradle plugin; no Flutter/plugin upgrade
  was necessary. NDK 27.0.12077973 matches the already installed plugin requirement.
- Android retains `adjustResize`, SafeArea/system insets and the shared responsive
  navigation. Intelligence accounts for keyboard height. No Windows configuration,
  backend business logic or endpoint changed.

## Device acceptance checklist

Host widget/API tests are not physical-device verification. On the Xiaomi, check:

- Login, restart/restore, logout, reconnect after USB loss and backend restart;
  session expiry/revocation must remove open protected dialogs and records.
- Drawer/account navigation, system Back, gesture/navigation bars, portrait/
  landscape, HyperOS font scaling, keyboard open/close, focused field scrolling.
- Owner/manager Today, calendar/month selection, create/edit/cancel synthetic stays,
  Reception list/thread/drafts, Intelligence submit and operational desk.
- Cleaning start/checklist/finish and maintenance lifecycle using authorized roles;
  staff/admin owner controls must not appear for workers or writable managers.
- Staff creation/reset one-time credential display and secure session restore after
  process termination. Keystore behavior and HyperOS lifecycle need device testing.
- Keep integrations unconfigured/local-sandbox. Do not provide actual provider
  keys or enable real Channex, AI, messaging or government services.

The existing functional/visual parity gaps in PORT_STATUS.md remain; Android does
not add a native public guest scanner or certified provider transmission.

## Validation on 2026-11-12

- `flutter analyze`: no issues.
- `flutter test`: 168 passed, no failures/skips (160 existing plus eight Android
  layout/IME tests). The new tests emulate Android theme, 393 × 852 viewport,
  system insets, drawer navigation and a 300px keyboard; they are host widget tests.
- `flutter build apk --debug`: succeeded with the final NDK/manifest changes.
  Package ID `com.delvane.delvane_business`, min SDK 21 / target and compile SDK 35,
  version 0.1.0+1. Universal debug APK includes ARM64 for the Xiaomi 15.
- Packaged manifest/XML inspected with Android SDK `aapt`: debug loopback policy,
  backup/transfer exclusions and `adjustResize` confirmed. `zipalign -c -P 16 4`
  succeeds; both packaged ARM64 libraries have 65536-byte ELF LOAD alignment.
  This is packaging evidence, not proof of operation on a 16 KB device.
- Nine isolated backend workspace tests pass. No backend source changed.
- Windows release regression also succeeded in the separate ignored
  `build/windows-android-regression/x64/runner/Release/` bundle. The usual output
  executable was locked by the running Windows app; it was preserved and not killed.
- No Android device was reported by `adb devices -l`; nothing was installed or
  launched on a phone. The USB helper's no-device refusal was exercised; real
  forwarding, Keystore storage, device fonts, GPU behavior and HyperOS lifecycle
  remain for device acceptance. No emulator run is claimed.

Reference: [Android network security configuration](https://developer.android.com/privacy-and-security/security-config),
[Android developer options](https://developer.android.com/studio/debug/dev-options),
[Xiaomi OS-version instructions](https://www.mi.com/global/support/faq/details/KA-07878/).
