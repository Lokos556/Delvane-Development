# Delvane Business feature parity inventory

Updated 2026-11-11 after the distribution and remaining functional-parity pass.
All 125 original capability IDs were rechecked against the current native PMS
sources, active web overrides and existing API contracts. The original web/backend
columns are retained as the reference inventory; the Flutter location, status and
follow-up evidence columns now describe the current authenticated implementation.
The original mock-only inventory is superseded. FLUTTER_ROADMAP.md remains a
historical plan; the actual original navigation is authoritative.

## Reading the inventory

### Counted summary

| Measure | Count |
|---|---:|
| Original capability rows retained | 125 |
| Fully implemented reference client workflow (F) | 73 |
| Partially implemented (P) | 24 |
| Missing native workflow (M) | 15 |
| Blocked by reference/backend limitations (B) | 11 |
| Original simulation faithfully ported (S) | 2 |

F concerns functional client workflow parity for the documented scope, not pixel
fidelity, production acceptance or proof of an external provider's operation.
P identifies remaining client depth, incomplete original behavior or unverified
external paths. M means a client workflow is absent; API-only features are not
pretended to be visible web controls. B identifies missing reference/backend
capabilities that Flutter cannot supply. S explicitly preserves original simulated
behavior (local feed or simulate-send), not a new mock implementation. Navigation
alone never earns F. Every row retains its independent reference Web status.

Web status: I = substantive local execution/read path; P = partial/backend-only;
S = simulation; M = missing. No status claims certified government transmission,
real messaging delivery, financial execution or current provider certification.

All new live-mode calls use authenticated FastAPI. Test transports and explicit
legacy offline demo remain separate. Validation totals, commands and limitations
are recorded in PORT_STATUS.md; runtime success is not inferred solely from a
visible control or endpoint name. Functional acceptance tests cover selected
contracts and states, not all permutations across all 125 rows.

Priority P0/P1/P2/P3 retains the original sequencing/dependency intent. Paths in
backend columns have /api prefixed unless starting /guest or /health. Backend-only
capabilities and shared product gaps remain counted so no hidden rewrite is implied.

## Evidence and active-code interpretation

- [Web entry point](../../static/index.html) loads [app.js](../../static/app.js) and then [v283.js](../../static/v283.js). Later declarations and assignments override older ones; legacy code remaining in a file is not automatically an active screen.
- Active manager/owner navigation: app.js `ownerPrimaryNav` assignment near 1674; settings groups near 1798; contextual reservation near 1833; guest/registration redirect near 1906. v283.js overrides Team & Access, knowledge/authority, operating mode, and owner maintenance.
- [Backend](../../app.py): authentication near 3559; dashboards 3671; reservations 4000–4258 and 8491–8582; reception 4338–4618; work 4645; intelligence 4708/4916/5228/5376; Channex 5825–7393; self-check-in 7394–7544; government 7545–8004; access/audit/admin 8353–8806.
- [Guest check-in client](../../static/guest-checkin.js) and [HTML](../../static/guest-checkin.html) are a separate public browser journey, not an owner sidebar page.
- [Government boundaries](../../NTAK_VIZA_NEXT.md), [security boundaries](../../SECURITY.md), and [previous validation](../../TEST_VALIDATION.md) corroborate incomplete transport, MFA/email gaps, and known metadata debt. Historical milestone pass counts are not current verification.
- Flutter evidence: authenticated composition and protected navigator, core auth/network, PMS shell/controller/workflow/dialog files, property/rates, Reception/reservations, Operations/Team/Administration and channel/mapping/distribution/sandbox sources; older mock-only pages are used solely by explicit demo mode. See test/channel_port_test.dart, test/management_port_test.dart, test/reservation_reception_test.dart and isolated root API contract tests.

## Existing web navigation and role surfaces

Owner/manager primary destinations are **Today, Intelligence, Reservations, Reception, Operations**. Account/settings adds Team & Access; Train Delvane; Simulation/Operating Mode; Maintenance; Supplies; Integrations; Security Center; language and sign-out. Global search and mode shortcut are shell utilities. Properties are principally contextual readiness cards and property dialogs, not a full independent CRUD administration module.

Guest profiles/history/preferences remain reachable from reservations, reception and search. The old Guests and Registration Center render functions/endpoints remain in source, but current `navigate('guests')` opens search and `navigate('registration')` returns Today. Preserve the underlying workflows, not obsolete standalone menu assumptions.

Cleaners get My day, Schedule, Maintenance. Maintenance staff primarily get Maintenance. Owner/manager shells are not suitable substitutes for these restricted workspaces. `/api/me` supplies role/permissions; server handlers remain authoritative. In particular team mutation, integration creation/configuration, government connection saving and organization-mode changes have stricter owner boundaries than general manager read access. Session revocation is owner-only despite manager visibility of security data. Do not infer authorization from hidden buttons alone.

## Parity matrix

### Shell, access and common navigation

