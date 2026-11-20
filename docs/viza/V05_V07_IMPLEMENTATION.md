# VIZA V05-V07 offline implementation

2026-11-20. Uncommitted additions on `main`, preserving V01-V04 and the protected NTAK HEAD/tag `7b9ead2dd7ea5196aee6dd28731aa841738c62c2` / `ntak-pre-viza-checkpoint`. Latest migration: **3087**. **Official communication remains disabled.** V08-V10 and NTAK15-20 were not started.

## V05: property signing and secure-channel foundations

`viza_security.py` reuses `government_security.credentials` for safe server-held file references, RSA/key matching and validity dates. Existing NTAK defaults were not changed. The inherited4096-bit minimum is an existing local credential policy, not a new claim about the v700 normative key-size requirement.

Property validation implements sec3.2-3.3 pp7-8 / schema p38: exact8-character property reporting ID, ordered arrival UUIDs and exact lexical reporting timestamp joined by ASCII `|`, without trailing newline. RSA PKCS#1 v1.5 with SHA256 hashes the original message exactly once; certificate is Base64 DER and signature is Base64. Verification pins an expected certificate fingerprint and detects timestamp/order/UUID/certificate tampering. `viza_contracts.serialize` now supports an explicitly checked lexical timestamp so the signed string and serialized `bejelentesIdopontja` cannot diverge through UTC/fraction formatting. The original schema assets are unchanged.

An operator-managed `binding.json` beside a server credential reference must explicitly identify system VIZA, organization, property, environment, reporting ID, endpoint and certificate SHA256; certificate CN must match. This prevents silently treating an existing NTAK credential as an approved VIZA credential. No current credential, private key, CA file or deployment installation was inspected or changed.

TLS construction requires explicit issuer/root CA certificates, hostname and chain verification, client credentials, minimum TLS1.2 and a context bound to the exact property/environment/endpoint. Missing trust, key mismatch, expiry, wrong CN/fingerprint and binding changes fail closed. `VerifiedHttpsTransport`, `OuterSecurity` and response-verification interfaces define the boundary; there is **no live HTTP connector**, and the default security profile rejects Q2 signing/verification. `DisabledOfficialTransport` always refuses communication. `OfflineMockTransport` can only run the worker in the guarded test environment and is never selectable through an API/settings flag.

`viza_delivery.render_bound_job` composes a property-signed business body from immutable captured facts, an explicitly supplied server credential reference and the frozen property configuration. This is not an outer SOAP signature or permission to send.

## V06: durable delivery and monitoring

`viza_delivery.py` extends the existing government outbox/attempt infrastructure rather than introducing another backend. Each captured job can bind once to an encrypted configuration snapshot, environment, digest and reporting timestamp. Business occurrence time, report-header timestamp and per-attempt wire timestamp remain separate. Configuration identity changes hold existing work; changing polling frequency does not rebind or strand messages.

Durable claims have identifiers and leases. Before an exchange, the attempt and sending state are committed atomically with a generic `government_delivery_attempts` row. A crash before sending can release an expired claim; a crash after the possible-send marker becomes uncertain. Concurrent workers cannot claim the same package. Every departure dependency is tracked per arrival package, including multi-unit/group histories. A THF acceptance prerequisite is distinct from downstream VIZA delivery.

The documented retry policy (sec6.2 p50) is implemented with injected time/randomness: attempts1-3 immediate; after failure3 random1-60 seconds, then10 minutes,1 hour,6 hours, and24 hours thereafter. Only definitely-not-sent failures automatically retry. Permanent validation failures stop. Uncertain responses, interrupted sends, malformed/oversized receipts, UUID mismatches and unsupported corrections never trigger blind replay or a new arrival UUID.

Receipts retain encrypted full response data and correlate every guest UUID. General diagnostics expose recognized codes, not sensitive free-form server text/XML. All73 official error codes have English descriptions and source Hungarian explanations/page references. Multiple codes and individual outcomes persist. Mixed/global-boolean contradictions are held under Q4; an OK candidate in a mixed receipt is not displayed as established batch success. A THF receipt never sets downstream delivery to confirmed.

