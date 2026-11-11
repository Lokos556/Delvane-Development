# Delvane Business feature parity inventory

Inspection date: 2026-11-11. Reference: existing PMS v2.11.26 and current Flutter preview in this repository. This is a static source assessment, not a claim of deployed correctness or certification. No application execution, database inspection, migration, provider request, or test execution was performed for this planning task. Only this document and FLUTTER_ROADMAP.md are being added.

## Reading the inventory

### Counted summary

| Measure | Count |
|---|---:|
| Capability rows assessed | 125 |
| Flutter implemented client-only capabilities | 2 |
| Flutter partial counterparts | 19 |
| Flutter missing counterparts | 104 |
| Backend-connected Flutter business workflows | 0 |
| Explicit gaps missing in both products, included in the 125 | 10 |

Thus 115 rows describe at least some reference implementation (including partial/simulated/backend-only capabilities); 10 record absent reference-side capabilities. Of the 104 Flutter-missing rows, 94 have at least some reference-side implementation and 10 are shared product gaps. Of the 19 partial Flutter rows, 18 are mock/local/scripted counterparts and one is the unused API foundation. These counts must not be described as 21 completed operational features.

Each ID is one separately assessable capability, not an endpoint count. Related low-level fields/actions are grouped where they form one workflow. Explicitly absent capabilities are included so they cannot be mistaken for available PMS behavior. Counts include those gap rows and backend-only capabilities; they do not mean the web PMS has that many complete features.

Web status: **I** = substantive implemented local execution/read path; **P** = partial, limited, backend-only or incomplete workflow; **S** = simulation/demonstration; **M** = missing. I does not prove runtime success. A real local database write does not prove external delivery.

Flutter status: **I** = actual client-only capability works without backend integration; **P** = partial foundation or mock/local counterpart, explicitly not operational parity; **M** = no corresponding workflow. All business data in Flutter is synthetic. No Flutter business workflow has live backend parity.

Priority: **P0** = access/safety or first daily-use slice; **P1** = core operational parity; **P2** = subsequent depth/admin/integration work; **P3** = explicitly separate backend/product dependency. Within P2, inventory-critical channel availability takes precedence over optional diagnostics.

Endpoint paths in tables have `/api` prefixed unless explicitly beginning `/guest` or `/health`. `{r}` reservation, `{g}` guest/record, `{p}` property, `{i}` integration, `{t}` task, `{m}` message, `{u}` user/member. Read/write methods are indicated; grouped paths are separate endpoints, not a new combined route.

## Evidence and active-code interpretation

- [Web entry point](../../static/index.html) loads [app.js](../../static/app.js) and then [v283.js](../../static/v283.js). Later declarations and assignments override older ones; legacy code remaining in a file is not automatically an active screen.
- Active manager/owner navigation: app.js `ownerPrimaryNav` assignment near 1674; settings groups near 1798; contextual reservation near 1833; guest/registration redirect near 1906. v283.js overrides Team & Access, knowledge/authority, operating mode, and owner maintenance.
- [Backend](../../app.py): authentication near 3559; dashboards 3671; reservations 4000–4258 and 8491–8582; reception 4338–4618; work 4645; intelligence 4708/4916/5228/5376; Channex 5825–7393; self-check-in 7394–7544; government 7545–8004; access/audit/admin 8353–8806.
- [Guest check-in client](../../static/guest-checkin.js) and [HTML](../../static/guest-checkin.html) are a separate public browser journey, not an owner sidebar page.
- [Government boundaries](../../NTAK_VIZA_NEXT.md), [security boundaries](../../SECURITY.md), and [previous validation](../../TEST_VALIDATION.md) corroborate incomplete transport, MFA/email gaps, and known metadata debt. Historical milestone pass counts are not current verification.
- Flutter: all 18 Dart files under `lib/` reviewed, including [composition](lib/app/app.dart), [controller](lib/app/controller.dart), [shell](lib/shared/app_shell.dart), [models](lib/domain/models.dart), [mock repository](lib/data/mock_business_repository.dart), [transport](lib/core/network/api_client.dart), shared components and all seven feature pages. Tests/readme were reviewed as evidence, not rerun.

## Existing web navigation and role surfaces

Owner/manager primary destinations are **Today, Intelligence, Reservations, Reception, Operations**. Account/settings adds Team & Access; Train Delvane; Simulation/Operating Mode; Maintenance; Supplies; Integrations; Security Center; language and sign-out. Global search and mode shortcut are shell utilities. Properties are principally contextual readiness cards and property dialogs, not a full independent CRUD administration module.