| ID | Feature | Web location | Backend/service | Web | Flutter location | Flutter | Recommended action | Priority |
|---|---|---|---|---|---|---|---|---|
| SH01 | Responsive primary navigation | shell, mobile menu | Client navigation | I | lib/features/pms/pms_shell.dart | F | Original primary/settings labels and restricted responsive shells; retain desktop/mobile acceptance checks. | P0 |
| SH02 | Shared visual styling | styles.css, shared shell | Client styling | I | lib/features/pms/pms_style.dart | P | Source palette/components retained; pixel metrics, glass layers and full localization remain for visual pass. | P0 |
| SH03 | Sign-in and sign-out | renderLogin, account panel | POST /login, /logout | I | lib/core/auth/auth_controller.dart | F | Real cookie login/logout, CSRF, secure session storage and expiry/revocation tests; no password persistence. | P0 |
| SH04 | Current user, permissions and organization context | boot, shell | GET /me, /organization | I | lib/core/auth/auth_controller.dart | F | GET me identity, organization, permissions and session-keyed protected navigator are connected. | P0 |
| SH05 | Cleaner/maintenance-specific home and navigation | shell role branches | GET /worker/dashboard, /maintenance | P: worker maintenance property-fetch mismatch | lib/features/pms/pms_shell.dart | F | Cleaner and maintenance routes/actions tested; narrow operations/properties contract fixes legacy worker fetch mismatch. | P0 |
| SH06 | Global cross-entity search and Ctrl-K | openGlobalSearch | GET /search?q= | I | lib/features/pms/pms_shell.dart | P | Search API, reservation/property/guest/message routing and Ctrl-K/Cmd-K wired; full palette interaction parity remains. | P1 |
| SH07 | Language selection and translated UI | settings, langSelect; catalogs | Browser localStorage; client catalogs | P: broad catalogs, patch layers | lib/features/pms/pms_controller.dart | P | Original catalogs and language selection loaded; untranslated dynamic labels and persistence remain. | P1 |
| SH08 | Welcome briefing and entry workflow | showWelcome / entry slider | GET /intelligence | P: computed brief, decorative online/handled claims | lib/features/pms/pms_shell.dart | M | No separate original welcome/entry briefing workflow; do not count the dashboard heading as this feature. | P1 |
| SH09 | Property-scoped workspace navigation | property cards, calendar links | GET /properties, /properties/{p}/overview | P: contextual, no universal selector | lib/features/pms/property_dialog.dart | F | Actual property cards and contextual stay/calendar routing; reference has no global CRUD property selector. | P0 |
| SH10 | API request/authentication foundation | api helper | Cookie session + X-Rosa-CSRF | I: browser requests | lib/core/network/api_client.dart | F | Real fixed-origin native transport, cookie/CSRF headers, all HTTP verbs and safe failures; isolated marker enforced. | P0 |

### Dashboard and daily operations

| ID | Feature | Web location | Backend/service | Web | Flutter location | Flutter | Recommended action | Priority |
|---|---|---|---|---|---|---|---|---|
| DY01 | Live daily counts and summary | ownerToday | GET /owner/dashboard, /operations/today-command | I | lib/features/pms/pms_shell.dart | F | Today binds real command/dashboard counts; no fabricated revenue or fallback fixtures. | P0 |
| DY02 | Arrivals and departures with reservation drill-in | Today, operations desk | GET /owner/dashboard, /intelligence; reservation detail | I | lib/features/pms/pms_shell.dart | F | Actual arrivals/departures and reservation drill-in; regression tests cover connected navigation. | P0 |
| DY03 | Property readiness and turnover handoff | Today cards, property modal | GET /properties/{p}/overview | I | lib/features/pms/property_dialog.dart | F | Readiness, same-day handoff, cleaning status and primary stay from actual overview records. | P0 |
| DY04 | Registration-risk work queue | contextual Today registration cards | GET /operations/today-command, /registration | I | lib/features/pms/pms_shell.dart | F | Backend registration-risk queue opens the actual stay/review workflow. | P0 |
| DY05 | Cleaning/maintenance attention summary | Today, next-48 desk | GET /owner/dashboard, /intelligence | I | lib/features/pms/pms_shell.dart | F | Live cleaning/maintenance attention rows and status/severity; no simulated task completion. | P0 |
| DY06 | Current guest journey stage and next step | guestJourneyBoard, Today | GET /guest-journeys | P: computed stage; legacy scheduled labels not delivery proof | lib/features/pms/pms_shell.dart | P | Current/next journey stages, eight-row paging and stay links; detailed tracker presentation still incomplete. | P1 |
| DY07 | Operational activity timeline | ownerOperations, operations desk | GET /operations/timeline | P: persisted activity mixed with synthetic system events | lib/features/pms/pms_shell.dart | P | Persisted timeline shown; backend can include seeded/synthetic system events, not provider-delivery proof. | P1 |
| DY08 | Business decision approval/decline | Intelligence desk decisions | POST /approvals/{id}/resolve | P: resolves record/logs choice, not commercial execution | lib/features/pms/pms_shell.dart | M | Generic approval_items resolve workflow remains separate from connected chat proposals and is not ported. | P1 |
| DY09 | Next 48-hour operational desk | v264OpenDesk tabs | GET /intelligence, /operations/timeline, /guest-journeys | I for aggregated reads | lib/features/pms/pms_shell.dart | M | Dedicated original next-48-hour operational desk overlay/tabs are not ported. | P1 |
| DY10 | Cleaning/day contextual special requests | task/property/stay summaries | GET /worker/dashboard, reservation detail | I | lib/features/pms/pms_shell.dart | F | Assigned task preparation requests, guest count and timing from worker dashboard are displayed. | P1 |

### Reservations and calendar

