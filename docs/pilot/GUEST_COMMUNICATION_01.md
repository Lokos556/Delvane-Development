# Guest Communication 01

Confirm a reservation, optionally enter its invitation address, then approve the prepared invitation in Reception. The address entered on the booking takes precedence over its linked primary contact and is stored encrypted. Changing it replaces the invitation, revokes the old links, and requires a new approval. The invitation pipeline uses the existing outbox, guest registration records, and audit trail.

Migration **3091** adds durable delivery state, events, encrypted booking contacts and guest link rate limits. Each outbox version keeps one stable provider idempotency key. A worker lease protects concurrent attempts and makes interrupted sends recoverable. Reception shows queued, sending, provider accepted, delivery confirmed, retry scheduled, failed, unconfirmed and cancelled states. A valid delivery receipt is required for confirmation. The reservation shows its current invitation and pre-check-in state. Owners and managers can advance a scheduled retry in Reception. Provider acceptance, signed delivery confirmation and guest identity review are separate steps.

The retry envelope contains the sender, recipient and links. It is encrypted while sending can still be attempted and cleared at a terminal outcome or provider acceptance. The outbox and event history retain identifiers, timestamps, attempts and classified outcomes. One invitation can include one expiring, single-use link per guest still awaiting details. Cancellation, significant booking changes and contact changes revoke links. A provider call already in flight can still complete after cancellation, but its links stay revoked. Duplicate receipt events are idempotent. Later accepted or bounced events cannot downgrade a confirmed delivery or reactivate a cancelled invitation.

## Before a genuine delivery test

Use the [Resend setup and controlled test procedure](RESEND_GUEST_INVITATIONS.md) for the implemented Resend adapter. The provider-neutral steps below apply to other adapters.

1. Approve an email provider that deduplicates a stable idempotency key for at least 24 hours and returns the original message identifier on replay. Implement its Delvane `Provider` adapter and register it on `app.state.guest_email_provider` before startup. Its send call must have a bounded timeout shorter than the 90-second worker lease. It must classify temporary errors, permanent errors and unknown outcomes without logging message bodies or credentials. Keep its least-privilege send credentials in the UAT secret store.
2. Verify the sending domain and sender with the approved provider. Publish its exact SPF, DKIM and any return-path DNS records. Set the domain's DMARC policy and confirm alignment with the selected sender. Use a separate approved guest hostname with DNS A/AAAA or CNAME as required by the ingress and a trusted TLS certificate for that hostname. Test that the hostname resolves and the certificate verifies from outside the operator network.
3. Keep the operator entry private. On the public HTTPS entry, enforce the exact guest Host at the proxy and forward only these paths and methods. Reject everything else at ingress, including operator APIs, docs, health and government routes. Route to the private backend. Forward client IP only from the trusted proxy, disable URL and body capture for guest routes and receipts in ingress, application, provider tracing and error reporting, and keep cache bypass enabled. Public-origin content security policy limits browser resources to the guest origin. Manual entry is the public flow until the OCR runtime and models are served from that origin and tested on a device.

| Method | Allowed public path |
| --- | --- |
| GET, HEAD | `/guest/checkin/{43-character token}` |
| GET, POST | `/api/public/checkin/{43-character token}` |
| GET, HEAD | `/static/guest-checkin.css`, `/static/guest-checkin.js`, `/static/guest-checkin-i18n.js`, `/static/delvane-icon.png` |
| POST | `/api/public/guest-delivery/receipt` |

Authenticate the original vendor webhook using its documented verification scheme in the approved adapter or webhook bridge. Normalize it to JSON with `event_id`, `outbox_id`, `message_id` and `state` (`accepted`, `delivered` or `bounced`). Carry the outbox ID as provider metadata so an early receipt can be correlated. Send the exact raw JSON with a fresh Unix-seconds `X-Delvane-Timestamp` and lowercase hex `X-Delvane-Signature` (HMAC-SHA256 with the Delvane receipt secret over timestamp, a dot, and the raw bytes). The backend requires a matching signature within five minutes, caps the body at 8 KiB and deduplicates event IDs. Keep the vendor secret and the bridge's Delvane receipt secret separate. The guest form allows 60 API calls per minute per hashed client IP and 30 per active token.

