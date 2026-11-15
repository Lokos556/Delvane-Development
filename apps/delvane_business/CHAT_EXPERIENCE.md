# Delvane AI — continuous chat experience

15 November 2026. Repository: C:\Delvane\Delvane-Development.
Started on clean main, five existing commits ahead of origin/main. No commits or
pushes made by this task. Operational/production/staging databases and services
were not accessed; tests used guarded fictional data.

## Confirmed root causes

Sending used PmsController.act with its default reload=true. After the POST,
PmsController.load set loading=true and cleared the page data. PmsShell then
replaced IntelligenceWorkspace with a page-wide spinner, disposing its focus/scroll
state and temporarily removing the conversation. This produced the refresh/white
flash and reset the list. The old send callback then often found its widget
unmounted, so its post-response scroll never ran. Its fallback scroll also targeted
the end of a response, which was unsuitable for long answers.

A separate retry regression was demonstrated before modifying the backend:
posting the same accepted turn twice produced four stored messages. A lost HTTP
response followed by a normal resend could therefore duplicate conversation history.

## Implemented UI behavior

- A session-owned PmsChatSession holds the live conversation separately from the
  page-wide PMS loading state. A submitted user message appears immediately.
- The composer clears for the next draft while the question remains visible.
  On failure, an empty composer is restored with the failed question and cursor at
  its end; an independently edited next draft is not overwritten.
- A restrained fading-dot indicator with 'Delvane is responding…' sits below the
  submitted question. It exists only while the real request is pending, respects
  reduced motion and is replaced by the complete actual response.
- No simulated streaming, character-by-character reveal or streaming backend was
  introduced. The existing whole-response JSON endpoint is retained.
- Previous messages remain selectable/scrollable while awaiting the answer. Only
  duplicate chat submissions are disabled; the conversation is not replaced by a
  loading screen or navigation operation.
- A failed request leaves the user's message in place and shows a localized error
  with Retry. Retrying reuses that same turn rather than adding another user bubble.
- Background Intelligence/history refreshes retain the existing chat widget and
  cached data. Temporary refresh errors are inline. Authentication/permission loss
  clears private cached chat instead of retaining unauthorized records.
- Sending keeps composer focus and does not automatically dismiss the keyboard.
  The composer remains above the IME/safe area. Auxiliary metrics/suggestions hide
  while the keyboard is open to give the conversation more room; existing layout
  rules and Delvane styling otherwise remain.

New copy uses the existing HU/EN localization system:

| English | Hungarian |
|---|---|
| Delvane is responding… | Delvane válaszol… |
| Jump to latest | Ugrás a legújabb üzenethez |
| Couldn't send. Try again. | Nem sikerült elküldeni. Próbáld újra. |
| Couldn't refresh history. Try again. | Nem sikerült frissíteni az előzményeket. Próbáld újra. |

## Scrolling, identity and performance

Submission resumes following the latest turn and brings the user message/pending
indicator into view. Short conversations are bottom-aligned near the composer.
Short replies follow the bottom; long replies target the beginning of the new
answer, leaving its continuation below the viewport rather than skipping to the end.

Older history uses a lazy sliver list. The newest bounded eight messages remain
laid out as an anchor, allowing even an immediately completed long response to
scroll directly to its beginning without first jumping to its end. Stable local
turn identities are reconciled with server message IDs; a successful send updates
the conversation in place instead of re-fetching the entire PMS page.

If the user scrolls upward while waiting, following stops and the current position
is retained when the response arrives. Jump to latest becomes available. Returning
to the bottom, tapping that control or submitting another question resumes following.
Keyboard viewport changes follow this same reading/following policy. Animations
are short and disabled when reduced motion is requested.

Conversation state survives navigation within the authenticated session, including
responses arriving while the chat widget is offscreen. Saved messages still restore
from the existing backend history after an application/backend restart. Sign-out
or loss of owner/manager access clears the private client cache.

## Minimal, demonstrated backend correction for retries

The UI-only changes do not require AI query/provider changes. Safe retry did require
a small backward-compatible addition to POST /api/rosa/chat:

- Optional client_request_id: a validated 32-character lowercase hexadecimal ID,
  generated once for a submitted turn and retained across its retries.
- Existing authenticated organization/user scope is included in deterministic
  record IDs. A replay returns the original stored user/assistant message IDs,
  content and factual metadata instead of running/storing another turn.
- Changing the question, language or explicitly selected conversation under a used
  ID is rejected. Another user cannot read the original response with the same ID.
- In-process concurrent copies share one computation. Existing database primary
  keys prevent duplicate saved records across workers as well. A rolled-back attempt
  can be retried; a committed answer can be replayed after a persistent restart.
- Request locking does not hold a database writer lock during provider HTTP I/O.
  Existing chat/audit storage is reused; no table, column, index or schema migration
  is required. Legacy requests without the optional ID retain their API behavior.
- The response includes additive user_message_id/assistant_message_id fields so the
  client can reconcile optimistic rows with saved history.

This extension was justified by the failing retry test, not added as new AI
infrastructure. PMS query logic, authorization, cookies, CSRF, read-only restrictions,
provider configuration and external request behavior remain unchanged.

## Validation

