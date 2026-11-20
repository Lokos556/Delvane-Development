# VIZA implementation roadmap

2026-11-20. The original audit plan is retained below. The subsequently authorized V01-V04 offline batch is implemented; see [V01_V04_IMPLEMENTATION.md](V01_V04_IMPLEMENTATION.md) for actual verification and bounded completion. V05-V07 are now also implemented in their unaffected offline scope; see [V05_V07_IMPLEMENTATION.md](V05_V07_IMPLEMENTATION.md). V08 offline rehearsal is complete with bounded fixes and documented build/external limitations; see [V08_OFFLINE_REHEARSAL.md](V08_OFFLINE_REHEARSAL.md). V09-V10 remain unstarted. This does not authorize installation, transmission or official validation. Use [SPECIFICATION_REVIEW.md](SPECIFICATION_REVIEW.md) as the source contract and [IMPLEMENTATION_READINESS.md](IMPLEMENTATION_READINESS.md) as the existing-code baseline. NTAK remains paused at `ntak-pre-viza-checkpoint`, migration3084; preserve its partial Task5 status and all transmission gates.

## Sequencing and scope

Immediate offline path: **V01 -> V02 -> V03 -> V04 -> V05/V06 -> V07 -> V08**. V05/V06 may be developed independently once their dependencies below exist; no parallel agents are required. Complete and verify each bounded task before expanding. Credentials are not a prerequisite for synthetic contract/model/UI/queue work. Only affected protocol operations remain blocked by Q1-Q9 in the specification review.

Later external path: **V09 provision/clarify -> V10 approved interoperability and official exercises**. Do not invent exercises, scenario IDs, certification results or protocol details. Use small synthetic engineering cases and label them as such.

Do not rebuild: actual-stay service/Flutter controls, owner identity review, token/session/CSRF boundaries, encryption/effective profile history, physical inventory/allocation/day-use, financial ledgers/closing, generic government queue/attempt foundations, certificate-loading/TLS primitives or administration navigation. Add VIZA-specific fields, IDs, projections, policy and adapters around those foundations. The V01-V04 batch adds repeatable migrations3085 (encrypted identity provenance/privacy compatibility) and3086 (logical visits and offline capture). V05-V07 adds3087 (bound dispatch, delivery attempts/outcomes, monitoring and action history). Only isolated test databases were migrated.

## V01 - Local contract assets, body serializers and business-rule tests

**Offline implementation status:** implemented in the authorized V01-V04 batch, subject to documented protocol/source-data holds and outstanding device/deployment checks. Evidence and limitations: [implementation report](V01_V04_IMPLEMENTATION.md).

**Can start offline. Dependencies:** supplied v700 PDF only. Source: sec4.2-4.4 pp10-27; sec5 pp28-43; sec6 pp44-57.

- Add a reviewed standalone transcription/extraction of the embedded WSDL with source hash/page provenance; retain the original PDF unchanged. Reuse safe lxml/no-network/no-DTD/size-limit patterns; do not replace the NTAK namespace or schemas.
- Implement typed request/response DTOs and unsigned business-body serialization for all4 operations. Enforce element order, required-versus-nillable distinction, lowercase UUID formatting,1-10 guest batches, tax-number formatting, UTF8 byte/character limits and the73 supplied business error mappings. Keep source parameters explicit where server settings are not known.
- Preserve raw codes and multiple per-arrival results. Test valid empty strings only where the schema/type allows them, not empty dates/enums. Register the supplied invalid examples as negative documentation evidence, not successful fixtures. Do not silently patch schemas.

**Acceptance/verification:** four request/response contract paths validate using unchanged XSD; empty/max/over-limit batches; all12 identity subfields and3 third-country fields round-trip with nil/value distinctions; Unicode254-byte vs200-character boundaries; full73-code mapping coverage; rejection of entities/DTD, malformed namespace/operation and oversized XML. Audit extraction already compiled: this task adds application integration/tests, not a second specification audit. Outer WS-Security remains an explicit interface until V09 resolves Q2.

