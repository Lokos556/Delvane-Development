# Delvane AI — owner assistant configuration

The active Flutter Intelligence conversation uses the existing authenticated
/api/rosa/chat and /api/rosa/conversation endpoints. It is read-only: no booking,
price, property, staffing or messaging changes, in any operating mode. Historical
assistant proposal approval is disabled. Other explicit PMS workflows are unchanged.

## Default persistent local testing (no API key needed)

```powershell
Set-Location C:\Delvane\Delvane-Development
.\.venv\Scripts\python -B run_persistent_development_workspace.py
```

Supported English/Hungarian counts, arrivals, departures, cancellations, upcoming
reservations, PMS inventory availability and open tasks use actual authorized local
records. Ordinary startup keeps the existing fictional data. No cloud hosting or
OpenAI call is needed for these questions. Persistent storage remains
.development\persistent\workspace.db with its matching workspace.json key.

## Optional OpenAI language interpretation

The earlier integration used ROSA_AI_PROVIDER, ROSA_OPENAI_API_KEY (or
OPENAI_API_KEY), ROSA_OPENAI_MODEL and ROSA_OPENAI_REASONING_EFFORT; normal backend
configuration also reads .env.local and %LOCALAPPDATA%\Rosa\.env.local. The isolated
launcher deliberately does not adopt those files, external databases or providers.
Do not copy an unrelated environment file into the acceptance workspace.

The persistent launcher now offers explicit --enable-openai. Set the key only in
the backend terminal. The prompt below does not echo it or place it in shell history:

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

Existing explicitly set ROSA_ASSISTANT_MODEL takes precedence, then
ROSA_OPENAI_MODEL, then the cost-conscious gpt-4o-mini default. Choose a model your
API project can access that supports Responses structured output. Existing legacy
guest-reply model/reasoning settings are not replaced by the assistant default.
The status endpoint reports configured, not a verified successful connection.

OpenAI is used only for unsupported wording: a strict, validated read-only query
plan. Database SQL, authorization and final factual wording stay on the server.
There are no model tools capable of writing, no generated SQL, and no unvalidated
model prose shown as facts. The prompt contains the question, accessible property
names, business date/timezone and previous lookup filters, not an export of guest,
identity, financial or reservation records. User-entered question text itself may
contain personal information, so avoid including document numbers or secrets.

Limits: one request per eligible chat turn, 500 output tokens, at most 20 attempted
interpretations per user/organization in a rolling hour (recorded in the existing
route log), with a socket/request timeout capped at 12 seconds. No automatic API
retry. No key or unsupported provider response: a safe local explanation.
The quick Ask bar remains local-only. This is not a monetary budget guarantee;
configure project-level billing limits separately if desired.

The opt-in transport is fixed to verified TLS at
https://api.openai.com/v1/responses. It does not enable arbitrary networking,
redirects, staging/production configuration, database URLs or channel providers.
Stop and restart without --enable-openai to return to completely offline mode;
data, accounts and conversation history remain.

No real API request was made during this change: no key was available in the
checked process, user/machine environment or existing local development config.
Automated provider tests used fictional keys and mocked responses.

API contract reference: [Responses API](https://developers.openai.com/api/reference/resources/responses/methods/create)
and [Structured outputs](https://developers.openai.com/api/docs/guides/structured-outputs).
