# Delvane AI — restored read-only owner assistant

14 November 2026. Repository: C:\Delvane\Delvane-Development.
Started on clean main, four existing commits ahead of origin/main. No commits or
pushes were made by this task. No production or staging environment was accessed.

## Outcome

The original OpenAI integration was found. Flutter was already connected to it;
this was not a missing Flutter-to-backend wire. The owner assistant now answers the
requested reservation/operational lookups from actual authenticated PMS records,
with Hungarian and English support, durable conversation context and read-only
behavior. Standard supported questions work without an API key or any external call.

A real OpenAI API request was NOT performed: no key was available in the process,
user/machine environment, repository development env file or checked legacy local
configuration. Provider success/failure tests used fictional keys and mocked Responses
API replies. The new optional live path is implemented but its real authentication,
project model access, billing and network connectivity remain unverified.

## Original architecture and confirmed gaps

Original web owner chat: static/app.js -> POST /api/rosa/chat, with existing cookie
and CSRF protection. Conversation/history endpoints and rosa_conversations,
rosa_chat_messages, rosa_ai_routes and rosa_proposals provide persistence/auditing.
app.py held the local router, _rosa_context_snapshot, _local_answer and
_openai_answer. The adapter used urllib POST https://api.openai.com/v1/responses,
Bearer authorization, instructions, a JSON prompt snapshot and plain text output.
It did not use OpenAI function calling or execute model-generated SQL.

The old route order was database facts, deterministic operations, governed action
engine, optional OpenAI free-text fallback, then an unconfigured-provider message.
The prompt snapshot held confirmed stays through the next seven days, two days of
cleaning, maintenance, staff, readiness and property knowledge. It was insufficient
for complete historical/monthly reservation and cancellation questions. Several
common English/Hungarian phrases were not recognized and fell through to fallback.
The old action path could simulate, propose or actually reassign cleaning according
to the organization's operating/authority mode, contrary to this phase's scope.

Active Flutter IntelligenceWorkspace already posted to /api/rosa/chat and loaded
/api/rosa/conversation through PmsController and the shared authenticated ApiClient.
Its send omitted conversation_id, while the old backend created a new thread when
none was supplied. The quick Ask bar called the older /api/rosa/ask endpoint with
only a few deterministic patterns. The legacy offline/demo AI page is not the active
authenticated owner assistant; it remains explicitly a prototype/demo interface.

The persistent development launcher intentionally clears provider configuration,
ignores unrelated .env files and blocks outbound networking. Thus an inherited API
key could not simply activate OpenAI there. This isolation was intentional, not a
broken database connection. The older global model default was not tested against
a real API and was not silently replaced for other legacy AI uses.

Windows' Python environment also lacked IANA timezone data. Added tzdata to
requirements.txt and installed tzdata 2026.6 into this existing .venv so business
calendar interpretation uses the configured timezone rather than the machine clock.

## What changed

The same chat/history/authentication infrastructure now delegates factual owner
queries to owner_assistant.py. Supported phrasing is interpreted locally; static,
parameterized SQL and deterministic rendering produce answers from actual rows.
Property knowledge/scalar facts, current readiness and maintenance reads are reused.
Unknown/inaccessible property scopes do not become unfiltered all-property answers.
Owners/managers retain their existing organization-wide access; workers cannot use
owner chat. No new property ACL or cross-organization lookup was introduced.

For less familiar wording, an explicitly configured OpenAI provider may return a
strict JSON-schema lookup plan (intent, date scope, property). The backend validates
it, authorizes the property again and computes the answer from the database. The
model supplies neither SQL nor final factual prose. Extra fields, malformed output,
refusals, missing output and provider errors never become fabricated PMS facts.
The external prompt contains the question, accessible property names, current
business date/timezone and previous lookup filters; it does not export guest,
identity-document, financial or reservation tables. A user's own question may of
course contain personal text, so avoid entering document numbers or secrets.

Write requests return a read-only explanation. No new action/proposal is created;
old assistant proposal approval is blocked, even in autonomous mode. The compatibility
/rosa/command endpoint delegates to the same read-only route. Flutter no longer
shows executable assistant proposal buttons or suggests a cleaning reassignment.
The quick Ask bar uses the same factual query layer locally, without external calls.
The Intelligence GET no longer refreshes/creates derived cleaning tasks merely by
opening the assistant. Other explicit PMS workflows remain available as before.

Business records are read-only; chat, audit, route and authentication metadata still
persist. No new schema version, migration or data reset is required.

Flutter now supplies the current conversation ID, and the backend also reuses the
primary thread when it is omitted. Lookup type/date/property context supports simple
follow-ups such as 'And today?' and 'What about Terra?'. New responses show PMS
provenance/read-only status, visible loading and safe errors. Failed requests retain
the entered question. Accepted messages scroll to the latest answer, respecting
reduced motion. Existing IME resizing and the existing design system are retained.
Configured provider status is labelled configured, not verified connected.

