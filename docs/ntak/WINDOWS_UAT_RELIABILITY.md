# Windows UAT reliability and presentation

## Findings and changes

- The previous release cleared the page on every navigation and fetched identity, page endpoints and sidebar endpoints in sequence. A single failed request could replace the entire page. The sidebar always announced that Delvane was online. Page sections now load independently. Previously fetched reads stay in memory for the authenticated identity and are reused for 25 seconds. Explicit refresh loads again. Successful mutations invalidate the read cache, and a revoked session or identity change clears it. Property dialogs continue to request data by their own property ID.
- A timeout previously closed the shared HTTP transport, interrupting other outstanding requests. The native client now applies deadlines to individual requests. A dropped read can retry once on a fresh connection within its deadline. The client does not replay writes or retry HTTP status failures. Timeout and dropped-connection regressions exercised real local sockets. HTTP status, TLS verification, interruption and timeout now have distinct operator messages.
- The release used Segoe UI in the theme and explicit Georgia overrides in several PMS screens. The PMS now uses the bundled Inter asset. Page titles share a responsive scale and wrap actions at constrained widths. The Hungarian Intelligence briefing uses structured facts from the existing API. Operations suppresses the three hard-coded demo rows that the timeline endpoint appends and localizes the recognized synthetic booking event.
- The reporting apartment and second test apartment keep their original IDs. The second apartment belongs to the same fictional owner organization and is used to verify that evidence from one property cannot be exported through a sibling property's route. The second organization is a separate tenant used in the isolation tests. Names in the UAT client are presentation labels. The sidebar identifies the test workspace, and the owner role and observer mode use distinct labels. [Sibling property and tenant assertions](../../tests/uat_postgres_smoke.py)

## Live Windows verification

The dedicated Windows release restored the authorized synthetic owner session through the existing pinned TLS/SSH relay. The environment, liveness and readiness checks each returned HTTP 200. The Windows UI exercised repeated Ma, Intelligencia, Foglalások, Recepció and Műveletek navigation. Today displayed both readable property labels. The reporting apartment opened its own next reservation and room 101 in Apartments and rooms. The second apartment showed its own details and no upcoming reservation. Intelligence and the recognized Operations activity displayed Hungarian text.

The traced navigation and property walkthrough produced **49 HTTP 200 responses**, each on the first attempt, with a median request time of **276 ms** and a range of **101–355 ms**. The isolated tunnel's Windows SSH error log had no forwarding-open, refused, reset or broken-pipe entries during inspection. The earlier release's blank loading state was reproduced. The reported intermittent unavailable screen did not recur in the live walkthrough, so its original network trigger remains unconfirmed. Docker application logs were not accessible through the UAT SSH account. The reproduced client failure modes are covered by the socket tests.

The Windows UI was exercised on the current display. Widget tests covered the shared Hungarian heading at 100%, 125% and 150% equivalent device pixel ratios. Changing the Windows desktop scaling and running a longer operator soak remain manual checks. The walkthrough was read-only and left the running backend, property data and relay configuration in place. NTAK and VIZA transmission gates were preserved.

The full Flutter suite passed 314 tests. The 14 targeted transport, diagnostics, navigation and DPI tests passed again after the final status-indicator adjustment. Flutter analysis and `git diff --check` passed.

## Artifacts and repeat run

- Windows executable `apps/delvane_business/build/windows-uat-polish/x64/runner/Release/delvane_business.exe`. Keep the complete Release directory together.
- Before and after screenshots for Today and Intelligence, and after screenshots for Reservations and Operations, are under the ignored `build/ntak-uat/windows-visual` directory.
- Opt-in request diagnostics record only timestamp, HTTP method, a fixed route label, outcome, status, attempt count and elapsed milliseconds. Unknown routes are recorded as `other`. The file omits query strings, dynamic identifiers, cookies, headers and payloads.

Start the dedicated release from the repository root after the existing local UAT client and its tunnel have been closed. The root relay must be active.

```powershell
$env:DELVANE_UAT_API_LOG = Join-Path (Get-Location) 'build\ntak-uat\windows-polish-next-requests.jsonl'
.\apps\delvane_business\tool\connect_uat_windows.ps1 -Executable '.\apps\delvane_business\build\windows-uat-polish\x64\runner\Release\delvane_business.exe'
Remove-Item Env:DELVANE_UAT_API_LOG
```

To reproduce the build, use the staging defines from the [Windows UAT access guide](NTAK_UAT_WINDOWS_ACCESS.md#release-artifact-and-reproduction) with CMake output directory `build/windows-uat-polish/x64`.
