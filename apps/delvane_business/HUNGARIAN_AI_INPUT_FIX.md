# Delvane AI — Hungarian input and suggested-question fixes

15 November 2026. Repository: C:\Delvane\Delvane-Development.
Existing uncommitted owner-assistant restoration changes were preserved. This task
made no commits or pushes and did not access production/staging data or services.

## Root causes

### Unicode request failure

The composer has no ASCII whitelist, filtering formatter or character-sanitizing
listener. The material_ui TextField passes text and composing ranges through to
Flutter EditableText. The backend accepts Unicode strings and retains its existing
1–4000-code-point (after boundary trimming) message rule. JSON responses and stored
chat content are already Unicode capable.

The defect was in the shared native HTTP transport, IoApiTransport.request:

    request.write(jsonEncode(body))

ApiClient sent Content-Type: application/json without a charset. In the installed
Dart SDK, HttpClientRequest.write selects ISO-8859-1/Latin-1 when no charset is
specified. Characters in Latin-1 (such as á/é) therefore become invalid UTF-8 JSON
bytes, and characters outside Latin-1 (such as ő/ű, Polish letters and emoji) cannot
be encoded by write at all.

A real ephemeral-loopback HTTP test failed before the fix with:

    Invalid argument (string): Contains invalid characters.
    _HttpClientRequest.write -> IoApiTransport.request

The same test passes after the fix. The user's clarification that Xiaomi shows
'A szerver nem tudta teljesiteni a kérést' identifies a request failure and is
consistent with this transport defect. Automated IME/typing/paste tests accept the
characters; no separate physical keyboard rejection was reproduced or claimed.

The fix sends UTF-8 bytes explicitly:

    request.add(utf8.encode(jsonEncode(body)))
    Content-Type: application/json; charset=utf-8

This is general Unicode support, not a Hungarian-only whitelist. No accents are
stripped or transliterated, including decomposed combining characters. Existing
query matching may still normalize a separate internal lookup copy; the original
user message and its stored/displayed history are preserved.

### Translated label but English insertion

IntelligenceWorkspace translated each English prompt for its picker label, then
assigned the original prompts[i] English string to the message controller.

AssistantPrompt now provides stable suggestion identities and shared localized
text. The active assistant resolves one localized list per rebuild and uses that
same string for both the label and inserted message. The cursor is placed at the
end, and submission uses the inserted text unchanged. HU/EN language changes rebuild
the suggestions without translating or overwriting an existing user draft/history.

Audited all native AI quick prompts. The separate scripted-demo AI chips had the
same display/send inconsistency; they also use AssistantPrompt now. Their stable
identity retains the existing canonical demo routing internally, while the visible
question/history remains localized. The quick Ask bar has no suggestion list; its
shared HTTP requests benefit from the UTF-8 transport fix.

The Hungarian 'Van valami aggasztó holnap?' phrase now reaches the same existing
local attention lookup as 'Anything concerning tomorrow?'. This small alias prevents
the newly localized submission from losing the supported English lookup. No other
PMS business workflow, authority rule or assistant write capability was changed.

## Changed files in this follow-up

| File | Purpose |
|---|---|
| apps/delvane_business/lib/core/network/api_client.dart | Explicit UTF-8 JSON bytes and content-type charset in shared native transport. |
| apps/delvane_business/lib/features/pms/assistant_prompts.dart | New stable identities and shared localization for owner/demo suggestions. |
| apps/delvane_business/lib/features/pms/intelligence_workspace.dart | Uses one localized text list for display, insertion and submission; preserves draft/history. |
| apps/delvane_business/lib/features/ai/ai_page.dart | Localized scripted-demo questions with stable internal routing. |
| owner_assistant.py | Adds the localized attention phrase to the existing local intent matcher. |
| apps/delvane_business/test/unicode_transport_test.dart | Actual loopback native HTTP byte/charset/echo regression. |
| apps/delvane_business/test/hungarian_assistant_test.dart | Typing, composing, clipboard paste, submission/display, localized suggestions and language switching. |
| tests/test_assistant_unicode.py | API/SQLite/persistent history, validation/security and HU/EN lookup parity. |
| apps/delvane_business/PORT_STATUS.md | Focused implementation/verification summary. |
| apps/delvane_business/HUNGARIAN_AI_INPUT_FIX.md | This report. |