Guest profiles/history/preferences remain reachable from reservations, reception and search. The old Guests and Registration Center render functions/endpoints remain in source, but current `navigate('guests')` opens search and `navigate('registration')` returns Today. Preserve the underlying workflows, not obsolete standalone menu assumptions.

Cleaners get My day, Schedule, Maintenance. Maintenance staff primarily get Maintenance. Owner/manager shells are not suitable substitutes for these restricted workspaces. `/api/me` supplies role/permissions; server handlers remain authoritative. In particular team mutation, integration creation/configuration, government connection saving and organization-mode changes have stricter owner boundaries than general manager read access. Session revocation is owner-only despite manager visibility of security data. Do not infer authorization from hidden buttons alone.

## Parity matrix

### Shell, access and common navigation

| ID | Feature | Web location | Backend/service | Web | Flutter location | Flutter | Recommended action | Priority |
|---|---|---|---|---|---|---|---|---|
| SH01 | Responsive primary navigation | shell, mobile menu | Client navigation | I | shared/app_shell.dart | I | Keep adaptive shell; add deep routes and all workspace sections | P0 |
| SH02 | Shared visual styling | styles.css, shared shell | Client styling | I | app/theme.dart, shared/components.dart | I | Preserve white/ink/yellow tokens; improve data density | P0 |
| SH03 | Sign-in and sign-out | renderLogin, account panel | POST /login, /logout | I | No login; fixed demo administrator | M | Implement real session lifecycle before live data | P0 |
| SH04 | Current user, permissions and organization context | boot, shell | GET /me, /organization | I | Hard-coded identity; no membership model | M | Typed identity and capability-based routing | P0 |
| SH05 | Cleaner/maintenance-specific home and navigation | shell role branches | GET /worker/dashboard, /maintenance | P: worker maintenance property-fetch mismatch | Everyone sees the same seven screens | M | Separate worker shell and allowed routes; resolve authorized property-context API | P0 |
| SH06 | Global cross-entity search and Ctrl-K | openGlobalSearch | GET /search?q= | I | Reservation-only search | M | Add command/search palette with typed entity results | P1 |
| SH07 | Language selection and translated UI | settings, langSelect; catalogs | Browser localStorage; client catalogs | P: broad catalogs, patch layers | Settings says English; no switch | M | Extract stable localization keys and operational text rules | P1 |
| SH08 | Welcome briefing and entry workflow | showWelcome / entry slider | GET /intelligence | P: computed brief, decorative online/handled claims | Dashboard greeting only | P (mock) | Replace ceremonial entry with actionable Today briefing | P1 |
| SH09 | Property-scoped workspace navigation | property cards, calendar links | GET /properties, /properties/{p}/overview | P: contextual, no universal selector | Desktop top-bar property selector | P (mock) | Persist valid client scope; apply consistently per screen | P0 |
| SH10 | API request/authentication foundation | api helper | Cookie session + X-Rosa-CSRF | I: browser requests | core/network/api_client.dart | P: unused GET/POST transport | Add cookie jar, CSRF, PATCH/PUT/DELETE, DTOs and remote repositories | P0 |

### Dashboard and daily operations

| ID | Feature | Web location | Backend/service | Web | Flutter location | Flutter | Recommended action | Priority |
|---|---|---|---|---|---|---|---|---|
| DY01 | Live daily counts and summary | ownerToday | GET /owner/dashboard, /operations/today-command | I | Dashboard metric cards | P (mock) | Bind backend counts; do not reuse synthetic occupancy/revenue as financial truth | P0 |
| DY02 | Arrivals and departures with reservation drill-in | Today, operations desk | GET /owner/dashboard, /intelligence; reservation detail | I | Dashboard arrivals / departure count | P (mock) | Add complete dated lists, arrival times and direct record routes | P0 |
| DY03 | Property readiness and turnover handoff | Today cards, property modal | GET /properties/{p}/overview | I | Dashboard heads-up, Properties readiness | P (mock) | Show outgoing stay, cleaner deadline and next arrival together | P0 |
| DY04 | Registration-risk work queue | contextual Today registration cards | GET /operations/today-command, /registration | I | No risk queue | M | Add urgent, due-today/tomorrow and owner-review queues | P0 |
| DY05 | Cleaning/maintenance attention summary | Today, next-48 desk | GET /owner/dashboard, /intelligence | I | Dashboard tasks / static heads-up | P (mock) | Use actual task states/deadlines/severity, not static brief text | P0 |
| DY06 | Current guest journey stage and next step | guestJourneyBoard, Today | GET /guest-journeys | P: computed stage; legacy scheduled labels not delivery proof | None | M | Port stage semantics and actionable links | P1 |
| DY07 | Operational activity timeline | ownerOperations, operations desk | GET /operations/timeline | P: persisted activity mixed with synthetic system events | None | M | Distinguish actual events from demo records before binding | P1 |
| DY08 | Business decision approval/decline | Intelligence desk decisions | POST /approvals/{id}/resolve | P: resolves record/logs choice, not commercial execution | None | M | Preserve decision log; never imply refund/checkout action ran | P1 |
| DY09 | Next 48-hour operational desk | v264OpenDesk tabs | GET /intelligence, /operations/timeline, /guest-journeys | I for aggregated reads | None | M | Compact drill-down workspace rather than oversized overlay | P1 |
| DY10 | Cleaning/day contextual special requests | task/property/stay summaries | GET /worker/dashboard, reservation detail | I | Generic sample task text only | M | Carry reservation requests and guest counts into authorized task context | P1 |