Completed final verification:

- New chat widget regressions: 11 passed. Covers optimistic insertion; no temporary
  blank/remount; indicator visibility/animation; short and long response positioning;
  frame-by-frame immediate long response; manual upward scrolling/Jump; keyboard,
  focus and safe areas; localized failure/retry; background refresh; navigation;
  stable IDs; permission loss.
- Complete Flutter suite: 272 passed; analysis: no issues.
- Relevant guarded backend suite: 60 passed, two existing deprecation warnings.
  Includes nine retry cases plus owner queries, HU/EN/Unicode, authorization and
  persistent workspace tests. The new retry coverage includes the original lost
  response reproduction, concurrent duplicate requests, invalid/reused IDs,
  rollback/retry, tenant/user scope and persistent-restart replay.
- Android debug APK: built successfully.
- Windows release bundle: built successfully.
- Font-loaded Hungarian phone widget previews rendered and inspected using
  fictional test messages. These are not physical-device or live OpenAI screenshots.
- git diff --check: passed.

The initial duplicate-turn test failed before the retry fix and passes afterward.
Early widget fixtures that returned only {'ok':true} were updated to the actual
assistant response contract; per-turn error assertions replace the former global
page-error assertions. No tests were skipped to hide a failure. Existing Kotlin
migration and Starlette/AnyIO warnings remain.

Logs: apps/delvane_business/build/chat-*.txt. Final artifacts:

- apps/delvane_business/build/app/outputs/flutter-apk/app-debug.apk
- apps/delvane_business/build/windows-vs2026/x64/runner/Release/

## Changed files

| File | Purpose |
|---|---|
| apps/delvane_business/lib/features/pms/chat_session.dart | New optimistic/session-owned conversation state, stable identity, pending/failure/retry handling. |
| apps/delvane_business/lib/features/pms/intelligence_workspace.dart | In-place chat UI, real pending indicator, anchored scrolling, user reading override, keyboard/focus handling. |
| apps/delvane_business/lib/features/pms/pms_controller.dart | Holds chat state; retains Intelligence during background refresh; invalidates private state on access loss. |
| apps/delvane_business/assets/native-hu.json | New natural Hungarian status/error/navigation text. |
| app.py | Optional retry ID, durable reply replay, additive message IDs, existing storage reuse. |
| apps/delvane_business/test/chat_experience_test.dart | New UI/scroll/keyboard/retry/localization regressions. |
| tests/test_chat_retry.py | Duplicate-turn reproduction and replay/concurrency/persistence/security tests. |
| apps/delvane_business/test/owner_assistant_test.dart | Per-turn loading/failure assertions. |
| apps/delvane_business/test/hungarian_assistant_test.dart | Realistic successful API response fixture; Unicode/suggestion checks preserved. |
| apps/delvane_business/test/visual_interactions_test.dart | Realistic assistant response fixture; session/CSRF checks retained. |
| apps/delvane_business/PORT_STATUS.md and CHAT_EXPERIENCE.md | Current report and verification summary. |

A complete changed-file manifest accompanies this report. Flutter 3.50.0 / Dart
3.14.0, application identifiers, environment isolation and existing data are retained.

## Install and test on Xiaomi 15

Restart the existing persistent backend first so safe retries use the updated server:

```powershell
Set-Location C:\Delvane\Delvane-Development
.\.venv\Scripts\python -B run_persistent_development_workspace.py
```

No database reset or migration is needed. Existing fictional accounts, reservations
and saved conversation history remain. Keep the backend terminal open.

In a second terminal, connect USB and authorize USB debugging, then install:

```powershell
Set-Location C:\Delvane\Delvane-Development
powershell -NoProfile -ExecutionPolicy Bypass -File .\apps\delvane_business\tool\connect_android.ps1 -Install
```

The helper uses adb install -r, preserving app data. Do not uninstall. Reapply after
USB reconnection; add -DeviceId SERIAL if multiple authorized devices are attached.

Test a Hungarian question, a long answer and a deliberate scroll upward while
waiting. Confirm the prior messages stay visible, the keyboard/input stay usable,
the long answer starts at its beginning, and Jump to latest works. Test Retry after
a connection failure and reopen the conversation. Repeat in English on Windows.

Windows uses the whole release bundle, including adjacent DLLs and data:

```powershell
Set-Location C:\Delvane\Delvane-Development
& .\apps\delvane_business\build\windows-vs2026\x64\runner\Release\delvane_business.exe
```

## Remaining limitations

Physical Xiaomi/Windows interaction, live keyboard animation/GPU behavior and real
screen-reader acceptance remain manual. No physical-device result or live OpenAI
request was performed/claimed. This task adds no streaming support.

Only accepted messages are durable on the backend. A local-only failed/unsent turn
and its draft are retained in the current authenticated client session, not newly
written to device disk; terminating the app before backend acceptance can lose
that unsaved draft. Saved history and accepted retry IDs survive server restarts.
Update/restart both backend and client to use the new retry protection.
## Widget preview artifacts

- [Pending response](CHAT_MOBILE_PENDING.png)
- [Completed response](CHAT_MOBILE_RESPONSE.png)

These previews use fictional widget-test data and installed fonts.
