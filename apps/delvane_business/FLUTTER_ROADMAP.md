# Delvane Business: operational parity roadmap

Planning-only companion to [FEATURE_PARITY.md](FEATURE_PARITY.md), inspected 2026-11-11. No application code, database or integration was changed during this task. The capability IDs in that matrix are the scope and acceptance ledger. This proposal does not authorize production writes, provider testing, migrations or deployment.

## Target and migration principle

Replace the web client workflow by workflow while retaining FastAPI as the business authority. Keep the existing root-level backend, launch scripts, stable data paths, providers and web interface intact. Build within `apps/delvane_business/`; do not introduce another repository or move backend files to satisfy a client framework convention.

Visual coverage is not parity: Flutter currently has seven screens, but no backend-connected business workflows. Its two implemented matrix rows concern shell/styling; its 19 partial rows mostly demonstrate synthetic state. The first useful release should be a trusted operational workspace, not a larger set of mock cards.

Client parity and backend completion are different tracks. Invoicing, payment processing, property CRUD, certified government transmission, transactional email, working MFA, physical-room allocation and durable offline sync cannot be supplied by adding Flutter screens. Keep their dependency rows visible, but do not claim them as existing web features or silently make them launch blockers for workflows the web already performs.

## Proposed information architecture

### Owner/manager desktop

Use a compact sidebar, a scoped utility bar, a dense primary work area and contextual secondary panels. Proposed logical sections:

| Section | Default view and subviews | Preserved reference workflows |
|---|---|---|
| Today | arrivals, departures, readiness, registration review, cleaning risks, pending decisions | DY01–DY10; direct stay/property/task links |
| Reservations | calendar / list; inquiries; detail workspace | RS01–RS12; contextual messages, registration, work and activity |
| Reception | inbox / prepared messages / automation rules | RC01–RC12; contextual guest and stay links |
| Properties | overview / room types / rate plans / knowledge links | PR01–PR07; distinguish unsupported property mutations |
| Operations | housekeeping / maintenance / supplies / timeline | OP01–OP12; preserve task, case and verification lifecycles |
| Team | people / access / workload | TM01–TM07; writable owner tools, read-only manager portions |
| Intelligence | conversation / decisions / action history; knowledge and authority links | AI01–AI12; real execution evidence and bounded capabilities |
| Channels & reports | connections / mappings / rates & availability / delivery queues / government readiness | CH01–CH14, GV01–GV04 |
| Settings | workspace preferences / notifications / account & sessions / security & audit / diagnostics | SH03–SH07, SE01–SE10 |

Nine logical sections do not require nine equally prominent mobile tabs. Group sidebar items into Work (Today, Reservations, Reception), Manage (Properties, Operations, Team), and Intelligence & administration (Intelligence, Channels & reports, Settings). Team/administration can collapse into a clearly named Manage group on compact desktops. Do not bury maintenance, supplies or channel errors behind an avatar-only menu.

Keep guest profile/history and registration review as reusable routes, not duplicated forms in multiple sections. Provide a discoverable registration work queue within Today and Reception/Guest workflows, with direct links from each stay. The old Guests/Registration menu redirects are reference routing artifacts, not an obligation to hide these workflows again.

### Mobile/tablet

- Owner/manager bottom tabs: Today, Stays, Reception, Work, More. Work opens housekeeping/maintenance; More exposes every authorized remaining section with counts and clear labels. A search action remains globally available.
- Use an agenda by default on phones, optional calendar date picker, and full stay detail routes. Desktop gets month/calendar and dense lists. Do not shrink a desktop month grid until dates and guests are unreadable.
- Desktop reception uses list/detail panes; phone reception uses list → thread → linked stay with reliable Back restoration. Never lose an unsaved draft silently on tab change.
- Use a rail only when height and width accommodate it; keep the existing short-landscape drawer fallback. Work queues should scroll independently of navigation.
- Reservation edits, identity review, sensitive fields, mapping review and queue failures need full-screen mobile workflows. Small dialogs are for short confirmations, not the entire PMS record.
- Preserve selected property/date, filters, focused record and scroll position where useful. Route state must be restorable; current enum-only navigation is insufficient.

### Role-based shells and actions

| Role | Default home and primary actions | Restrictions and dependencies |
|---|---|---|
| Owner | Today; full operational sections; team and business controls | Own organization only; explicitly confirm high-impact mode, access and distribution changes |
| Manager | Today; reservations, reception, operations; permitted knowledge/integration reads/writes | Team read-only; no owner-only member changes, mode/authority/config actions or session revocation merely because a button exists |
| Cleaner | My day, Schedule, Report issue; checklist and assigned task details | No reservation finance, guest documents, integration credentials or owner dashboard; preserve task note/deadline/preparation context |
| Maintenance | My cases / unassigned available cases; start/resolve | No arbitrary reporting/editing capabilities inferred from role copy; owner/manager verifies; worker property-context API currently mismatches UI needs |
| Guest | Expiring public pre-check-in link | Keep separate browser flow; no employee app installation, organization navigation or general account session required |