### Reservations and calendar

| ID | Feature | Web location | Backend/service | Web | Flutter location | Flutter | Recommended action | Priority |
|---|---|---|---|---|---|---|---|---|
| RS01 | Reservation browse/statuses | ownerReservations, inquiries list | GET /reservations | I | reservations_page.dart | P (mock) | DTOs for confirmed/inquiry/cancelled; do not equate UI arriving/in-house with stored status | P0 |
| RS02 | Reservation search/filter | calendar/list and contextual search | GET /reservations; client filtering | P: filtering surfaces vary | Reservation text/status search | P (mock) | Combine text, property, room type, source, date and canonical status | P1 |
| RS03 | Month calendar and previous/next/today | ownerReservations rebuilt calendar | GET /reservations, /properties; client date projection | I | No calendar | M | Desktop calendar plus mobile agenda with correct checkout-exclusive occupancy | P0 |
| RS04 | Day overflow, arrival/departure counts and source colors | calendar day cells/more dialog | Same reservation data | I | None | M | Port complete day-detail list, accessible source/status encoding | P1 |
| RS05 | Create from toolbar or selected date | legacyReservationModal | POST /reservations | I: validation/capacity checks | None | M | Validated editor and conflict feedback; no optimistic confirmed booking | P0 |
| RS06 | Edit dates/property/room/guest count/source/amount/requests | booking edit dialog | PATCH /reservations/{r} | I with validation inconsistencies to review | Read-only detail dialog | M | Preserve field ownership and old/new inventory transitions | P0 |
| RS07 | Confirm inquiry and cancel reservation | legacy edit contextual buttons | PATCH /reservations/{r}; DELETE /reservations/{r} | I: cancellation is status change | None | M | Confirm intent, preserve history and pending distribution results | P0 |
| RS08 | Reservation workspace overview | reservationModal tabs | GET /reservations/{r}/detail | I | shared/components.dart stay dialog | P (mock) | Side panel/route with complete linked record context | P0 |
| RS09 | Arrival time, manual payment and registration status | overview operational controls | PATCH /reservations/{r}/operations | I: manual labels, not payment execution | None | M | Port validation; review manual completion versus verification gate | P1 |
| RS10 | Stay messages, notes and change history | communications/history tabs | GET detail; POST /reservations/{r}/notes | I | None | M | Persist notes; separate internal notes from guest messages | P1 |
| RS11 | Linked cleaning/maintenance/readiness context | reservation cleaning tab | GET detail, checklists, maintenance | I | None | M | Deep-link to scoped work; show blockers without exposing documents to workers | P1 |
| RS12 | Per-reservation channel delivery evidence/retry | overview Channex panel, save-result dialog | GET/POST /reservations/{r}/channex-availability-delivery[/retry] | P: durable dispatch/task IDs; not end-OTA acceptance | None | M | Model local save, queued, retry, submitted, error distinctly | P1 |

### Reception and guest communications

