# Pilot 01 · Complete guest stay

One synthetic guest completed an overnight stay through the normal PMS HTTP APIs on disposable PostgreSQL 17.12. The rehearsal used one rentable apartment, the existing synthetic communication path and the same reservation, guest, physical unit, turnover task and folio throughout. It recorded an early departure, completed the assigned checklist, settled a HUF 12,400 folio, calculated HUF 400 IFA, closed two business days in order and verified persistence after an application restart.

## Original capability and Pilot 01 result

| Step | Before Pilot 01 | Pilot 01 result and evidence |
| --- | --- | --- |
| Booking creation and channel sync | Working in local workflows and mocked Channex regressions. | Direct booking was created through the reservation API. Duplicate creation was rejected. Inbound Channex and sandbox import now prepare the same invitation. Live channel traffic was outside this rehearsal. |
| Reservation confirmation | Working. Direct create confirms, inquiries can become confirmed, and channel imports confirm existing bookings. | A confirmed booking creates one durable invitation with its own state. Inquiries and cancellations cannot issue links. |
| Automatic pre-check-in invitation | Partial. The existing automation could prepare reminder text, and an operator could issue individual links. | Confirmation automatically prepares a Reception item. The operator approves and simulates it locally, then sees one link per outstanding guest. Live external delivery is blocked by the absence of an approved sender and guest-facing HTTPS origin. |
| Guest pre-check-in and ID capture | Working through secure guest tokens and encrypted identity capture. Physical camera quality still needs verification. | The public API rejected incomplete adult identity, accepted valid synthetic manual data, and rejected reuse of the consumed token. |
| Identity review and correction | Working through scoped review, encrypted sources and explicit verification. | The owner set the reporting profile and verified the guest. A later reporting-profile change still requires renewed identity review. |
| Actual check-in and arrival | Working through audited, idempotent actual-stay operations. | Owner recorded a real PMS arrival against the assigned physical apartment. Property readiness showed occupied. |
| Stay and room management | Working for physical allocation and actual movement with existing operational constraints. | The rehearsal used the normal physical-unit and allocation APIs. No room move was needed for the single-apartment stay. |
| Guest checkout | Partial. Actual departure was persisted, with overnight task timing still driven by planned dates. | Final actual departure updates the existing turnover in the same transaction. Partial departures leave the task blocked while guests remain checked in. Duplicate checkout requests retain one actual event and one turnover. |
| Automatic cleaning scheduling | Partial. Overnight tasks were generated from planned dates, and day-use already had separate per-unit handling. | Early or late final checkout adjusts the overnight schedule to the observed local date and time. The task ID, assigned cleaner and checklist survive the adjustment. |
| Cleaner completion and room readiness | Partial. The assigned-worker checklist worked, but property readiness could look ready without a near-term arrival. | The worker sees the actual checkout blocker, and the API enforces it. A checkout-backed overnight task requires the checklist to be complete. Owners see occupied, cleaning pending and ready as the single-apartment workflow progresses. |
| Financial closing, invoicing and reporting | Local ledger, IFA and daily closing worked. Live invoice issuance was missing and official reporting was externally blocked. | The same reservation's accommodation charge, IFA and recorded cash settled to HUF 0.00. Two encrypted close snapshots persisted. Local reporting preparation stayed gated. Invoice issuance and payment processing still require an external integration. |

## Implementation

- [Backend booking and operations](../../app.py) reuses the communication outbox, secure guest token table, worker assignments and existing audit log. No database migration was needed. The schema remains at 3090.
- [Actual-stay operations](../../guest_stays.py) reconcile overnight turnover with the final observed departure and recalculate pending work after a supported departure correction. Planned booking dates, physical allocations and channel selling availability are unchanged by checkout scheduling.
- [Flutter Reception](../../apps/delvane_business/lib/features/pms/reception_page.dart) shows preparation, approval and simulation. Links appear only in the authorized response dialog. The reservation preparation section shows the invitation state. Operations displays observed arrival and departure when recorded, including guests still checked in past their planned checkout. Active Today, Operations and worker Schedule views check their current page for updates every 30 seconds.
- The existing invitation and cleaning APIs handle scoped retries. A failed local link issuance rolls back both tokens and the outbox status. Duplicate simulation requests return the recorded status without regenerating links. Booking date, property, party and confirmation changes revoke active links before preparing any replacement. A booking with mismatched guest slots requires review.
- Existing manual link generation remains available when the operator needs a replacement after a lost response. The system stores token hashes and does not add bearer links or identity details to audit and outbox records. Public submission and owner verification remain separate actions.
- A retry of an unchanged partial sensitive-data edit preserves the subsequent verification. The backend compares the merged encrypted record with the stored values before invalidating review.