Both monitoring operations are implemented with injected mocks. Status polling respects configured1-60-minute intervals, persistent due times/claims, all9 additional flags, compound primary statuses, actual counters, software version, local observation time and THF timestamp. CERT-EXPIRED requires ERROR as explicitly stated on p10. Health starts unknown with null counters and becomes stale after two configured polling intervals without a newer observation; this is a local freshness policy, not an official delivery rule.

Both NEMBEKULDOTT/HIBAS lists retain encrypted observations, property/message/environment correlation, multiple recognized error codes, unknown-message diagnostics and the10000-item cap. Cross-property payloads are held rather than exposed. Current shared-THF mixed-property response handling is deliberately conservative; filter/authorization behavior must be confirmed during provisioning. Downstream list rejection is recorded at message level; a multi-guest rejection does not manufacture individual guest outcomes. Empty lists never imply delivery. Local stored-list paging is not an invented THF pagination protocol.

The existing30-second government worker invokes VIZA synchronization/monitoring through the disabled runtime transport. PMS arrivals/departures, NTAK and financial/closing operations remain usable during simulated outages. Mock observations and attempts are persistently labelled mock.

## V07: normal administration and safe recovery

`viza_api.py` and Flutter `lib/features/pms/viza_reporting_dialog.dart` extend the existing Integrations government section. They provide property-scoped readiness, unknown/stale/mock health, THF counters/version/timestamps, queue and per-guest outcomes, recognized localized errors, identity-source links, attempt/action history and stored unsent/rejected lists. Credentials, keys and unrestricted XML/resend controls are absent. THF counters are labelled as potentially shared across properties, separately from the local queue.

Owner/manager access and property/organization checks reuse existing authentication. Settings are owner-only; existing cookie/CSRF checks protect mutations. Normal identity editing remains in the existing reception workflow. Only never-sent blocked arrival facts can be refreshed into immutable revisions; only definitely-not-sent retry work can be rescheduled. Accepted/uncertain packages cannot be replayed by operator controls. Readiness/configuration saving never reports a successful connection, certification or official acceptance. Actual remote observation/list actions explicitly return blocked while transmission/security remain disabled.

API prefix: `/api/government/viza/properties/{property_id}`:

- GET overview; PUT `/settings` for safe public property/poll settings (no credential upload/live toggle).
- POST `/observe`; POST `/lists/{NEMBEKULDOTT|HIBAS}`: transport-gated monitoring/retrieval.
- GET `/lists/{selector}?offset=0&limit=100`: authorized paging over the latest stored scoped observation, maximum500 per local page.
- POST `/jobs/{job_id}/recover`: `refresh_identity` or `retry_not_sent` only, with durable action results.

The UI shows the latest200 job summaries and20 attempts per job; action history is bounded to50 entries. Lists retain the complete capped response and display100 rows per local page. These are diagnostic-view limits, not loss of durable history or official pagination claims.

## Migration and compatibility

**3087 `viza_delivery_monitoring`** adds repeatable tables: `viza_settings`, `viza_dispatch`, `viza_attempts` linked to existing government attempts, `viza_guest_outcomes`, `viza_message_status`, `viza_job_dependencies`, `viza_monitor_schedule`, encrypted `viza_observations`, and `viza_actions`. A trigger freezes an already bound environment/configuration/report timestamp. V01-V04 snapshots/UUIDs remain intact. No persistent/operational database was opened or migrated. SQLite migration/restart behavior was tested; PostgreSQL-specific trigger DDL remains unverified against a real PostgreSQL server.

Relevant edits: `app.py` migration/API/worker hooks; `viza_contracts.py` lexical timestamp preservation; `viza_reporting.py` shared immutable-fact body builder; `integrations_page.dart`, new reporting dialog and `assets/native-hu.json`. No NTAK signing, hash, financial, inventory or booking business logic was replaced.

## Verification