| ID | Feature | Web location | Backend/service | Web | Flutter location | Flutter | Recommended action | Priority |
|---|---|---|---|---|---|---|---|---|
| RC01 | Inbox list, search, status and unread indicators | ownerInbox Inbox tab | GET /inbox, /reception/summary | I: stored inbox, not automatic all-channel ingestion | reception_page.dart | P (mock) | Connect list/search with real status and linked records | P1 |
| RC02 | Conversation/message detail and mobile list-to-thread | Reception message pane | GET /inbox payload | I | Reception selection/detail | P (mock) | Preserve thread context; full-screen mobile detail and back state | P1 |
| RC03 | Manually add incoming message/inquiry and link stay | newInboxModal | POST /inbox | I | None | M | Clearly label manual intake, source and reservation linkage | P1 |
| RC04 | Analyze message and inspect extracted fields/authority | Analyze action, analysis chips | POST /inbox/{m}/analyze | I: deterministic extraction + mode gates | None | M | Expose extracted facts and uncertainties before applying changes | P1 |
| RC05 | Generate smart draft with optional model fallback | Smart draft | POST /inbox/{m}/draft | P: local drafting plus optional external model | None | M | Preserve draft provenance and missing-fact boundaries | P1 |
| RC06 | Edit/save persisted reply draft | draft editor | PATCH /inbox/{m}/draft | I | Local draft editor | P (mock) | Persist draft; show unsaved/error state | P1 |
| RC07 | Apply extracted arrival/request/inquiry actions | Apply action | POST /inbox/{m}/apply | I for supported actions, gated by mode/authority | None | M | Review structured changes and actual execution evidence | P1 |
| RC08 | Mark externally replied / archive message | message tools | POST /inbox/{m}/reply-sent, /archive | I: bookkeeping; no send transport | None | M | Label mark-as-sent separately from sending | P1 |
| RC09 | Contextual stay/guest memory and quick navigation | message footer / guest context | GET reservation detail, /guests/{g} | I | Property name only | M | Preserve linked guest history and preferences | P1 |
| RC10 | Scheduled outbox edit/approve/cancel | Scheduled tab | GET /communications/outbox; PATCH /communications/outbox/{id}; POST /communications/outbox/{id}/approve | I: persistent preparation/approval | None | M | Add scheduled queue with truthful delivery state | P1 |
| RC11 | Simulate send versus actual channel send | outbox Simulate send | POST /communications/outbox/{id}/simulate-send | S; actual external email/SMS/OTA/WhatsApp send missing | None | M | Port simulation label; live messaging requires separate backend adapter | P2 |
| RC12 | Automation rules, authority and evaluate-now | Automations tab | GET /automation/rules; PATCH /automation/rules/{id}; POST /automation/run | P: real rule evaluation/outbox creation; no independent timed delivery | None | M | Port enable/ask/auto/never and manual evaluation; identify scheduler dependency | P2 |

### Properties and accommodation

| ID | Feature | Web location | Backend/service | Web | Flutter location | Flutter | Recommended action | Priority |
|---|---|---|---|---|---|---|---|---|
| PR01 | Property facts, occupancy/readiness preview | Today property modal | GET /properties, /properties/{p}/overview | I for configured properties | properties_page.dart | P (mock) | Expand into real property overview with operational links | P1 |
| PR02 | Same-day turnover, current and next stay | property modal | GET /properties/{p}/overview | I | No stay/handoff detail in property dialog | M | Retain all contextual facts and calendar/stay links | P1 |
| PR03 | List/create room types and capacity | property modal Add room type | GET/POST /properties/{p}/room-types | I; create can have Channex effects | None | M | Real editor with remote-side-effect warning and mapping checks | P1 |
| PR04 | Rate-plan creation and room ownership | rate management API, ARI selection | GET/POST /properties/{p}/rate-plans | P: backend creation, no complete dedicated web editor found | None | M | Add discoverable rate-plan UI; avoid inventing edit/delete APIs | P2 |
| PR05 | Property create/edit/archive administration | No general active editor found | No general property mutation endpoints found | M | None | M | Separate backend dependency; not a feature already available to port | P3 |
| PR06 | Physical room assignment/moves | Room types model; no complete physical-room allocator | No full physical-room inventory service found | M | None | M | Distinguish room-type capacity from physical unit allocation | P3 |
| PR07 | Property operational knowledge and calendar links | property modal, Train Delvane | GET overview, /knowledge; calendar client | I | Static overview only | M | Add scoped navigation without duplicating knowledge storage | P1 |

### Guests, registration and identity