## Verification

- The [connected PostgreSQL rehearsal](../../tests/pilot_postgres_rehearsal.py) passed through the actual HTTP application, with zero published container ports, an internal IPv4-only Docker network, container IPv6 disabled, no upstream DNS and an application with no default route. It used a run-specific database, credentials and encryption key. Restart checks confirmed the simulated invitation, completed cleaner note and both decryptable snapshots. The runner removed its disposable containers and network.
- The [Pilot regression tests](../../tests/test_pilot_guest_journey.py) cover failed issuance rollback, concurrent simulation, replacement and cancellation, and a partial departure followed by late final checkout.
- Backend verification ran in separate, overlapping groups. The initial guest check-in, reservation, cleaner and actual-stay group passed **33 tests**. The shared Channex, PMS reliability, finance, daily-close, VIZA identity and NTAK evidence run passed **88 tests** with one failure in the newly added Channex assertion. That assertion had taken the reservation ID from an empty sync-apply list after the webhook had already applied the booking. The corrected assertion confirms the webhook and its duplicate produce exactly one invitation. All **5 final targeted tests** passed, including that case, the three Pilot regressions and the unchanged-identity retry.
- The separate legacy `test_v293.py` run produced **4 passed, 1 known failure**. The unchanged `test_modification_preserves_manual_fields_and_cancellation_updates_cleaning` expects registration `complete` and receives `incomplete`, matching the [documented baseline](../ntak/NTAK_HANDOFF.md). Backend runs also showed the two existing FastAPI and Starlette dependency deprecation warnings.
- Flutter analysis was clean. The final targeted Flutter run passed 44 tests, including the new authorized simulation dialog. The separate Windows release built successfully in `apps/delvane_business/build/windows-uat-pilot01/x64/runner/Release`. The previous UAT release folders are still available.
- `git diff --check` passed. While implementation was in progress, the repository advanced to `312bd27` (`save`), which contains earlier working-tree changes and part of Pilot 01. No commit, push or tag change was initiated for this assignment.

Repeat the PostgreSQL rehearsal with the two pinned, locally available UAT images and a local Docker engine. The [runner](../../tests/run_pilot_postgres_rehearsal.sh) mounts the two changed backend modules read-only over the reviewed UAT runtime and starts a fresh PostgreSQL 17.12 instance. It performs no image pulls.

```sh
sh tests/run_pilot_postgres_rehearsal.sh
```

## Boundaries and Pilot 02

- No live guest delivery, remote invoice issuance or payment collection was exercised. The current SSH-only UAT origin serves the operator, so a guest on another network still needs an approved, reachable HTTPS guest origin.
- For this pilot, the single apartment and its property share one overnight turnover. The existing property/day grouping remains for overnight operations. Independent cleaning per unit on multi-unit properties and reinspection after a retrospective correction to a completed turnover remain manual. A no-show or late guest still requires an explicit operator decision, with no inferred arrival or departure.
- Camera/OCR quality, guest-browser behavior on a real Xiaomi and the new Windows UI against a backend running these changes remain manual acceptance checks. The backend changes were exercised locally. Hetzner still runs the previously deployed image.
- Both official transmission gates stayed disabled. Existing NTAK signing and normalization blockers and VIZA external interoperability requirements remain open.
- **Pilot 02** should validate one approved guest communication channel and reachable HTTPS guest origin. Redact bearer paths from application and ingress access logs before exposing the guest form. Rehearse delivery receipts, rejected and delayed delivery, link recovery, and physical-device scanning with synthetic data before any real guest rollout.