## V02 - Persistent identity provenance and VIZA completeness

**Offline implementation status:** implemented in the authorized V01-V04 batch, subject to documented protocol/source-data holds and outstanding device/deployment checks. Evidence and limitations: [implementation report](V01_V04_IMPLEMENTATION.md).

**Can start offline. Depends on:** V01 definitions. Source: sec4.2 pp10-12; sec5 pp34-39; sec6.1 pp46-49; sec6.3-6.4 pp50-57.

- Extend existing encrypted guest-source/history infrastructure for immutable original reader field values and distinct reviewed manual/correction values. Retain full-name display fields for compatibility, but add explicit surname/given, birth-surname/given and mother's-surname/given pairs. Store raw code/value, source, actor, time, document/read context and correction reason separately. Legacy originals that were not retained must remain unknown, not reconstructed from a mutable current row.
- Add three third-country facts and explicit operator-reviewed applicability. Implement the unambiguous country mappings and all291 accepted alpha2 codes from the supplied appendix without changing NTAK's country set. Reject/hold ambiguous NLD->NL/BQ conversion and do not guess meanings for special accepted codes or XKX/XKA variants.
- Add VIZA readiness/validation distinct from NTAK hash/profile readiness. Under14 document exemption must use actual arrival date; do not use the under18 IFA rule. Preserve owner review. Birthplace and unprinted optional identity fields must not be fabricated or universally required. Replace fixed1920 and YY-century assumptions only with reviewed, tested date handling appropriate to the source; ambiguous MRZ centuries require confirmation.
- Address plaintext duplicate storage/capture paths and masked read models before enabling any sender. Reuse encryption/key infrastructure; define access/retention for new originals and protocol snapshots. Do not retain document images merely to implement field provenance. Keep real data out of test fixtures and logs.

**Acceptance/verification:** original + corrected pair survives edits/restart; editing either name partner projects both manual fields, leaving original scan unchanged; missing optional birthplace/mother/birth names;14th birthday the day before/on/after arrival vs later reporting; valid110-year boundary; code/country ambiguity; third-country data/nonapplicable nils; actor/source spoofing denial, cross-property/tenant denial, CSRF; additive migration twice; plaintext identity values absent from new outbox/general audit outputs. Do not weaken existing frozen-ID/profile/review assertions.

## V03 - Extend scanner ingestion and normal guest/reception controls

**Offline implementation status:** implemented in the authorized V01-V04 batch, subject to documented protocol/source-data holds and outstanding device/deployment checks. Evidence and limitations: [implementation report](V01_V04_IMPLEMENTATION.md).

**Can start offline. Depends on:** V02. Source: sec1.1 p4 (reader mechanics outside this contract); sec4.2 pp10-12; sec6.3 p50.

- Extend the existing browser scanner submission contract to deliver original parsed field components/codes before user edits plus explicit manual changes. Existing camera/OCR/MRZ machinery stays in place. A scalar camera scan_method or checksum confidence is not field provenance or owner verification.
- Stop treating missing birth name copied from full_name as an original scan. Retain reviewed/display convenience separately if required, with its real provenance. Do not infer world-name splits from existing combined strings. Add paired-name and visa/entry review controls using current Flutter reservation/reception workflow and HU/EN conventions.
- Show age-dependent document requirements, unread/optional fields and required review clearly. Check first-load OCR assets/network assumptions: the current scanner loads Tesseract from a CDN even though images are processed locally. Do not claim offline asset/device support without testing it.

**Acceptance/verification:** existing4 JS suites continue passing; add field-provenance/paired-correction tests, front/back no-overwrite checks, unchanged original Unicode/MRZ text versus reviewed correction, no inferred birthplace/birth name, minors without document IDs, unsupported/no-MRZ manual provenance. Flutter/mobile/desktop tests use existing controls and mocks. No automatic arrival or verification on scan/registration completion. Actual OCR engine and camera accuracy remain V10 evidence unless separately tested with controlled local fixtures.

## V04 - Per-guest arrival UUID and transactional VIZA capture