Build capability-driven action guards from `/api/me` plus explicit endpoint-role rules. Persist role information only as needed for the session and always revalidate with the backend. Hiding a destination is convenience, not authorization. Invalid deep links, expired sessions and cross-organization resource IDs must fail safely.

## Visual and interaction rules

1. Retain white surfaces, ink/black text and energetic yellow for active navigation, primary actions and priority focus. Use borders and spacing for hierarchy; reserve semantic danger/success colors for actual state, with text/icons so color is never the only signal.
2. Replace the current oversized dashboard hero and ornamental chart-first layout with a compact greeting/date/property toolbar and actionable queues. Decorative branding can remain small; at a typical desktop height, arrivals, readiness problems and pending reviews should be visible without scrolling past a marketing panel.
3. Keep rounded components but offer comfortable and compact table/list densities. Align date, money and status columns; show HUF and source ownership explicitly. Do not show reservation totals as collected revenue.
4. Every status carries provenance: mock, local save, pending, awaiting approval, simulated, submitted to provider, accepted if proven, failed, or unavailable. Never collapse these into green "done".
5. Prioritize keyboard navigation, Ctrl/Cmd-K search, focus restoration, accessible labels, validation near fields, large-text behavior and adequate touch targets. Preserve the web's functional keyboard/shortcuts without copying its version-patch structure.
6. Loading, empty, stale, permission-denied, conflict, partial-delivery and network-error states are designed states. Do not replace backend uncertainty with fixture data or generic success messages.
7. Keep controls near their record: guest history, identity verification, internal note, arrival time, linked work and distribution status belong in the stay workspace. Avoid duplicate editing logic in dashboard cards, reception and settings.
8. Role-specific worker views emphasize what/where/when, checklist, preparation request and report issue, not owner KPIs or commercial controls.

## Client architecture to evolve

Keep current theme/shared widgets and feature folders. Evolve the single controller/snapshot into feature repositories and scoped state models. Separate transport DTOs from domain states; a reservation's persisted status, derived journey stage, registration completeness, verification and channel-delivery state are different types.

Add typed routes for workspace, stay detail, guest, task, case, integration and review. A record can be opened from search, Today, calendar, Reception or a notification while retaining a coherent Back target. Keep drafts and unfinished forms in an explicit unsaved-change policy; decide secure persistence separately from ordinary navigation state.

Complete the native transport seam before live screens: GET/POST/PATCH/PUT/DELETE, response headers/cookie capture, per-session CSRF, structured validation errors, timeouts/cancellation, safe retry rules, secure session storage, logout/revocation and relogin. Backend uses cookie sessions and `X-Rosa-CSRF`; do not assume a bearer-token API exists. Never retry a reservation write or full sync blindly. Query in background only after identifying side-effectful reads: generating check-in links via GET rotates tokens, and some current GET views refresh derived records.

Mock and remote repositories must be explicitly separated. A live loading failure must never fall back to synthetic guest/booking data. Keep mock mode visually labeled and deterministic for tests. Do not connect native clients directly to SQLite/PostgreSQL or embed Channex/government/AI credentials. Keep provider workers, financial decisions and authority validation on FastAPI.

## Phased implementation

Phases are acceptance milestones, not calendar estimates. Dependencies are gates, not assumed backend capabilities.

### 1. Shell and navigation parity — recommended first milestone

**Scope:** SH01–SH10; route entries for all matrix domains; permission-aware owner/manager/cleaner/maintenance shells; guest/registration/task/case/integration detail route contracts. Preserve the current premium styling and reduce dashboard decoration.

**Dependencies:** `/login`, `/logout`, `/me`, `/organization`; secure native cookie/CSRF design; remote/mock repository separation; transport method/error coverage. The worker Maintenance page's forbidden `/properties` dependency needs a worker-safe context contract, not wider owner-level access. Metadata contract ambiguity must not be hidden by inventing version literals.

**Acceptance:** isolated fixtures authenticate all four roles; unauthorized routes and writes fail; expired session returns to login without losing safe navigation context; every reference workflow has an authorized navigation home or documented backend blocker. No production integration is enabled. Phone back navigation and desktop keyboard/focus tests pass. This milestone is navigational/access parity, not an assertion that all destinations are fully operational.

### 2. Trusted Today and daily operations

**Scope:** DY01–DY10 with read-oriented operational drill-ins; notifications feed/read state (SE01); current and next-day arrivals/departures, property readiness, cleaning blockers, registration review and pending business decisions. Replace hero/static brief with compact real queues.