| Backend setting | Value for an approved, isolated trial |
| --- | --- |
| `DELVANE_GUEST_EMAIL_ENABLED` | Unset by default. Set to `1` only after the adapter, endpoint and synthetic recipient are approved. |
| `DELVANE_GUEST_PUBLIC_ORIGIN` | The guest hostname at an `https://` origin, without a path or custom port. |
| `DELVANE_GUEST_EMAIL_FROM` | Provider-verified sender email address. |
| `DELVANE_GUEST_RECEIPT_SECRET` | Random secret of at least 32 bytes, supplied through the UAT secret store to the backend and trusted bridge. |
| `DELVANE_GUEST_MAX_ATTEMPTS` | Default 5. |
| `DELVANE_GUEST_RETRY_BASE_SECONDS`, `DELVANE_GUEST_RETRY_MAX_SECONDS` | Defaults 60 and 3600. Bounded exponential delay with jitter. |
| `DELVANE_GUEST_LINK_HOURS` | Default 48. Replay also stops within 24 hours and when no eligible links remain. |

Leave both NTAK and VIZA transmission controls disabled. For the first test, approve one synthetic booking to an approved test mailbox. Verify that Reception first shows provider acceptance, then transitions on a genuine signed receipt. Open the link on a separate network, submit fictional details and verify that a cancelled booking's link fails.

## Local rehearsal

Run `sh tests/run_pilot_postgres_rehearsal.sh --guest-delivery` with the existing pinned images and local Docker. It uses an internal network, temporary PostgreSQL 17.12, synthetic sign-in credentials and an in-process adapter that never contacts a provider. It restarts the backend container after a temporary send failure and exercises owner retry, receipt authentication, duplicate delivery events, guest submission, cancellation and separate tenant access. Running without the flag exercises the earlier full Pilot stay.

- **Backend** — 59 focused and shared regressions passed, including Pilot 01, room turnover, allocations, NTAK evidence and VIZA identity capture. The final delivery-only rerun passed all four tests. Both PostgreSQL 17.12 rehearsals passed through a backend restart on schema 3091. The delivery suite also checks concurrent queue claims, recovery after provider acceptance before local recording, receipt ordering, redaction and link throttling.
- **Flutter and Windows** — 319 tests passed and analysis was clean with Flutter 3.50.0 and Dart 3.14.0. The separate staging release is in `apps/delvane_business/build/windows-uat-guest-delivery/x64/runner/Release`, configured for the existing HTTPS loopback tunnel at `127.0.0.1:18443`. Updated backend and Windows interaction over the Hetzner tunnel remain pending.
- **Sources** — [Delivery, schema and worker](../../guest_delivery.py), [API and reservation lifecycle](../../app.py), [Reception](../../apps/delvane_business/lib/features/pms/reception_page.dart), [reservation screens](../../apps/delvane_business/lib/features/pms/reservation_dialogs.dart), [delivery status](../../apps/delvane_business/lib/features/pms/guest_delivery_status.dart), [API error mapping](../../apps/delvane_business/lib/features/pms/pms_workflows.dart), [Hungarian labels](../../apps/delvane_business/assets/native-hu.json), [runtime allowlist](../../.dockerignore) and [production startup](../../start_production.sh).
- **Tests** — [delivery regressions](../../tests/test_guest_delivery.py), [PostgreSQL journey](../../tests/guest_delivery_postgres.py), [lab runner](../../tests/run_pilot_postgres_rehearsal.sh), [existing stay regression](../../tests/pilot_postgres_rehearsal.py), [migration assertions](../../tests/uat_postgres_smoke.py) and [Flutter operator interaction](../../apps/delvane_business/test/reservation_reception_test.dart).