| ID | Feature | Web location | Backend/service | Web | Flutter location | Flutter | Recommended action | Priority |
|---|---|---|---|---|---|---|---|---|
| RS01 | Reservation browse/statuses | ownerReservations, inquiries list | GET /reservations | I | lib/features/pms/reservation_dialogs.dart | P | Live calendar and inquiry access; comprehensive cancelled/status browsing remains incomplete. | P0 |
| RS02 | Reservation search/filter | calendar/list and contextual search | GET /reservations; client filtering | P: filtering surfaces vary | lib/features/pms/pms_shell.dart | P | Global search and dated calendar navigation; complete combined filtering is not implemented. | P1 |
| RS03 | Month calendar and previous/next/today | ownerReservations rebuilt calendar | GET /reservations, /properties; client date projection | I | lib/features/pms/pms_shell.dart | F | Month navigation, Today and month selection use real reservations with checkout-exclusive occupancy. | P0 |
| RS04 | Day overflow, arrival/departure counts and source colors | calendar day cells/more dialog | Same reservation data | I | lib/features/pms/pms_shell.dart | F | Day creation, complete overflow list, arrival/departure counts and source colors are tested. | P1 |
| RS05 | Create from toolbar or selected date | legacyReservationModal | POST /reservations | I: validation/capacity checks | lib/features/pms/reservation_dialogs.dart | F | Toolbar/day creation posts existing fields; server capacity/conflict errors preserve input. | P0 |
| RS06 | Edit dates/property/room/guest count/source/amount/requests | booking edit dialog | PATCH /reservations/{r} | I with validation inconsistencies to review | lib/features/pms/reservation_dialogs.dart | F | Existing editor PATCH fields and exact integer HUF; backend remains validation authority. | P0 |
| RS07 | Confirm inquiry and cancel reservation | legacy edit contextual buttons | PATCH /reservations/{r}; DELETE /reservations/{r} | I: cancellation is status change | lib/features/pms/reservation_dialogs.dart | F | Inquiry confirmation and explicit cancellation persist through existing endpoints. | P0 |
| RS08 | Reservation workspace overview | reservationModal tabs | GET /reservations/{r}/detail | I | lib/features/pms/reservation_dialogs.dart | F | Live stay overview, preparation, communication and activity modal tabs; no mock replacement. | P0 |
| RS09 | Arrival time, manual payment and registration status | overview operational controls | PATCH /reservations/{r}/operations | I: manual labels, not payment execution | lib/features/pms/reservation_dialogs.dart | F | Arrival/manual payment/registration operations PATCH; labels do not perform payments or verify identity. | P1 |
| RS10 | Stay messages, notes and change history | communications/history tabs | GET detail; POST /reservations/{r}/notes | I | lib/features/pms/reservation_dialogs.dart | F | Persisted messages, internal notes and reservation events; isolated mutation regression coverage. | P1 |
| RS11 | Linked cleaning/maintenance/readiness context | reservation cleaning tab | GET detail, checklists, maintenance | I | lib/features/pms/reservation_dialogs.dart | P | Actual cleaning/maintenance context and authorized record reader retained; deeper task presentation remains. | P1 |
| RS12 | Per-reservation channel delivery evidence/retry | overview Channex panel, save-result dialog | GET/POST /reservations/{r}/channex-availability-delivery[/retry] | P: durable dispatch/task IDs; not end-OTA acceptance | lib/features/pms/reservation_dialogs.dart | P | Delivery evidence/retry connected; provider task IDs do not prove final OTA acceptance. | P1 |

### Reception and guest communications

| ID | Feature | Web location | Backend/service | Web | Flutter location | Flutter | Recommended action | Priority |
|---|---|---|---|---|---|---|---|---|
| RC01 | Inbox list, search, status and unread indicators | ownerInbox Inbox tab | GET /inbox, /reception/summary | I: stored inbox, not automatic all-channel ingestion | lib/features/pms/reception_page.dart | F | Real inbox/status/count/search with explicit disconnected and empty states. | P1 |
| RC02 | Conversation/message detail and mobile list-to-thread | Reception message pane | GET /inbox payload | I | lib/features/pms/reception_page.dart | F | Message details and mobile list/back selection; desktop pane scrolling still a visual limitation. | P1 |
| RC03 | Manually add incoming message/inquiry and link stay | newInboxModal | POST /inbox | I | lib/features/pms/reception_page.dart | F | Manual intake/inquiry linkage persists; no automatic external ingestion is claimed. | P1 |
| RC04 | Analyze message and inspect extracted fields/authority | Analyze action, analysis chips | POST /inbox/{m}/analyze | I: deterministic extraction + mode gates | lib/features/pms/reception_page.dart | F | Analyze/extracted facts and authority state use existing API responses. | P1 |
| RC05 | Generate smart draft with optional model fallback | Smart draft | POST /inbox/{m}/draft | P: local drafting plus optional external model | lib/features/pms/reception_page.dart | P | Existing draft generation and provenance are connected; optional external model was not exercised. | P1 |
| RC06 | Edit/save persisted reply draft | draft editor | PATCH /inbox/{m}/draft | I | lib/features/pms/reception_page.dart | F | Persisted draft save plus session-only unsaved drafts; failed requests preserve input. | P1 |
| RC07 | Apply extracted arrival/request/inquiry actions | Apply action | POST /inbox/{m}/apply | I for supported actions, gated by mode/authority | lib/features/pms/reception_page.dart | F | Apply actions calls server mode/authority executor; no client business-rule duplicate. | P1 |
| RC08 | Mark externally replied / archive message | message tools | POST /inbox/{m}/reply-sent, /archive | I: bookkeeping; no send transport | lib/features/pms/reception_page.dart | F | Mark externally replied and archive are bookkeeping actions, explicitly separate from sending. | P1 |
| RC09 | Contextual stay/guest memory and quick navigation | message footer / guest context | GET reservation detail, /guests/{g} | I | lib/features/pms/guest_history_dialog.dart | F | Linked guest history/preferences and stay context; actual preference save now supported. | P1 |
| RC10 | Scheduled outbox edit/approve/cancel | Scheduled tab | GET /communications/outbox; PATCH /communications/outbox/{id}; POST /communications/outbox/{id}/approve | I: persistent preparation/approval | lib/features/pms/reception_page.dart | F | Scheduled edit/approve/cancel persist with explicit state and stale-refresh locking. | P1 |
| RC11 | Simulate send versus actual channel send | outbox Simulate send | POST /communications/outbox/{id}/simulate-send | S; actual external email/SMS/OTA/WhatsApp send missing | lib/features/pms/reception_page.dart | S | Original simulate-send endpoint faithfully labeled; live messaging transport remains absent. | P2 |
| RC12 | Automation rules, authority and evaluate-now | Automations tab | GET /automation/rules; PATCH /automation/rules/{id}; POST /automation/run | P: real rule evaluation/outbox creation; no independent timed delivery | lib/features/pms/reception_page.dart | P | Rule enable/authority/manual run supported; no independent timed delivery scheduler supplied by backend. | P2 |

### Properties and accommodation