**Dependencies:** `/owner/dashboard`, `/operations/today-command`, `/intelligence`, `/guest-journeys`, `/properties/{p}/overview`, `/notifications`; task and stay routing stubs. Inspect synthetic timeline additions and heuristic "handled" counts before presenting them as automation evidence. Worker home uses `/worker/dashboard` separately.

**Acceptance:** fixture-driven dates/counts reconcile; queues are scoped and drill into correct records; real/synthetic events are distinguished; no claim of autonomous completion; empty/error/permission states and stale refresh are covered. Decision resolution only records the backend-supported decision effect.

### 3. Reservations and calendar

**Scope:** RS01–RS12; month/list/agenda, inquiries, full booking editor, create/edit/confirm/cancel, operational fields, notes/activity and contextual links. Read-only delivery evidence is included now even though full Channels administration waits until phase 8.

**Dependencies:** reservation CRUD, `/detail`, `/operations`, `/notes`, room-type/property reads, availability-delivery status/retry. Map confirmed/inquiry/cancelled separately from derived arriving/in-house/departing. Backend owns date/capacity checks, cancellation reconciliation and ARI jobs. Review concurrency and validation differences before claiming safe multi-user writes.

**Acceptance:** checkout-exclusive calendar nights; old and replacement stay windows reconcile after moves; inquiry confirmation/cancellation preserves history; manual closures stay closed; structured 409/validation errors are useful; monetary values avoid floating-point conversion; local saved versus queued/submitted channel results remain distinct. No direct channel HTTP from Flutter. Test date rollover/leap/month boundaries using deterministic clocks.

### 4. Reception and guest workflows

**Scope:** RC01–RC10, GU01–GU06, GU09–GU12; real inbox/search, manual intake, persisted draft, analysis/apply, mark-replied/archive, stay links, guest history/preferences, completeness, per-guest link generation, reminder draft and human verification. Prepared outbox is distinct from actual sending.

**Dependencies:** inbox/reception/outbox APIs; guest/profile/preference APIs; check-in-status/links/verify/reminder APIs; sensitive registration read contract and privacy review. Preserve the public web check-in/scanner journey (GU07–GU08) while employee flows move to Flutter. Review manual registration-status updates versus verification before exposing completion shortcuts.

**Acceptance:** drafts survive the agreed navigation/recovery policy; note/send/apply are unambiguous actions; no premature VIZA queue from self-submission; verified review records actor/method/time and produces supported events; link refresh is intentional, never prefetch; denied users cannot reveal sensitive fields. Manual replied status and simulated sends never claim external delivery. Actual email/OTA/SMS sending remains blocked until its backend adapter exists.

### 5. Properties and accommodation depth

**Scope:** PR01–PR04/PR07; real facts/readiness/handoff, room-type listing/creation, rate-plan listing/creation where supported, property knowledge and related stay/calendar routes. Room-type reads needed earlier are not delayed until this phase.

**Dependencies:** property overview, room-type and rate-plan endpoints, knowledge scopes, mapping validation and possible remote creation effects. No general property CRUD or physical-room allocation API exists; PR05–PR06 require separate backend work and must not be fabricated client-side.

**Acceptance:** room inventory/capacity and rate ownership are explicit; property IDs remain consistent across reservation, task and channel workflows; room creation does not silently mutate remote inventory; unsupported edit/delete remains clearly unavailable. Operational knowledge has one authoritative editor with contextual entry points.

### 6. Housekeeping, maintenance, supplies and staff

**Scope:** OP01–OP11 and TM01–TM06; cleaner day/schedule, start/checklist/finish-note, issue reporting, case states/verification, supplies and par levels, people/access/workload, owner account tools and one-time setup credentials.

**Dependencies:** worker/task/checklist, maintenance/status, inventory and team APIs. Resolve worker property-fetch mismatch, checklist assignment enforcement and assignee validators before broad writes. Reservation-derived cleaning aggregates by property/day; multi-unit suitability is backend debt, not something a richer Flutter list fixes. Maintenance worker reporting rights differ from label copy.

**Acceptance:** all four roles pass positive/negative endpoint tests; workers never receive finance/documents; incomplete checklist enforcement matches configuration; start/finish/verify are independent; revoked/suspended accounts cannot continue writes; one-time setup credentials are not logged; workload is labeled a read summary rather than automatic optimization. No invented payroll/purchasing/invitation email workflows.

### 7. Intelligence and AI governance

**Scope:** AI01–AI11 plus RC04/RC05 provenance and RC12 automation-rule editor/evaluate-now. Persist conversations; show local/database/model/unavailable routes; review executable proposals; knowledge, authority, modes, action history/undo and memory. Existing draft analysis can arrive earlier without general AI administration.