## Factual query definitions and limits

- Counts cover all reservation statuses unless confirmed/cancelled is requested.
  A month filters planned arrival dates within the business calendar month.
- Arrivals, departures and upcoming lists use confirmed reservations. Checkout
  questions filter departure dates. This week is Monday through Sunday.
- Cancellation period filters use planned arrival dates, and the answer explicitly
  says so; missing original cancellation dates are not invented.
- Upcoming means arrivals on or after the current business day. Lists are capped
  at 50; counts remain complete and truncation is indicated.
- Next weekend means the next strictly future Saturday arrival and Monday checkout.
  Availability checks active room-type inventory against confirmed occupied nights;
  checkout frees that night. It does not verify live OTA sales/channel restrictions.
- Explicit YYYY-MM-DD ranges are supported, with exclusive checkout and a maximum
  366-day window. Unsupported relative periods or filters ask for clarification;
  they are not silently replaced with a broader total.
- Open work is a bounded task list (normally overdue/due through the next seven
  days), not an invented complete assessment of all business risks.
- Business dates use organization_settings.timezone, Europe/Budapest by default,
  with IANA DST rules. Displayed list date ranges use inclusive calendar endpoints;
  structured facts retain date_to_exclusive for verification.
- Unsupported net profit, financial analysis, policies not stored, complex judgment
  and open-ended 'why' explanations remain explicitly unavailable. The model is
  deliberately not allowed to invent a fluent explanation as if it were evidence.
  This is a useful read-only factual assistant, not unrestricted autonomous AI.

## OpenAI configuration and limits