| ID | Feature | Web location | Backend/service | Web | Flutter location | Flutter | Recommended action | Priority |
|---|---|---|---|---|---|---|---|---|
| PR01 | Property facts, occupancy/readiness preview | Today property modal | GET /properties, /properties/{p}/overview | I for configured properties | lib/features/pms/property_dialog.dart | F | Configured property facts/readiness modal and links connected, tested with empty property relationships. | P1 |
| PR02 | Same-day turnover, current and next stay | property modal | GET /properties/{p}/overview | I | lib/features/pms/property_dialog.dart | F | Current/next stay and same-day turnover handoff use overview API. | P1 |
| PR03 | List/create room types and capacity | property modal Add room type | GET/POST /properties/{p}/room-types | I; create can have Channex effects | lib/features/pms/property_dialog.dart | F | List/create room types with whole inventory/capacity values and server validation; no edit/delete endpoint invented. | P1 |
| PR04 | Rate-plan creation and room ownership | rate management API, ARI selection | GET/POST /properties/{p}/rate-plans | P: backend creation, no complete dedicated web editor found | lib/features/pms/property_rates_dialog.dart | P | Read plans/mappings and create through existing API with returned local room choices; original web has no complete dedicated editor. | P2 |
| PR05 | Property create/edit/archive administration | No general active editor found | No general property mutation endpoints found | M | No native implementation | B | General property create/edit/archive endpoints and complete reference workflow are absent. | P3 |
| PR06 | Physical room assignment/moves | Room types model; no complete physical-room allocator | No full physical-room inventory service found | M | No native implementation | B | No physical-room allocation/move domain or supporting contract in the reference backend. | P3 |
| PR07 | Property operational knowledge and calendar links | property modal, Train Delvane | GET overview, /knowledge; calendar client | I | lib/features/pms/administration_pages.dart | F | Shared/property knowledge persistence and existing property calendar links connected. | P1 |

### Guests, registration and identity

| ID | Feature | Web location | Backend/service | Web | Flutter location | Flutter | Recommended action | Priority |
|---|---|---|---|---|---|---|---|---|
| GU01 | Guest lookup/history/returning-guest context | search, stay and reception guest dialogs | GET /guests, /guests/{g} | I; old directory route redirected | lib/features/pms/guest_history_dialog.dart | F | Authorized guest history/language/preferences from real records; search routes to the same dialog. | P1 |
| GU02 | Add operational guest preferences | guestPreferenceModal | POST /guests/{g}/preferences | I | lib/features/pms/guest_history_dialog.dart | F | Add preference submits original key/value contract and reloads saved records. | P1 |
| GU03 | Registration completeness and expected guest slots | Today and reservation registration panel | GET detail, /registration, /reservations/{r}/guest-checkin-status | I | lib/features/pms/reservation_dialogs.dart | F | Actual expected slots/completeness shown; manual status and human verification remain separate. | P0 |
| GU04 | Generate/copy individual secure check-in links | reservation Send guest check-in link dialog | GET /reservations/{r}/guest-checkin-links | I: generates/rotates tokens; does not send | lib/features/pms/reservation_dialogs.dart | F | Explicit link generation and user-triggered clipboard copy; no automatic send or link on load. | P1 |
| GU05 | Prepare reminder and open reception | registration contextual buttons | POST /reservations/{r}/registration-reminder | I: persisted local draft only | lib/features/pms/reservation_dialogs.dart | F | Persisted reminder draft and Reception routing; no message delivery claim. | P1 |
| GU06 | Public guest pre-check-in form and confirmation | separate guest-checkin.html | GET/POST /public/checkin/{token}; /guest/checkin/{token} | I: expiring bearer flow, manual review follows | No native implementation | M | Public guest form remains the existing browser journey; no native guest-facing port. | P1 |
| GU07 | Camera capture, front/back OCR, MRZ and manual correction | guest-checkin.js | Browser Tesseract; structured public submission | P: real extraction code; device/accuracy limits; not authenticity/liveness | No native implementation | M | Public browser camera/OCR/MRZ/correction flow remains outside native client; no invented native scanner. | P2 |
| GU08 | OCR diagnostics, retry/timeouts and camera cleanup | guest scanner details/error states | Local browser diagnostics | P: raw OCR diagnostic visibility is privacy-sensitive | No native implementation | M | Original browser OCR diagnostics and camera cleanup not ported to native. | P2 |
| GU09 | Owner verify/reject and review method/note | reservation Verify guest identity dialog | POST /reservations/{r}/guests/{g}/verify | I: verification records; queue after all verified | lib/features/pms/reservation_dialogs.dart | F | Owner/manager verify/reject uses real guest review endpoint and notes; worker UI is restricted. | P1 |
| GU10 | Sensitive registration vault read/write | Backend boundary; no active full vault editor found | GET /registration/{r}/sensitive; PUT /registration/records/{g}/sensitive | P: field encryption, not all identity data encrypted | No native implementation | M | Sensitive vault administration not exposed in native; minimizing identity data remains deliberate. | P1 |
| GU11 | Authenticated scanner ingestion | API-only developer boundary | POST /government/viza/id-scan | P: stores fields; requires owner review, not certified VIZA | No native implementation | M | Authenticated id-scan backend exists but native scanner ingestion UI is missing. | P2 |
| GU12 | Unified standalone registration center | old ownerRegistration; current route redirects Today | GET /registration | P: retained endpoint/render function, not active destination | lib/features/pms/pms_shell.dart | P | Current web redirects standalone registration to Today; native risk queue/stay review retained, no obsolete extra page invented. | P1 |

### Cleaning, maintenance and supplies