**Offline implementation status:** implemented in the authorized V01-V04 batch, subject to documented protocol/source-data holds and outstanding device/deployment checks. Evidence and limitations: [implementation report](V01_V04_IMPLEMENTATION.md).

**Can start offline for documented operations. Depends on:** V01-V03. Source: sec2.2 p5; sec4.2 p11; sec4.3 p14; sec6.2 p50.

- Add a VIZA visit/arrival identity mapping to the existing actual-stay transaction. Each real guest visit receives a unique durable lowercase UUID, including each member of a group; keep message UUIDs separate. Do not use reservation IDs, NTAK frozen guest hashes, group event UUIDs or per-transfer occupancy segment UUIDs as the visit identity.
- Actual arrival/departure automatically captures an immutable encrypted VIZA projection and government outbox work. Preserve operational events with clear recoverable blockers when identity/config/protocol facts are missing; no fabricated values or NTAK-normalization dependency for VIZA. Do not send legacy reservation.created/registration_verified preparation records as arrivals. Define deliberate handling of old pending rows without inferring occupancy.
- Departure references the same original arrival UUID; transfers within a property retain visit identity. Erroneous arrival emits the documented departure closure and permanently retires that UUID; a subsequent genuine arrival gets a new one. Preserve shared PMS/NTAK correction history but block unsupported VIZA reversals/after-send identity/timestamp changes pending Q5. Distinguish never-sent replacement versions from accepted/uncertain submissions.
- Preserve exact observed timestamps. A historical noon fallback, if supported, must be an explicit reviewed operation when the real time is unknown, with the mandated source distinction, never a scheduled-time default. Same-day VIZA expected-departure handling remains Q6; leave true PMS day-use unchanged.

**Acceptance/verification:** individual/group/multi-unit visits,10+ guests split into allowed message batches, delayed individual arrival, transfer/restart stability, UUID nonreuse after erroneous arrival, later new visit, duplicate requests, concurrent claims, rollback with no orphan report, cancelled/nonconfirmed booking denial, registration-only creates no THF arrival. Unknown outcomes and unsupported corrections are visibly held; NTAK/occupancy/financial facts still persist correctly.

## V05 - Property signature and gated certificate/transport interfaces

**Offline implementation status:** implemented with45 new focused backend checks and10 Flutter administration checks, plus preserved V01-V04 regressions. Official transport, unresolved protocol cases and deployment/device validation remain gated. See [V05_V07_IMPLEMENTATION.md](V05_V07_IMPLEMENTATION.md).

**Offline portions can start. Depends on:** V01,V04. Source: sec3 pp7-8; sec4.4 pp15-27; sec5 p38; EF0200-0209 pp49-50.

- Reuse server-held certificate/key references and credential checks; model correct property8-character reporting ID/CN, provider identity, environment and issuer/root trust binding. A10-character NTAK registration number is a different field. No keys/certificates in Flutter/source control, and no replacement credentials.
- Implement the unambiguous property-validation check string and standard RSA-SHA256 signature with disposable test-only key material in isolated tests: ordered arrival UUIDs, exact reporting timestamp, no trailing newline, correct Base64 DER/public certificate and signature encoding. Do not accidentally hash twice through a higher-level signature API.
- Define verified-HTTPS transport and outer WS-Security sign/verify interfaces, with injected offline mock services. Keep unresolved outer profile, signed-response validation policy and actual CA/credential binding fail-closed. Do not copy SHA1/long timestamp examples or relax certificate verification to get tests to connect.

**Acceptance/verification:** deterministic signed-string bytes, multiple guests/order, timestamp/UUID/property tampering, signature verification, wrong CN/property/environment, key mismatch/expiry/untrusted CA/hostname rejection, missing trust/config blockers, no real key reads/network. Normative outer security interoperability is V09/V10, not a mock success claim.

## V06 - VIZA durable delivery, THF monitoring and recovery