Existing server-side names are retained: ROSA_OPENAI_API_KEY or OPENAI_API_KEY.
The assistant model priority is ROSA_ASSISTANT_MODEL, explicit ROSA_OPENAI_MODEL,
then gpt-4o-mini. Existing guest-reply model/reasoning defaults are not overwritten.
The current assistant model uses structured output; choose a model your API project
can access. See the official [Responses API](https://developers.openai.com/api/reference/resources/responses/methods/create)
and [Structured outputs](https://developers.openai.com/api/docs/guides/structured-outputs)
contracts. No SDK or API key was embedded in Flutter/web assets.

One external request per eligible chat turn, no automatic provider retry, 500 output
tokens, up to 20 attempted interpretations per user/organization in a rolling hour,
recorded in the existing route log. Socket/request timeout is capped at 12 seconds.
These are application limits, not a guaranteed monetary budget; project billing
limits and actual model availability must be checked by the account owner.

Default persistent startup remains fully offline. --enable-openai is an explicit
opt-in and requires a key in the backend process. development_openai.py provides a
fixed verified-TLS transport to api.openai.com:443/v1/responses only, without
redirects or proxy adoption; request/response sizes are bounded. It does not relax
general network/database guards or load staging/production/provider configuration.
Stopping and restarting without the flag restores fully offline behavior without
replacing data. No existing credential file was changed.

## Verification

- Broader isolated backend regression: 79 passed, two existing deprecation warnings.
- Focused owner-assistant suite: 32 passed. Subsequent final date/copy/scope/filter
  checks passed (11 scenario checks and one additional filter check; overlapping,
  not extra unique test totals).
- Requested HU/EN examples compared against actual guarded database counts/rows.
  Tests include unauthorized tenant/property, worker roles, cross-user conversation,
  CSRF, unknown facts, same-thread follow-up, read-only behavior in autonomous mode,
  structured mocked provider success/failures, missing key and usage limits.
- Fictional two-unit inventory test verifies full occupancy, cancellation freeing a
  unit and checkout freeing its night. Explicit/invalid dates, Monday/week/year
  boundaries and Budapest DST dates covered.
- Persistent isolated workspace repeated the example queries and retained a new
  fictional reservation plus the same conversation across reopen.
- Independent-process persistent/disposable proof passed: reservation details,
  guests, encrypted values, staff, assignments, identity/session retained; disposable
  data gets a fresh identity and cleanup; no operational/staging database opened.
- Complete Flutter suite: 257 passed. New test checks current conversation ID,
  CSRF/language, loading, retained input after a safe server error, source label and
  absence of historical proposal actions. Existing Android keyboard and Windows/
  narrow-layout checks passed. Flutter analysis: no issues.
- Android debug APK and Windows release bundle built successfully.
- git diff --check passed. Flutter 3.50.0 / Dart 3.14.0 and app IDs retained.
- Real OpenAI request: NOT RUN, missing credentials. Mock success is not a live test.
- Physical Xiaomi/Windows interaction, live camera and real screen-reader behavior
  were not tested. No physical device result is claimed.

Initial checks caught a check-in/checking-out parser collision, fixture table/mode
names, a missing Flutter mock record, and old tests expecting autonomous chat writes
or arbitrary free-model prose. Corrected those issues and updated the historical
regressions to assert the requested read-only/grounded behavior rather than skipping
them. Existing Kotlin migration and Starlette/AnyIO warnings remain. No final test
failure remains in the checks reported above.

Logs: apps/delvane_business/build/assistant-*.txt. APK:
apps/delvane_business/build/app/outputs/flutter-apk/app-debug.apk. Windows full
release bundle: apps/delvane_business/build/windows-vs2026/x64/runner/Release/.

## Test on the Xiaomi 15

Stop the existing backend with Ctrl+C, then start the default persistent environment:

```powershell
Set-Location C:\Delvane\Delvane-Development
.\.venv\Scripts\python -B run_persistent_development_workspace.py
```

Keep that terminal open. Normal startup preserves the existing fictional accounts,
passwords, reservations and conversation history. Storage remains
C:\Delvane\Delvane-Development\.development\persistent\workspace.db with its
matching workspace.json identity/encryption key. No reset is needed.

In another terminal, connect USB, authorize USB debugging and run:

```powershell
Set-Location C:\Delvane\Delvane-Development
powershell -NoProfile -ExecutionPolicy Bypass -File .\apps\delvane_business\tool\connect_android.ps1 -Install
```

The helper uses adb install -r, preserving app data. Do not uninstall. Reapply the
helper after reconnecting USB; add -DeviceId SERIAL if several devices are present.
Log in with the existing owner/manager workspace.invalid account, open the Delvane
Intelligence/assistant screen and try:

1. How many reservations do I have?
2. Who is arriving tomorrow?
3. Which guests are checking out this week?
4. How many reservations were cancelled?
5. Which properties are available next weekend?
6. Summarize my upcoming reservations.
7. Melyik vendégek érkeznek holnap?
8. Hány lemondott foglalásom van?
9. Who is arriving tomorrow at Not Accessible House?
10. What was my net profit last year?

Also try 'Who arrives tomorrow at Terra?' then 'And today?'; confirm the same thread
and property filter. Ask to cancel a reservation: it should explain read-only mode
without changing any records. Compare the reported dates/statuses/counts with the
reservation list and test keyboard-open input scrolling and retained failed drafts.
These examples work locally; zero API calls are needed for supported phrasing.

Windows can use the complete bundle, including adjacent DLLs/data:

```powershell
Set-Location C:\Delvane\Delvane-Development
& .\apps\delvane_business\build\windows-vs2026\x64\runner\Release\delvane_business.exe
```

## Optional live OpenAI smoke test once a key is available

Stop the offline backend. In the backend terminal only:

```powershell
Set-Location C:\Delvane\Delvane-Development
$openAiSecret = Read-Host 'OpenAI project API key' -AsSecureString
$env:ROSA_OPENAI_API_KEY = [System.Net.NetworkCredential]::new('', $openAiSecret).Password
$env:ROSA_ASSISTANT_MODEL = 'gpt-4o-mini'
try {
    .\.venv\Scripts\python -B run_persistent_development_workspace.py --enable-openai
} finally {
    Remove-Item Env:\ROSA_OPENAI_API_KEY -ErrorAction SilentlyContinue
    Remove-Item Env:\ROSA_ASSISTANT_MODEL -ErrorAction SilentlyContinue
    $openAiSecret.Dispose()
}
```

Reconnect the Android helper as above. Ask a fictional-data paraphrase such as
'Tell me the size of my booking ledger' to exercise language interpretation rather
than a standard local pattern. A valid plan should produce the same reservation
count as the normal count question. Check the provider status's last success after
that request; a configured label alone does not prove success. Limit this manual
smoke test to one question initially. If the model/account rejects the request, the
assistant should show a safe unavailable explanation; do not paste keys or raw
provider traces into chat. Stop and restart without the flag for offline testing.
For a newly recreated .venv, first install requirements.txt (tzdata is required on
Windows); this workspace's existing .venv was already updated.

## Changed files

app.py: existing route/storage integration, safe provider helper, read-only proposal
boundary, current model status and removal of assistant GET's derived-task writes.
owner_assistant.py: bounded HU/EN plans, scoped SQL, factual rendering/date rules.
development_openai.py and run_persistent_development_workspace.py: explicit narrow
provider opt-in while retaining default isolation/storage/reset behavior.
requirements.txt: IANA timezone data for Windows.
Flutter intelligence_workspace.dart, ask_bar.dart and assets/native-hu.json:
thread ID, read-only/source/loading text, safe existing error path and scroll behavior.
Tests: new test_owner_assistant.py and owner_assistant_test.dart; updated historical
test_v26.py/test_v262.py/test_v265.py contracts for grounded, read-only behavior.
AI_SETUP.md, LOCAL_FIRST_AI.md and PORT_STATUS.md: current architecture, setup,
limits and verification. A complete changed-file manifest accompanies this report.