**Dependencies:** conversation/chat/provider/proposal, knowledge/authority/organization-mode, actions/undo/memory and automation APIs. Validate supported action inventory explicitly: cleaning reassignment in proposal executor; arrival/request/inquiry actions in inbox engine. Generic business approval records are a separate type. Provider secrets remain backend-only.

**Acceptance:** Observe changes no business records; Assist waits; Autonomous executes only supported/authorized actions; authority/mode changes and stale proposals are handled safely; chat prose never proves execution. Prompt injection and sensitive-snapshot boundaries need tests. Never translate a configured refund/discount authority label into a nonexistent executor. No unaudited client-side tools.

### 8. Integrations, government reporting and administration

**Scope:** CH01–CH14, GV01–GV03, SE02–SE09; connection/environment state, explicit inventory mappings, ARI single/bulk/base/horizon, full sync, queue/ack retries, import preview/conflicts/history, government status/preview and owner config, security/session/audit/retention/settings. Settings basics exist from phase 1; high-impact configuration finishes here.

**Dependencies:** implemented Channex services and durable workers; provider access/certification remains external. Preserve rate/currency/minor-unit semantics and throttling; fix/review sending-job crash recovery separately. Official NTAK SOAP/signature/certificate artifacts and VIZA module integration are required before GV04. Invoicing/payment (GV06–GV07), email/MFA/push/offline services are explicitly separate backend projects, not switches in Settings.

**Acceptance:** queue status survives reconnect; provider task IDs are traceable to the exact action; 429 pauses are visible; old/new dates and manual closures reconcile; full-sync scope is explicit. Secrets never round-trip in public DTOs. Government pages show waiting/locked/preview until real validated transport exists. Retention-policy display does not claim automatic enforcement. Sandbox/demo reset stays isolated from ordinary customer navigation and operational data.

## Dependency and release gates

| Dependency | Required before | Handling |
|---|---|---|
| Session/cookie/CSRF and permission contract | Any live client screen | First milestone; isolate fixtures; no invented authentication API |
| Worker property context and assignment checks | Worker maintenance/checklist writes | Backend review with negative-role tests, not frontend privilege widening |
| Room-type/status/money DTO semantics | Calendar and booking writes | Read available APIs early; keep derived and persisted states distinct |
| Verification and sensitive-data contract | Native guest completion/review | Resolve completion shortcut conflict; minimize data exposure |
| Durable delivery evidence and retry safety | Reservation delivery and ARI controls | Reuse workers/outboxes; never retry arbitrary writes blindly |
| Transactional email / messaging provider | Recovery/invitation/live sends | Backend dependency; draft/simulation parity does not imply delivery |
| Official government artifacts and acceptance | Actual NTAK/VIZA transmission | Separate certified backend implementation; status UI can ship earlier |
| Invoice/payment domain | Invoice issue, charge/refund reconciliation | New backend scope; manual amounts/statuses remain available |
| Canonical backend/release/schema metadata | Diagnostics/release labeling | Resolve the release/schema disagreement recorded in TEST_VALIDATION.md against current source; do not invent version literals |
| Device/native toolchains | Platform release claims | Preserve current Windows build compatibility script; verify Android and Apple builds on appropriate hosts |

Each phase must include typed error/permission states, accessibility/layout checks and isolated integration fixtures. Keep Flutter's current fake-transport testing and extend it with real API-contract tests against disposable backend storage only. No CI/test may adopt sibling/operational databases or contact live providers. Browser reference behavior, source handlers and tests together define intended behavior; resolve discrepancies instead of reproducing bugs.

Cut over per workflow with the web PMS available for fallback. Maintain an acceptance ledger by matrix ID: role, entry points, endpoint mappings, state transitions, tests, known limitations and owner sign-off for release. Do not remove a web destination because a same-named Flutter page exists. Final replacement requires all reference workflows accounted for, no undocumented omissions, demonstrated authorization/tenant isolation, recovery/delivery truthfulness and platform validation. Shared reference-side gaps remain visible as explicit limitations, not false parity claims.

## First implementation milestone: concrete deliverable

Implement **role-aware operational shell plus authenticated read-only Today** on isolated test infrastructure. Include the complete section/record route map, session/CSRF lifecycle, mock/live separation, worker-safe context decision, compact priority queues and cross-record navigation. Reuse current colors/components, remove the oversized decorative hero from the operational default, and keep every unfinished workflow visibly mapped with its dependency. No placeholders should imply completed writes.

Demonstrate owner/manager Today, cleaner assigned work, and maintenance case home with the correct read permissions, plus expired-session and forbidden-deep-link cases. This establishes a trustworthy foundation for reservation/calendar writes rather than expanding the disconnected demo into a misleading replacement. It deliberately combines phase 1 with the minimal read-only slice of phase 2; subsequent milestones deliver the full phases in order.