**Offline implementation status:** implemented with45 new focused backend checks and10 Flutter administration checks, plus preserved V01-V04 regressions. Official transport, unresolved protocol cases and deployment/device validation remain gated. See [V05_V07_IMPLEMENTATION.md](V05_V07_IMPLEMENTATION.md).

**Core/mock work can start offline. Depends on:** V01,V04,V05 interfaces. Source: sec4 pp9-10; sec5 pp29-33,40; sec6.2 p50.

- Extend existing government queue/attempt/worker infrastructure with VIZA-specific persisted due times, leases/claim IDs, immutable business snapshots/digests, environment/property binding, per-arrival outcomes, receipts and receipt times. Preserve NTAK's separate policy and existing jobs. Keep protocol/wire signing timestamps distinct from immutable business facts.
- Implement the recommended technical retry schedule with an injected clock/random source:3 immediate attempts, random1-60s,10m,1h,6h, then24h continuously. Retry definitely-not-sent technical failures; do not treat permanent validation errors as transport retries. A timeout after possible receipt is uncertain, not permission to manufacture a new arrival UUID or blindly retry; Q7 must define safe reconciliation for that path.
- Schedule status calls every1-60 minutes independent of the current30-second worker tick. Parse all primary/additional health codes and observe counters/time/software version. Retrieve both NEMBEKULDOTT/HIBAS lists with property/message correlation, multiple errors, result codes and the10000 cap. Do not infer individual VIZA delivery merely from absence in a list.
- Keep stale/unknown health distinct from zero counts. Persist pending work across process restart/outage; never block PMS business actions. Expose technical retry state separately from THF acceptance and downstream rejection.

**Acceptance/verification:** deterministic clock-based schedule; crash before/after claim/send/receipt, restart and dedup; missing configuration isolation; malformed/oversized/signed-response rejection; mixed guest results held safely; OK/WARNING/ERROR plus every documented flag; polling cadence and stale state; both list selectors/empty/result-error/cap reached; cross-property lists and message mismatch; permanent-error/manual-review cases. No live retries are enabled by this offline task.

## V07 - Normal Flutter VIZA administration and source-linked diagnostics

**Offline implementation status:** implemented with45 new focused backend checks and10 Flutter administration checks, plus preserved V01-V04 regressions. Official transport, unresolved protocol cases and deployment/device validation remain gated. See [V05_V07_IMPLEMENTATION.md](V05_V07_IMPLEMENTATION.md).

**Can start with mocks. Depends on:** V02-V06 read models. Source: sec4.1 pp9-10; sec5 pp32-33,40; sec6.1 pp44-50.

- Extend existing government administration with property-scoped VIZA health, poll timestamp, unsent/rejected counts, per-guest arrival/departure/receipt state, durable blockers and safe action history. Do not label local queue size or a certification/configuration flag as actual THF health/connection.
- Display multiple structured error codes and localized explanations; link to normal identity/source correction workflows. Preserve raw/scanned/manual field distinction. Show when an already-sent correction cannot legally be executed and requires official guidance; never expose XML editing or a fake resend-success button.
- Add authorized list retrieval and constrained recovery controls; redact general logs and sensitive diagnostic exports. Preserve existing NTAK reporting dialog, reception, day-close and financial controls.

**Acceptance/verification:** HU/EN mobile/desktop tests for unknown/stale/warning/error/counters, per-guest errors, missing credentials, blocked protocol actions, no accidental repeated submission after timeout/refresh failure, role/property isolation and CSRF. Confirm application operation during THF outage.

## V08 - Offline combined rehearsal and security regression checkpoint

**Status:** completed as an offline engineering rehearsal, not certification. Nine combined synthetic checks, existing VIZA/PMS/NTAK regressions, full Flutter/analysis/JS and Windows release evidence are recorded in [V08_OFFLINE_REHEARSAL.md](V08_OFFLINE_REHEARSAL.md). Android release is blocked by missing cached dependencies; PostgreSQL/device/official interoperability remain outstanding. Read [VIZA_HANDOFF.md](VIZA_HANDOFF.md) and [EXTERNAL_READINESS_CHECKLIST.md](EXTERNAL_READINESS_CHECKLIST.md) before any new task. No V09/V10 or live transport work was started.