| ID | Feature | Web location | Backend/service | Web | Flutter location | Flutter | Recommended action | Priority |
|---|---|---|---|---|---|---|---|---|
| GU01 | Guest lookup/history/returning-guest context | search, stay and reception guest dialogs | GET /guests, /guests/{g} | I; old directory route redirected | None | M | Contextual profiles plus searchable history | P1 |
| GU02 | Add operational guest preferences | guestPreferenceModal | POST /guests/{g}/preferences | I | None | M | Structured preference editor with source/history | P1 |
| GU03 | Registration completeness and expected guest slots | Today and reservation registration panel | GET detail, /registration, /reservations/{r}/guest-checkin-status | I | None | M | Separate data completeness, identity verification and government status | P0 |
| GU04 | Generate/copy individual secure check-in links | reservation Send guest check-in link dialog | GET /reservations/{r}/guest-checkin-links | I: generates/rotates tokens; does not send | None | M | Generate/copy/share safely; do not call this automatic messaging | P1 |
| GU05 | Prepare reminder and open reception | registration contextual buttons | POST /reservations/{r}/registration-reminder | I: persisted local draft only | None | M | Preserve draft linkage and no-external-send wording | P1 |
| GU06 | Public guest pre-check-in form and confirmation | separate guest-checkin.html | GET/POST /public/checkin/{token}; /guest/checkin/{token} | I: expiring bearer flow, manual review follows | None | M | Keep public browser journey while native owner workflow is ported | P1 |
| GU07 | Camera capture, front/back OCR, MRZ and manual correction | guest-checkin.js | Browser Tesseract; structured public submission | P: real extraction code; device/accuracy limits; not authenticity/liveness | None | M | Preserve web flow; native scanner needs separate validation | P2 |
| GU08 | OCR diagnostics, retry/timeouts and camera cleanup | guest scanner details/error states | Local browser diagnostics | P: raw OCR diagnostic visibility is privacy-sensitive | None | M | Preserve recovery; restrict/redact diagnostics, never add PII telemetry | P2 |
| GU09 | Owner verify/reject and review method/note | reservation Verify guest identity dialog | POST /reservations/{r}/guests/{g}/verify | I: verification records; queue after all verified | None | M | Dedicated owner review flow with explicit confirmation/audit evidence | P1 |
| GU10 | Sensitive registration vault read/write | Backend boundary; no active full vault editor found | GET /registration/{r}/sensitive; PUT /registration/records/{g}/sensitive | P: field encryption, not all identity data encrypted | None | M | Authorized, redacted, no-cache review; security review before native persistence | P1 |
| GU11 | Authenticated scanner ingestion | API-only developer boundary | POST /government/viza/id-scan | P: stores fields; requires owner review, not certified VIZA | None | M | Integrate only with vetted scanner/schema and owner workflow | P2 |
| GU12 | Unified standalone registration center | old ownerRegistration; current route redirects Today | GET /registration | P: retained endpoint/render function, not active destination | None | M | Proposed work queue may consolidate it; retain contextual actions | P1 |

### Cleaning, maintenance and supplies

| ID | Feature | Web location | Backend/service | Web | Flutter location | Flutter | Recommended action | Priority |
|---|---|---|---|---|---|---|---|---|
| OP01 | Cleaner My day / upcoming schedule | workerToday(false/true) | GET /worker/dashboard | I | No worker-specific screen | M | Assigned work, dates, deadlines and preparation context | P1 |
| OP02 | Start assigned cleaning task | worker task card/detail | POST /work-tasks/{t}/start | I | None | M | Persist start transition and validate assignment | P1 |
| OP03 | Finish task with worker note | worker task detail | POST /work-tasks/{t}/finish | I; checklist enforcement configurable | Operations checkbox only | P (mock) | Replace boolean with real lifecycle, note and incomplete-checklist handling | P1 |
| OP04 | Checklist read/toggle and progress | worker task dialog, reservation cleaning tab | GET /work-tasks/{t}/checklist; PATCH /work-tasks/{t}/checklist/{item} | I with assignment authorization gap to review | None | M | Port actual items and restrict edits server-side | P1 |
| OP05 | Automatically derive cleaning from reservation changes | Today/worker schedule refresh | refresh_cleaning_tasks | P: property/day aggregation and first-cleaner default | None | M | Preserve refresh semantics; multi-unit aggregation is backend debt | P1 |
| OP06 | Report maintenance with property/severity/details | cleaner/owner maintenance modal | POST /maintenance | I for owner/manager/cleaner; maintenance role cannot create | None | M | Match creation rights and actual automatic assignment behavior | P1 |
| OP07 | Maintenance list/status/severity/assignee | ownerMaintenance, workerMaintenance | GET /maintenance | P: case read implemented; worker screen additionally requests forbidden properties route | Generic sample tasks only | M | Dedicated cases and role-specific queues; fix dependency without widening guest-data access | P1 |
| OP08 | Start/resolve maintenance | case action buttons | PATCH /maintenance/{id}/status; POST /maintenance/{id}/resolve | I; transition/assignment checks need review | None | M | Port exact lifecycle and error states | P1 |
| OP09 | Owner/manager verify resolved maintenance | owner maintenance Verify | PATCH /maintenance/{id}/status | I | None | M | Keep verification distinct from worker completion | P1 |
| OP10 | Reassign maintenance | API status payload; incomplete dedicated UI | PATCH /maintenance/{id}/status assigned_to | P: weak assignee/ownership checks | None | M | Do not expose broader permissions until server validators reviewed | P2 |
| OP11 | Supplies quantity, par and estimated consumption | ownerSupplies via settings | GET /inventory; PATCH /inventory/{id} | I: local tracking/heuristic need | None | M | Port low-stock list and quantity editor; no purchasing claims | P1 |
| OP12 | Shift/attendance/payroll and purchasing automation | No working workflow found | No complete service found | M | None | M | Outside existing parity; separate scoped product work | P3 |