| ID | Feature | Web location | Backend/service | Web | Flutter location | Flutter | Recommended action | Priority |
|---|---|---|---|---|---|---|---|---|
| OP01 | Cleaner My day / upcoming schedule | workerToday(false/true) | GET /worker/dashboard | I | lib/features/pms/pms_shell.dart | F | Assigned My day/Schedule and original today/in-progress filtering; worker data stays scoped. | P1 |
| OP02 | Start assigned cleaning task | worker task card/detail | POST /work-tasks/{t}/start | I | lib/features/pms/pms_shell.dart | F | Start accepts server open and legacy pending; real assigned-task endpoint and tests. | P1 |
| OP03 | Finish task with worker note | worker task detail | POST /work-tasks/{t}/finish | I; checklist enforcement configurable | lib/features/pms/pms_shell.dart | F | Checklist-gated completion with optional note persists; empty-note contract tested. | P1 |
| OP04 | Checklist read/toggle and progress | worker task dialog, reservation cleaning tab | GET /work-tasks/{t}/checklist; PATCH /work-tasks/{t}/checklist/{item} | I with assignment authorization gap to review | lib/features/pms/pms_shell.dart | F | Read/toggle checklist/progress with completion lock; backend assignment weaknesses remain separately documented. | P1 |
| OP05 | Automatically derive cleaning from reservation changes | Today/worker schedule refresh | refresh_cleaning_tasks | P: property/day aggregation and first-cleaner default | lib/features/pms/reservation_dialogs.dart | F | Reservation mutations retain server-derived cleaning refresh; no parallel native scheduler. | P1 |
| OP06 | Report maintenance with property/severity/details | cleaner/owner maintenance modal | POST /maintenance | I for owner/manager/cleaner; maintenance role cannot create | lib/features/pms/operations_pages.dart | F | Property/severity/detail report form, auto-assignment and worker-safe property context are tested. | P1 |
| OP07 | Maintenance list/status/severity/assignee | ownerMaintenance, workerMaintenance | GET /maintenance | P: case read implemented; worker screen additionally requests forbidden properties route | lib/features/pms/operations_pages.dart | F | Live cases, severity, assignee, timestamps and status filter; no worker guest-document access. | P1 |
| OP08 | Start/resolve maintenance | case action buttons | PATCH /maintenance/{id}/status; POST /maintenance/{id}/resolve | I; transition/assignment checks need review | lib/features/pms/operations_pages.dart | F | Permitted owner/manager/maintenance start and resolve actions; cleaners only report. | P1 |
| OP09 | Owner/manager verify resolved maintenance | owner maintenance Verify | PATCH /maintenance/{id}/status | I | lib/features/pms/operations_pages.dart | F | Owner/manager verification only; maintenance self-verification denied in client/backend tests. | P1 |
| OP10 | Reassign maintenance | API status payload; incomplete dedicated UI | PATCH /maintenance/{id}/status assigned_to | P: weak assignee/ownership checks | lib/features/pms/operations_pages.dart | M | Backend status PATCH accepts assignment but active web has no dedicated manual reassignment editor; none invented. | P2 |
| OP11 | Supplies quantity, par and estimated consumption | ownerSupplies via settings | GET /inventory; PATCH /inventory/{id} | I: local tracking/heuristic need | lib/features/pms/operations_pages.dart | F | Inventory estimates/par/low-stock/shopping list and fractional stock adjustment persist. | P1 |
| OP12 | Shift/attendance/payroll and purchasing automation | No working workflow found | No complete service found | M | No native implementation | B | No shift/payroll/purchasing backend; do not reinterpret stock estimates as procurement execution. | P3 |

### Staff and team access

| ID | Feature | Web location | Backend/service | Web | Flutter location | Flutter | Recommended action | Priority |
|---|---|---|---|---|---|---|---|---|
| TM01 | People directory/contact/security posture | v283 ownerTeam People tab | GET /team/overview | I: manager can read | lib/features/pms/team_page.dart | F | Live people/contact/security cards with owner manage and manager read-only tests. | P1 |
| TM02 | Create member and show/copy setup password once | add-member/password dialogs | POST /team/members | I: owner; no invitation email | lib/features/pms/team_page.dart | F | Real creation, once-only credentials and explicit copy; credentials removed with revoked session. | P1 |
| TM03 | Edit contact/job/role/active status | Manage member dialog | PATCH /team/members/{u} | I: owner; self-lockout guard | lib/features/pms/team_page.dart | F | Contacts/role/status PATCH with self-lockout safeguards and suspension/revocation tests. | P1 |
| TM04 | Reset access and revoke member sessions | member access tools | POST /team/members/{u}/reset-access, /revoke-sessions | I: owner | lib/features/pms/team_page.dart | F | Confirmed access reset and revoke-sessions; owner-only, same backend session lifecycle. | P1 |
| TM05 | Access/role permission matrix | Team Access tab | GET /team/overview | I for declared permissions, not proof all handlers match | lib/features/pms/team_page.dart | F | Server permission groups displayed by role; no permission engine duplicated in Flutter. | P1 |
| TM06 | Workload by person and upcoming assignments | Team Workload tab | GET /team/overview | I: read aggregation, not optimizer | lib/features/pms/team_page.dart | F | Real workload-by-person and upcoming assignments; no decorative assignment success. | P1 |
| TM07 | Transactional invitation delivery | account creation explanatory text | No connected email adapter | M | No native implementation | B | No transactional invitation delivery adapter; once-only password is not an emailed invitation. | P3 |

### Intelligence, AI governance and knowledge