The owner assistant, launcher, API configuration and tests already modified in the
previous task remain in the working tree. They were not reset or committed here.
The accompanying changed-file manifest lists this follow-up's scope only.

## Verification

- Before-fix native wire test reproduced the encoding exception; after-fix test
  verifies byte-level UTF-8 and exact server echo through the real IoApiTransport.
- Flutter analysis: no issues.
- Complete Flutter suite: 261 passed, including four new tests.
- Backend: 43 passed (11 Unicode/localized-lookup cases plus the existing 32 owner
  assistant cases), two existing Starlette/AnyIO deprecation warnings.
- Android debug APK: built successfully.
- Windows release bundle: built successfully.
- git diff --check: passed.

Coverage includes all five supplied Hungarian examples, lowercase/uppercase vowels,
German/French/Polish text, emoji and decomposed e + combining acute. IME composing
and commit ranges remain intact. Clipboard.getData -> EditableTextState.pasteText
is exercised. Tests submit Unicode and render it from restored Flutter history;
backend tests compare the exact original string with API history and SQLite, then
reopen a guarded persistent workspace and verify every message again.

Each owner suggestion is selected/submitted in both HU and EN; the request body
matches the displayed label and current language. Language switching changes the
suggestion list while retaining an existing Unicode draft. Supported readiness,
attention and cancellation suggestions produce matching HU/EN lookup results.
4000 accented characters are accepted; 4001, empty and whitespace-only messages are
rejected. CSRF and existing authorization/read-only regressions remain intact.

Some first test runs needed fixture corrections for typed JSON records and the
same loading/organization responses the full app uses. These were corrected without
suppressing errors. The original wire failure was retained as before-fix evidence.
No final failure remains in the reported checks. Existing Android Kotlin migration
warnings remain; toolchain settings were not changed.

Logs are under apps/delvane_business/build/hungarian-*.txt. Artifacts:

- apps/delvane_business/build/app/outputs/flutter-apk/app-debug.apk
- apps/delvane_business/build/windows-vs2026/x64/runner/Release/

## Install and verify on the Xiaomi 15

Restart the existing persistent backend to load the localized lookup alias, retaining
all fictional reservations and conversation history:

```powershell
Set-Location C:\Delvane\Delvane-Development
.\.venv\Scripts\python -B run_persistent_development_workspace.py
```

In another PowerShell terminal, connect USB, authorize USB debugging and install:

```powershell
Set-Location C:\Delvane\Delvane-Development
powershell -NoProfile -ExecutionPolicy Bypass -File .\apps\delvane_business\tool\connect_android.ps1 -Install
```

The helper uses adb install -r. Do not uninstall or reset app data. Add -DeviceId
SERIAL when multiple authorized devices are attached. Keep the backend terminal open.
No migration or database reset is required. Normal offline lookup testing needs no
OpenAI key. Existing opt-in provider configuration is unchanged.

In Hungarian, type/paste 'Árvíztűrő tükörfúrógép' and the supplied PMS questions;
confirm they remain intact and send without the request error. Select the readiness
suggestion and confirm the inserted/submitted question exactly matches its label.
Switch to English and repeat. Reopen the conversation and verify the original
Unicode history, including uppercase vowels and ő/ű. Unsupported query meanings
(such as new seasonal analytics) have not been added by this text-handling fix.

Windows can run the full release bundle as before:

```powershell
Set-Location C:\Delvane\Delvane-Development
& .\apps\delvane_business\build\windows-vs2026\x64\runner\Release\delvane_business.exe
```

## Remaining limits

No physical Xiaomi/Windows interaction was performed by this task. Actual Xiaomi
keyboard/IME, paste menu and installed-build acceptance remain to be rechecked.
The automated tests distinguish the confirmed request-encoding defect from a claim
of physically reproduced keyboard filtering. No real OpenAI request was required or
performed. Existing supported lookup scope and server-side length rules are retained.
Flutter 3.50.0/Dart 3.14.0, package IDs, session storage, environment isolation and
existing persistent data remain unchanged.