### Staff and team access

| ID | Feature | Web location | Backend/service | Web | Flutter location | Flutter | Recommended action | Priority |
|---|---|---|---|---|---|---|---|---|
| TM01 | People directory/contact/security posture | v283 ownerTeam People tab | GET /team/overview | I: manager can read | None | M | Team destination; server-driven read/write permissions | P1 |
| TM02 | Create member and show/copy setup password once | add-member/password dialogs | POST /team/members | I: owner; no invitation email | None | M | Sensitive one-time setup flow; never log credential | P1 |
| TM03 | Edit contact/job/role/active status | Manage member dialog | PATCH /team/members/{u} | I: owner; self-lockout guard | None | M | Preserve role change/suspension warnings and session effects | P1 |
| TM04 | Reset access and revoke member sessions | member access tools | POST /team/members/{u}/reset-access, /revoke-sessions | I: owner | None | M | Reauthentication/review UX; show exact effect | P1 |
| TM05 | Access/role permission matrix | Team Access tab | GET /team/overview | I for declared permissions, not proof all handlers match | None | M | Explain capabilities; verify real API authorization | P1 |
| TM06 | Workload by person and upcoming assignments | Team Workload tab | GET /team/overview | I: read aggregation, not optimizer | None | M | Read workload alongside task/case links | P1 |
| TM07 | Transactional invitation delivery | account creation explanatory text | No connected email adapter | M | None | M | Explicit backend dependency; preserve manual setup option | P3 |

### Intelligence, AI governance and knowledge

| ID | Feature | Web location | Backend/service | Web | Flutter location | Flutter | Recommended action | Priority |
|---|---|---|---|---|---|---|---|---|
| AI01 | Persistent operational conversation | Intelligence main thread; compatibility conversation API | GET /rosa/conversation; GET/POST /rosa/conversations; GET /rosa/conversations/{id}; POST /rosa/chat | I: stored user/org-scoped chat; compatibility new endpoint returns the same primary thread | ai_page.dart | P (scripted mock) | Persist backend thread and distinguish response provenance; do not promise multiple new threads | P1 |
| AI02 | Local factual/operational answers and routing labels | chat badges, quick prompts, legacy rosaBar | local answer/context/router; /rosa/ask, /rosa/command, /rosa/provider | I within supported intents | Generic scripted answers only | M | Preserve local facts vs reasoning vs unavailable distinction and legacy entry semantics | P1 |
| AI03 | Optional model reasoning fallback/provider status | chat, provider status | external-answer adapter; GET /rosa/provider | P: configured optional call; not unrestricted autonomy | None | M | Backend-only credentials; explicit unavailable/error states | P2 |
| AI04 | Structured proposals approve/decline | conversation proposal cards | POST /rosa/proposals/{id}/resolve | I for supported cleaning reassignment | None | M | Show payload/authority/mode and backend execution result | P1 |
| AI05 | Actual cleaning reassignment by AI command | proposal executor | _execute_proposal reassign_cleaning | I for narrow supported action | None | M | Port validated action, not generic free-form execution | P1 |
| AI06 | Observe/Assist/Autonomous mode | mode badge, v283 Simulation | PATCH /organization/mode | I: backend mode gates | None | M | Persistent visible mode; owner-only change; no implied broad automation | P1 |
| AI07 | Per-action automatic/ask/never authority | Train Delvane authority cards | PATCH /authority/{action_type} | I; declared actions exceed executor coverage | None | M | Capability matrix must distinguish supported from merely configured actions | P1 |
| AI08 | Shared/property knowledge editing and completeness | v283 ownerTrainRosa | GET /knowledge; PUT /knowledge/{scope} | I: structured operational fields | None | M | Real scoped editor, preserve exact entered text | P1 |
| AI09 | Action history, simulated/awaiting/executed counts | Simulation activity | GET /rosa/actions | I: includes simulated records | None | M | Port evidence and actors; never infer success from chat prose | P2 |
| AI10 | Undo eligible actions | Simulation undo button | POST /rosa/actions/{id}/undo | I for implemented reversible action types only | None | M | Confirm scope; handle stale/current-state conflicts | P2 |
| AI11 | Business memory and guest preference overview | Simulation memory panels | GET /memory | P: structured stored records, not general learning engine | None | M | Read provenance/confidence without claiming autonomous learning | P2 |
| AI12 | Unlimited autonomous financial/maintenance/government execution | Authority labels may mention broader actions | No complete executor for those labels | M | None | M | Do not invent; separately specify validators/providers/approvals | P3 |