- **85 distinct focused VIZA checks passed across final focused runs:**40 V01-V04 regressions,37 delivery/monitoring/API tests and8 security tests. The combined run before the final race test was84/84 (65.11s); the final delivery rerun was37/37 (35.55s), and the final bound-trust security rerun8/8 (7.65s). These include the late-before-send supersession guard and polling-setting changes without rebinding message identity.
- Broader backend: **207 passed,1 failed**,2 existing dependency deprecation warnings,273.70s. The failure remains `tests/test_v293.py::test_modification_preserves_manual_fields_and_cancellation_updates_cleaning` (expected registration `complete`, actual `incomplete`), already documented before V05-V07. No assertion or unrelated business rule was changed. This run covered VIZA, guest registration/verification/lifecycle, physical units/allocations, reservations/Channex, day-use, NTAK profiles/contracts/reporting, financial ledger, daily closing and isolated persistence. The final narrow safety refinements were checked in the focused reruns rather than repeating the entire broad suite.
- Flutter: **297 passed**,57s (288 existing +9 VIZA administration tests at that run). Latest targeted HU/EN390/1200-width administration/recovery/stored-list-refresh rerun: **10 passed** (one additional pagination-refresh regression). Latest analysis: **no issues**,2.3s.
- JavaScript: all5 scanner/UI/provenance scripts passed unchanged.
- `git diff --check`: clean; official PDF hash and protected HEAD/tag verified unchanged.

Reproduce from the repository root:

```powershell
.\.venv\Scripts\python -B -m pytest tests/test_viza_security.py tests/test_viza_delivery.py tests/test_viza_contracts.py tests/test_viza_identity_capture.py -q
.\.venv\Scripts\python -B -m pytest tests/test_guest_checkin.py tests/test_guest_checkin_lifecycle.py tests/test_v3000.py tests/test_actual_stays.py tests/test_guest_reporting_profile.py tests/test_physical_units.py tests/test_reservation_allocations.py tests/test_normal_reporting.py tests/test_day_use.py tests/test_financial_ledger.py tests/test_business_days.py tests/test_ntak_reporting.py tests/test_ntak_contracts.py tests/test_persistent_development.py tests/test_v293.py tests/test_v2991.py -q
node tests/test_mrz_parser.js
node tests/test_guest_scanner_parser.js
node tests/test_v21089_hungarian_id_ocr.js
node tests/test_guest_registration_ui.js
node tests/test_viza_scanner_provenance.js
Set-Location C:\Delvane\Delvane-Development\apps\delvane_business
flutter analyze --no-pub
flutter test --no-pub
```

Ignored local evidence: `build/viza-audit/v05-v07-{backend-final,focused-final,delivery-final,security-final,analysis,flutter-final,flutter-focused}.txt`.

All new credentials are generated only inside isolated synthetic tests; TLS trust/hostname tests use SSL MemoryBIO and no sockets or official service. Sources: `tests/test_viza_security.py`, `tests/test_viza_delivery.py`, existing V01-V04 suites, and Flutter `test/viza_reporting_test.dart`. Existing assertions were preserved. Temporary test-fixture clock/delay issues found during development were corrected; no product test expectation was weakened.

No Android/Windows compilation, physical Xiaomi test, camera/OCR accuracy test, official THF installation/interoperability or certification exercise was performed. Flutter3.50.0/Dart3.14.0 were preserved.

## Remaining blockers and V08 readiness

All Q1-Q9 remain in [SPECIFICATION_REVIEW.md](SPECIFICATION_REVIEW.md). Q2 blocks outer signing/response verification and every real exchange; Q4 holds mixed receipts; Q5 submitted corrections; Q6 same-day expected departure; Q7 uncertain replay/delivery confirmation/list-cap behavior; Q8 country ambiguity; Q9 conditional/server parameters retain their operation-specific restrictions. Q1 assigned endpoint/bindings and Q3 corrected machine-readable examples remain external requirements. The unambiguous property signature implementation does not resolve Q2.

V08 can now begin as a separately authorized **offline combined rehearsal** using the captured guest lifecycle, signatures, mock delivery/monitoring and normal UI. It has not been performed as a new roadmap task. Preserve the known v293 failure as a separate issue. Before later V09/V10, obtain official test access, THF installation/operations material, VIZA-specific property/PMS credential roles/bindings, issuer/root trust and a normative outer security/response profile plus official exercises. No official acceptance or deployment readiness is claimed.

No operational data, existing private keys, real guests, official endpoints, deployment, credential replacement, commit, push or checkpoint-tag modification occurred.