| ID | Feature | Web location | Backend/service | Web | Flutter location | Flutter | Recommended action | Priority |
|---|---|---|---|---|---|---|---|---|
| AI01 | Persistent operational conversation | Intelligence main thread; compatibility conversation API | GET /rosa/conversation; GET/POST /rosa/conversations; GET /rosa/conversations/{id}; POST /rosa/chat | I: stored user/org-scoped chat; compatibility new endpoint returns the same primary thread | lib/features/pms/pms_shell.dart | F | Persistent server conversation load/chat send and proposal state retained. | P1 |
| AI02 | Local factual/operational answers and routing labels | chat badges, quick prompts, legacy rosaBar | local answer/context/router; /rosa/ask, /rosa/command, /rosa/provider | I within supported intents | lib/features/pms/pms_shell.dart | P | Actual local answers/brief displayed; complete evidence/routing/provider treatments remain incomplete. | P1 |
| AI03 | Optional model reasoning fallback/provider status | chat, provider status | external-answer adapter; GET /rosa/provider | P: configured optional call; not unrestricted autonomy | lib/features/pms/pms_shell.dart | P | Provider API loaded and backend fallback used by chat; complete provider diagnostics display and external validation remain. | P2 |
| AI04 | Structured proposals approve/decline | conversation proposal cards | POST /rosa/proposals/{id}/resolve | I for supported cleaning reassignment | lib/features/pms/pms_shell.dart | F | Chat proposal approve/decline uses existing resolve executor and actual statuses. | P1 |
| AI05 | Actual cleaning reassignment by AI command | proposal executor | _execute_proposal reassign_cleaning | I for narrow supported action | lib/features/pms/pms_shell.dart | P | Same chat/proposal APIs can invoke server reassignment; no dedicated native reassignment acceptance test completed. | P1 |
| AI06 | Observe/Assist/Autonomous mode | mode badge, v283 Simulation | PATCH /organization/mode | I: backend mode gates | lib/features/pms/administration_pages.dart | F | Real observe/assist/autonomous with owner-only mode changes and confirmation; server gates persist. | P1 |
| AI07 | Per-action automatic/ask/never authority | Train Delvane authority cards | PATCH /authority/{action_type} | I; declared actions exceed executor coverage | lib/features/pms/administration_pages.dart | F | Existing authority auto/ask/never PATCH for authorized owners/managers; no arbitrary executor added. | P1 |
| AI08 | Shared/property knowledge editing and completeness | v283 ownerTrainRosa | GET /knowledge; PUT /knowledge/{scope} | I: structured operational fields | lib/features/pms/administration_pages.dart | P | Shared/property knowledge and authority edit persist; full completeness score and exact tab presentation remain. | P1 |
| AI09 | Action history, simulated/awaiting/executed counts | Simulation activity | GET /rosa/actions | I: includes simulated records | lib/features/pms/administration_pages.dart | P | Real action ledger/statuses shown; complete source counts and payload treatments remain. | P2 |
| AI10 | Undo eligible actions | Simulation undo button | POST /rosa/actions/{id}/undo | I for implemented reversible action types only | lib/features/pms/administration_pages.dart | F | Only eligible executed reversible actions expose existing undo; server revalidates eligibility. | P2 |
| AI11 | Business memory and guest preference overview | Simulation memory panels | GET /memory | P: structured stored records, not general learning engine | lib/features/pms/administration_pages.dart | P | Real business/guest memory shown; complete structured-value presentation remains incomplete. | P2 |
| AI12 | Unlimited autonomous financial/maintenance/government execution | Authority labels may mention broader actions | No complete executor for those labels | M | No native implementation | B | Authority vocabulary does not implement unlimited autonomous financial/government/maintenance execution. | P3 |

### Channels and integrations