### Channels and integrations

| ID | Feature | Web location | Backend/service | Web | Flutter location | Flutter | Recommended action | Priority |
|---|---|---|---|---|---|---|---|---|
| CH01 | Integration cards, status and sync summary | Settings Integrations | GET /integrations, /integration-sync/summary | I: status is configuration, not independent connectivity proof | None | M | Channels workspace with environment and last evidence | P2 |
| CH02 | Add integration slot | integration-create dialog | POST /integrations | S: creates sandbox slot | None | M | Separate sandbox creation from live connection onboarding | P2 |
| CH03 | Encrypted technical credentials/configuration | technical API, developer setup; not full active UI | GET /integrations/{i}/technical-status; PATCH /integrations/integrations/{i}/technical-config | P: backend support | None | M | Owner-controlled configuration; secrets remain write-only/redacted | P2 |
| CH04 | Booking.com commercial/property authorization | commercial-connect control | POST /integrations/integrations/{i}/commercial-connect | P: staging/onboarding intent; commercial authorization external | None | M | Truthful onboarding stages; not a completed direct Booking.com connector | P2 |
| CH05 | Channex link/discover or map existing inventory | integration dialogs | POST /integrations/{i}/channex/link; GET/PUT /integrations/{i}/channex/inventory-mapping | P: real remote adapter; staging/certification boundary | None | M | Separate discovery, mapping and remote create effects | P2 |
| CH06 | Check bookings, inbound polling/webhook and ack retry | Check for bookings / receiver status | POST /integrations/{i}/channex/receive, /integrations/{i}/channex/bookings/{revision}/ack-retry; POST /channel-bridge/webhooks/{i}; workers | P: durable receiver implemented, live approval unverified | None | M | Keep workers backend-side; expose imported/acked/retry separately | P2 |
| CH07 | Room/rate-plan mappings | inventory mapping and ARI dialogs | GET/POST /integrations/{i}/channex/rate-mappings; room mappings | I local mappings with remote dependencies | None | M | Preserve room ownership, ambiguity checks and explicit IDs | P2 |
| CH08 | Date-range rate/availability/restriction edits | Rates & availability dialog | GET/PUT /integrations/{i}/channex/ari | P: real save/outbox/remote request; OTA completion unverified | None | M | All stay restrictions, closures, currency/minor-unit and conflict validation | P2 |
| CH09 | Bulk multi-date/multi-room/multi-rate edits | bulk ARI controls | PUT /integrations/{i}/channex/ari/batch | P: implemented dispatch path | None | M | Review batch deltas before submit; avoid silent full-state overwrite | P2 |
| CH10 | Base nightly rate and rolling horizon | base-rate publisher | PUT /integrations/{i}/channex/base-rate; maintenance worker | P: persistent overrides and background queue | None | M | Show scope, overrides and distribution evidence | P2 |
| CH11 | 500-day full sync | integration Full sync action | POST /integrations/{i}/channex/full-sync | P: real recovery/certification dispatch | None | M | Explicit recovery confirmation; not a recurring frontend timer | P2 |
| CH12 | ARI queue/retry/backoff/task evidence | outgoing queue status | GET /integrations/{i}/channex/outbox; POST /integrations/{i}/channex/outbox/retry | I locally; sent means request submitted | None | M | Queue monitor; expose rate-limit pause and crash-recovery limitations | P2 |
| CH13 | Sandbox feed/new/change/cancel/outage/iCal and preview/apply | Sync sandbox, history/events | /integrations/{i}/sandbox/*; POST /integrations/{i}/sync/preview, /integrations/{i}/sync/apply; GET /integrations/{i}/feed, /integration-sync/runs, /integration-events | S for feed creation; I local import transactions | None | M | Isolated demo tools with real local-write warnings; preserve conflict/idempotency results | P2 |
| CH14 | Direct provider XML/events and other booking channels | Developer API; iCal sample UI | POST /integrations/{i}/booking/xml, /integrations/{i}/provider-events; parsers | P: normalized intake, not full direct Booking.com/Szallas.hu/Airbnb transport | None | M | Keep adapter boundaries; route supported channels through certified provider | P3 |

### Government and finance boundaries

| ID | Feature | Web location | Backend/service | Web | Flutter location | Flutter | Recommended action | Priority |
|---|---|---|---|---|---|---|---|---|
| GV01 | NTAK/VIZA readiness/certification/queue summary | Integrations government notice | GET /government/status | P: real queue/config, readiness flags not transport proof | None | M | Reports status page must accurately show locked/waiting states | P2 |
| GV02 | Government property connection configuration | API-only owner configuration | PUT /government/connections | P: credentials/config persisted | None | M | Owner editor only after official artifacts/transport review | P2 |
| GV03 | NTAK XML/VIZA payload preview and developer readiness | Backend developer endpoints; not full current web form | POST /government/{system}/preview/{r}; GET /government/{system}/developer-readiness/{p} | P: preview/test records, not official validated submission | None | M | Preview permission and redaction; separate from submit | P2 |
| GV04 | Certified government transmission/acknowledgement | Notices imply future transport | government worker stops at waiting_for_transport | M: official transport not implemented | None | M | External packages/signing/module/certification are backend dependencies | P3 |
| GV05 | Reservation amount and manual payment labels | reservation editor/overview | reservation CRUD and PATCH operations | I: records amounts/status, not payment processing | Detail displays synthetic amount only | P (mock) | Port amount/status semantics; avoid fake collected-revenue metrics | P1 |
| GV06 | Invoice issue/numbering/PDF/correction/NAV/provider | No implementation found | No invoice schema/endpoints/adapter found | M | None | M | Separate financial domain; not achievable by Flutter-only port | P3 |
| GV07 | Card charge/refund/payment reconciliation | Labels/authority terms only | No payment gateway/ledger found | M | None | M | Keep manual labels separate; require dedicated backend/provider work | P3 |

### Settings, notifications, security and support

| ID | Feature | Web location | Backend/service | Web | Flutter location | Flutter | Recommended action | Priority |
|---|---|---|---|---|---|---|---|---|
| SE01 | Persistent notification list/read/read-all | shell notification popup | GET /notifications; POST /notifications/{id}/read, /notifications/read-all | I: internal records | Static notification dialog | P (mock) | Real feed/badge/read state; not OS push | P1 |
| SE02 | Event notification preferences | Simulation preferences | GET/PUT /notifications/preferences | I: persisted choices; not external delivery | Single session-only settings switch | P (mock) | Port event-specific settings and server persistence | P2 |
| SE03 | Security posture and active sessions | Security Center | GET /security | I for stored session/read metadata | None | M | Role-limited security view, no private token exposure | P1 |
| SE04 | Revoke individual session | Security Center revoke | DELETE /security/sessions/{id} | I: owner only | None | M | Owner authorization and current-session expiry handling | P1 |
| SE05 | Audit events and retention-policy visibility | Security Center audit/retention panels | GET /audit, /retention | P: audit reads/policy display; no automatic retention enforcement | None | M | Filtered audit and truthful policy status, no invented delete workflow | P2 |
| SE06 | Reset password / email verification token flows | Backend security endpoints, not complete browser recovery UI | POST /security/password-reset/request, /confirm; /security/email-verification/request, /security/email-verification/confirm | P: hashed tokens; production email delivery absent | None | M | Coordinate native recovery/deep links with email adapter | P1 |
| SE07 | MFA/passkeys enrollment and enforcement | Team/security counts mention MFA | Stored fields only; no working MFA flow found | M | None | M | Do not render an enabling toggle until backend supports it | P3 |
| SE08 | Runtime/health/configuration diagnostics | Security runtime panel | GET /system/runtime, /health/live, /health/ready | P: real checks; conflicting release/schema metadata | None | M | Resolve metadata contract; display redacted actionable diagnostics | P2 |
| SE09 | Demo workspace reset | legacy/local demo settings action; not ordinary production nav | POST /demo/reset, DEMO_MODE guard | I: destructive demo-only reset | No equivalent; session resets on restart | M | Keep out of operational client; explicit isolated developer tool only | P3 |
| SE10 | OS push, durable offline writes and synchronization | Minimal web manifest/service worker only | No full push/offline conflict service found | M for durable workflow; P for installable web shell | None beyond native app shell | M | Separate offline/push design; never promise queued work is saved remotely | P3 |

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

The matrix is the acceptance checklist. I/P/M in the **Flutter** column is the client roll-up; P includes mock/scripted counterparts, not live parity. A feature moves to operationally complete only with endpoint mapping, correct permission checks, real state/error handling and isolated workflow tests. Related API-only capabilities are deliberately recorded rather than presented as currently reachable web controls. New functionality beyond the reference needs a separate specification.

See FLUTTER_ROADMAP.md for the navigation proposal, sequencing, dependencies and cutover gates. Keep the existing web frontend available until all required parity rows are accepted; do not replace it with a broad switch based on a visually complete dashboard.