**Can be completed without credentials for all resolved paths. Depends on:** V01-V07. Source: all documented business/protocol rules; no official scenario identifiers invented.

Build synthetic engineering flows through ordinary guest/reception/stay APIs and Flutter: scan+manual pair correction, reviewed minor with no document, nationality edge case, applicable/nonapplicable third-country values, group arrivals, transfer, departure, erroneous-arrival closure/new visit, restart/outage and corrected never-sent data. Use mock THF services and disposable fictional data. Document unsupported paths as explicit blockers rather than changing schemas or simulating official acceptance.

**Acceptance/verification:** focused VIZA contract/provenance/UUID/security/retry/UI suites plus existing scanner4 scripts, guest registration/lifecycle, actual stays, physical allocations/day-use, NTAK profiles/reporting, financial/closing and tenant/CSRF regressions. Run Flutter analyze/tests and authorized local Android/Windows builds when requested; record exact results/failures. Preserve known v293 registration-state failure separately unless an independently demonstrated in-scope fix addresses it. Verify NTAK tag unchanged and no operational storage/credentials accessed. Update these documents with actual completed state before proposing live work.

## V09 - Obtain and verify external prerequisites

**Blocked on issuance/clarification; no endpoint access in this assignment. Depends on:** V05 design and official support materials.

Required: test-access acceptance/assigned endpoint and IDs; correct property/PMS certificate roles and CN bindings; THF installation/operations guide; THF issuer/root CA files; normative WS-Security/response-signature profile and machine-readable success/error/multi-error samples; Q5/Q6/Q7 operational procedures; official validation exercises and evidence instructions. The embedded schema is already sufficient for offline contract work: do not request nonexistent external XSD imports as a blanket blocker.

**Acceptance/verification for a later authorized task:** install/configure only in an isolated developer environment, reuse legitimately issued existing credentials where officially applicable, verify key match/trust/expiry/host/property and signed examples, keep production/staging isolated, maintain a deliberate live-transmission gate. No guessed test exercises, production exposure, database reset or credential replacement.

## V10 - Device/OCR evidence, test THF interoperability and official validation

**Requires explicit later authorization and supplied official materials. Depends on:** V08,V09; resolved operation-specific gates.

- Verify Windows/reception and Xiaomi15/browser camera/permissions, focus/rotation/front-back, glare/blur, Unicode names, TD1/2/3/non-MRZ documents and manual provenance using controlled approved test material. Measure image-to-field accuracy independently of parser unit tests. The old0/18 synthetic-strip artifact is not certification/device evidence.
- Run against the assigned test THF only after trust/signatures/configuration are verified; exercise receipt versus downstream status, list retrieval, outage/recovery and nonreuse according to the approved procedure. Preserve protected evidence and avoid exposing real identity data/secrets.
- Execute the official exercises exactly as supplied and record limitations. Do not manufacture a scenario list or claim certification from mock responses. Only after verified results can a later readiness decision discuss live use; production deployment is outside this roadmap's current authorization.

## Verification commands available now

These reuse guarded offline tests; they do not start a persistent workspace or contact THF. Current completion evidence and expanded commands are in the V08 report:

```powershell
Set-Location C:\Delvane\Delvane-Development
node tests/test_mrz_parser.js
node tests/test_guest_scanner_parser.js
node tests/test_v21089_hungarian_id_ocr.js
node tests/test_guest_registration_ui.js
.\.venv\Scripts\python -B -m pytest tests/test_guest_checkin.py tests/test_guest_checkin_lifecycle.py tests/test_v3000.py tests/test_actual_stays.py tests/test_guest_reporting_profile.py -q
```

The audit executed these successfully:4 JS scripts and29 backend tests (2 dependency warnings). Contract compilation/example checks were separate audit-only checks. Full Flutter/build/device/OCR/live results were not newly produced by this audit. See the NTAK handoff for the larger regression baseline to preserve during subsequent implementation.