| ID | Feature | Web location | Backend/service | Web | Flutter location | Flutter | Recommended action | Priority |
|---|---|---|---|---|---|---|---|---|
| CH01 | Integration cards, status and sync summary | Settings Integrations | GET /integrations, /integration-sync/summary | I: status is configuration, not independent connectivity proof | lib/features/pms/integrations_page.dart | F | Live cards, queue counts, environment/configuration states, history and truthful government lock notice. | P2 |
| CH02 | Add integration slot | integration-create dialog | POST /integrations | S: creates sandbox slot | lib/features/pms/integrations_page.dart | F | Owner-only local integration slot form; manager has no create action. | P2 |
| CH03 | Encrypted technical credentials/configuration | technical API, developer setup; not full active UI | GET /integrations/{i}/technical-status; PATCH /integrations/integrations/{i}/technical-config | P: backend support | No native implementation | M | Encrypted credentials/technical-config API exists; dedicated native credential configuration not implemented. | P2 |
| CH04 | Booking.com commercial/property authorization | commercial-connect control | POST /integrations/integrations/{i}/commercial-connect | P: staging/onboarding intent; commercial authorization external | No native implementation | M | Commercial authorization API/backend instructions exist; no complete current native onboarding UI. | P2 |
| CH05 | Channex link/discover or map existing inventory | integration dialogs | POST /integrations/{i}/channex/link; GET/PUT /integrations/{i}/channex/inventory-mapping | P: real remote adapter; staging/certification boundary | lib/features/pms/channex_mapping_dialog.dart | P | Active map-existing-inventory flow connected and tested; legacy discovery/link/staging creation not exposed as a new workflow. | P2 |
| CH06 | Check bookings, inbound polling/webhook and ack retry | Check for bookings / receiver status | POST /integrations/{i}/channex/receive, /integrations/{i}/channex/bookings/{revision}/ack-retry; POST /channel-bridge/webhooks/{i}; workers | P: durable receiver implemented, live approval unverified | lib/features/pms/integrations_page.dart | P | Explicit receive and acknowledgement result UI connected; background receiver stays backend-owned, individual ack retry UI missing. | P2 |
| CH07 | Room/rate-plan mappings | inventory mapping and ARI dialogs | GET/POST /integrations/{i}/channex/rate-mappings; room mappings | I local mappings with remote dependencies | lib/features/pms/channex_mapping_dialog.dart | F | Property/active room/rate mappings with room-dependent rate options; failed reads clear stale choices and block writes. | P2 |
| CH08 | Date-range rate/availability/restriction edits | Rates & availability dialog | GET/PUT /integrations/{i}/channex/ari | P: real save/outbox/remote request; OTA completion unverified | lib/features/pms/distribution_dialog.dart | F | Single date-range price/availability/min/max/stop/arrival/departure restrictions, all-room option and certification resend. | P2 |
| CH09 | Bulk multi-date/multi-room/multi-rate edits | bulk ARI controls | PUT /integrations/{i}/channex/ari/batch | P: implemented dispatch path | lib/features/pms/distribution_dialog.dart | F | Add/remove bulk rate rows with independent dates/restrictions, duplicate-plan prevention and one batch request. | P2 |
| CH10 | Base nightly rate and rolling horizon | base-rate publisher | PUT /integrations/{i}/channex/base-rate; maintenance worker | P: persistent overrides and background queue | lib/features/pms/distribution_dialog.dart | P | Existing whole-unit base-rate endpoint and 365-day horizon connected; fractional non-HUF base prices blocked by backend int contract. | P2 |
| CH11 | 500-day full sync | integration Full sync action | POST /integrations/{i}/channex/full-sync | P: real recovery/certification dispatch | lib/features/pms/distribution_dialog.dart | F | Explicit 500-day full-sync action; queued/submitted/task IDs are not certification acceptance. | P2 |
| CH12 | ARI queue/retry/backoff/task evidence | outgoing queue status | GET /integrations/{i}/channex/outbox; POST /integrations/{i}/channex/outbox/retry | I locally; sent means request submitted | lib/features/pms/distribution_dialog.dart | F | Safe outbox diagnostics, retry timing/error, manual retry and saved/queued/retry/submitted/no-change result states. | P2 |
| CH13 | Sandbox feed/new/change/cancel/outage/iCal and preview/apply | Sync sandbox, history/events | /integrations/{i}/sandbox/*; POST /integrations/{i}/sync/preview, /integrations/{i}/sync/apply; GET /integrations/{i}/feed, /integration-sync/runs, /integration-events | S for feed creation; I local import transactions | lib/features/pms/sandbox_dialog.dart | S | Original local simulator: add/change/cancel/restore/outage/recover/iCal/preview/import. Real local writes, no external OTA delivery. | P2 |
| CH14 | Direct provider XML/events and other booking channels | Developer API; iCal sample UI | POST /integrations/{i}/booking/xml, /integrations/{i}/provider-events; parsers | P: normalized intake, not full direct Booking.com/Szallas.hu/Airbnb transport | No native implementation | B | Direct provider XML/events are backend plumbing; additional live channel adapters/access are incomplete. | P3 |

### Government and finance boundaries

| ID | Feature | Web location | Backend/service | Web | Flutter location | Flutter | Recommended action | Priority |
|---|---|---|---|---|---|---|---|---|
| GV01 | NTAK/VIZA readiness/certification/queue summary | Integrations government notice | GET /government/status | P: real queue/config, readiness flags not transport proof | lib/features/pms/integrations_page.dart | P | Actual certification flag and queued system/status counts shown; flags are not validated official transport. | P2 |
| GV02 | Government property connection configuration | API-only owner configuration | PUT /government/connections | P: credentials/config persisted | No native implementation | M | Owner-only government configuration API remains backend-only; no original complete active web editor found. | P2 |
| GV03 | NTAK XML/VIZA payload preview and developer readiness | Backend developer endpoints; not full current web form | POST /government/{system}/preview/{r}; GET /government/{system}/developer-readiness/{p} | P: preview/test records, not official validated submission | No native implementation | M | Developer preview/readiness APIs not exposed as a new native submission screen. | P2 |
| GV04 | Certified government transmission/acknowledgement | Notices imply future transport | government worker stops at waiting_for_transport | M: official transport not implemented | No native implementation | B | Official certified transport/module/signing and acknowledgement not implemented/validated by this port. | P3 |
| GV05 | Reservation amount and manual payment labels | reservation editor/overview | reservation CRUD and PATCH operations | I: records amounts/status, not payment processing | lib/features/pms/reservation_dialogs.dart | F | Exact stored amounts/manual payment statuses retained; no fake financial execution. | P1 |
| GV06 | Invoice issue/numbering/PDF/correction/NAV/provider | No implementation found | No invoice schema/endpoints/adapter found | M | No native implementation | B | No invoice domain/endpoints/provider/NAV adapter; requires separate backend work. | P3 |
| GV07 | Card charge/refund/payment reconciliation | Labels/authority terms only | No payment gateway/ledger found | M | No native implementation | B | No card gateway/ledger/reconciliation domain; manual labels remain distinct. | P3 |

### Settings, notifications, security and support

| ID | Feature | Web location | Backend/service | Web | Flutter location | Flutter | Recommended action | Priority |
|---|---|---|---|---|---|---|---|---|
| SE01 | Persistent notification list/read/read-all | shell notification popup | GET /notifications; POST /notifications/{id}/read, /notifications/read-all | I: internal records | lib/features/pms/pms_shell.dart | F | Persistent notification feed/read/read-all and count use existing APIs; no OS delivery implied. | P1 |
| SE02 | Event notification preferences | Simulation preferences | GET/PUT /notifications/preferences | I: persisted choices; not external delivery | lib/features/pms/administration_pages.dart | F | Six event preferences load/save through server; in-app choices are not external delivery. | P2 |
| SE03 | Security posture and active sessions | Security Center | GET /security | I for stored session/read metadata | lib/features/pms/administration_pages.dart | F | Actual account indicators and sessions shown; MFA indicator is not enrollment. | P1 |
| SE04 | Revoke individual session | Security Center revoke | DELETE /security/sessions/{id} | I: owner only | lib/features/pms/administration_pages.dart | F | Owner-only individual session revoke with confirmation; revalidation removes protected routes. | P1 |
| SE05 | Audit events and retention-policy visibility | Security Center audit/retention panels | GET /audit, /retention | P: audit reads/policy display; no automatic retention enforcement | lib/features/pms/administration_pages.dart | F | Audit/retention read paths connected; displaying a policy is not enforcement. | P2 |
| SE06 | Reset password / email verification token flows | Backend security endpoints, not complete browser recovery UI | POST /security/password-reset/request, /confirm; /security/email-verification/request, /security/email-verification/confirm | P: hashed tokens; production email delivery absent | No native implementation | M | Backend reset/email token flows have no complete native client form; transactional delivery remains absent. | P1 |
| SE07 | MFA/passkeys enrollment and enforcement | Team/security counts mention MFA | Stored fields only; no working MFA flow found | M | No native implementation | B | Working MFA/passkeys enrollment/enforcement missing in reference backend, not supplied by state indicators. | P3 |
| SE08 | Runtime/health/configuration diagnostics | Security runtime panel | GET /system/runtime, /health/live, /health/ready | P: real checks; conflicting release/schema metadata | lib/features/pms/pms_controller.dart | P | Runtime API loaded; full original developer diagnostics/configuration display remains incomplete. | P2 |
| SE09 | Demo workspace reset | legacy/local demo settings action; not ordinary production nav | POST /demo/reset, DEMO_MODE guard | I: destructive demo-only reset | No native implementation | M | No native reset button; existing dangerous demo reset is not introduced into ordinary development navigation. | P3 |
| SE10 | OS push, durable offline writes and synchronization | Minimal web manifest/service worker only | No full push/offline conflict service found | M for durable workflow; P for installable web shell | No native implementation | B | No push adapter or durable offline write/conflict-sync engine. Failures never fall back to demo data. | P3 |

## Flutter's exact current scope

- `app/destination.dart` defines seven destinations, with no nested route tree or role gating. Desktop sidebar is used from 1120px; medium layouts use a rail; narrow/short layouts use a drawer and Home/Stays/Reception/More bottom navigation. A drawer selection changes one controller enum; no durable/deep-linked navigation stack exists.
- `app/app.dart` always creates MockBusinessRepository unless a repository is injected in code. There is no deployed remote repository or login/live switch. `BusinessRepository` exposes only `load()`, so business mutations need separate repositories/use cases, not just more buttons.
- Dashboard: illustrative fixed-date greeting/chart, fixture-derived metrics and arrivals, static briefing, route shortcuts, and task checkboxes shared with Operations. The hero and generous spacing currently displace work queues. Reservation value is the sum of sample totals, not paid revenue; unit occupancy is a separate fixture dataset.
- Reservations: local case-insensitive guest/property/reference search, local status chips, displayed count and read-only stay dialog. No calendar, create/edit/cancel, guest records, notes, room types, audit history, or delivery state. Its statuses arriving/inHouse/departing are presentation concepts; the backend stores confirmed/inquiry/cancelled separately.
- Reception: select sample messages and type/save a draft into a controller map. No thread API, persistent drafts, message creation/search, analysis, apply, archive, outbox or channel send. "Unread" is a fixed fixture flag, not read tracking.
- Properties: synthetic cards with readiness, units/occupied, progress and a read-only dialog. No room/rate/knowledge/mapping editors or property mutation.
- Operations: one generic sample task list with a boolean completed set and optional compact spacing. No cleaning lifecycle, checklists, maintenance cases, assignments or staff identity.
- AI: local scripted branches for arrivals/tasks plus generic fallback, with session-only conversation tuples. It has no backend conversation, inference, authority, proposals, audit, or execution engine.
- Settings: session-only notification preference and compact-task toggle; English and HUF explanatory tiles; build/mock disclosures. Compact density is a useful Flutter-only affordance, not an operational parity claim. No role/team/integration/security administration.
- State ownership: controller holds destination, selected property, search, stay-status filter, completed task IDs, drafts and two preferences. Reception selection/editor and scripted AI history live in page State and can be lost on navigation; nothing persists after restart. There is no secure session store, local database, offline conflict queue or durable draft recovery.
- API foundation: native dart:io transport, HTTPS-origin validation, same-origin `/api/` paths, JSON decode, sanitized status/parse/network errors, timeout and injectable headers. Only GET/POST methods exist. Cookie capture, secure session storage, CSRF lifecycle, refresh/relogin handling, mutation DTOs, cancellation, response-size limits and domain-specific errors are not complete. The fixture app never instantiates it.
- Native scaffolds exist for Windows/Android/iOS/macOS. Existing README records 19 Flutter tests and a Windows release using an app-local VS2026 compatibility script. These are prior build results, not fresh tests or proof of operational parity; Apple/mobile device builds remain unverified here.

## Critical non-equivalences and backend dependencies

1. Copying a guest link is not sending it; mark-replied is not a transport; scheduled labels do not prove a scheduler or delivery exists. Never turn those labels into success toasts in Flutter.
2. Registration data completeness, human identity review and government acceptance are independent states. The operational-status patch can manually set complete, so its relationship to the newer verification gate needs explicit backend review. Do not silently reinterpret the endpoint as certified identity verification.
3. Government connection flags can say submission enabled, yet the worker still has no certified transport. UI must report actual worker/attempt evidence. No legal/certification claim is made by this inventory.
4. Generic approval_items resolution logs a decision; chat proposals have a separate deterministic executor. Model them separately. Authority labels alone do not implement refunds or arbitrary maintenance execution.
5. Channex has substantive HTTP/inbox/outbox/poll/ack/mapping/ARI logic. Staging defaults, credentials, current certification, external delivery and provider acceptance were not verified. Keep secrets and workers on the backend. Task ID capture is not OTA-final acceptance.
6. Existing source includes known safety/debt boundaries: incomplete login failure-rate persistence, declared but unenforced idle timeout, field-level rather than comprehensive identity encryption, broad checklist/maintenance mutation checks, booking capacity concurrency risk, property/day cleaning aggregation and outbox crash recovery. Treat these as review dependencies, not proof Flutter can safely expose every write immediately.
7. Role copy and handler permissions differ in places: maintenance cannot POST new cases; cleaner maintenance POST can auto-assign, while PATCH only permits reported; worker checklist edits lack equivalent assignment checks; manager security views can show actions whose endpoint is owner-only. Preserve intended least privilege, resolve API inconsistencies with tests instead of copying UI bugs.
8. Create/edit properties, physical-room allocation, invoicing, payment gateway, working MFA, email delivery, certified government transmission, full direct OTA connectors and durable offline sync are missing/partial on the reference side. Record these dependencies separately from client parity defects.
9. `workerMaintenance` (app.js:1481–1484) awaits `/api/maintenance` and `/api/properties` together, but property_list restricts `/api/properties` to owner/manager. No v283 worker override was found. Treat the current cleaner/maintenance page as a source-level broken dependency, not verified end-to-end functionality. A worker-safe property-context contract is required; do not simply grant broad owner-level access. Other version-layered shortcut bindings also require route tests rather than assuming a visible button is functional.

## Counting and migration governance

The matrix is the acceptance checklist. F/P/M/B/S in the **Flutter** column is the current functional client roll-up, with remaining limitations explicit per row. A feature moves to accepted release parity only with endpoint mapping, permission checks, state/error handling, isolated workflow tests and visual/device acceptance. Related API-only capabilities are deliberately recorded rather than presented as currently reachable web controls. New functionality beyond the reference needs a separate specification.

See FLUTTER_ROADMAP.md for the navigation proposal, sequencing, dependencies and cutover gates. Keep the existing web frontend available until all required parity rows are accepted; do not replace it with a broad switch based on a visually complete dashboard.
