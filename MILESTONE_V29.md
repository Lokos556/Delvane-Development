# Rosa V2.9.5 — Two-Way Channex Distribution

Runtime version: `2.9.5`  
Schema: `2950`  
Desktop URL: `http://127.0.0.1:8819`

## Delivered

- Stable per-user data path so unpacking an update does not create a fresh database.
- One-time adoption of the newest legacy database from a nearby Rosa version folder.
- Non-destructive database migration.
- Encrypted connector credentials with metadata-only status responses.
- Tenant-isolated, idempotent provider event inbox.
- Normalized event adapter feeding the existing preview, conflict detection, import, cleaner-task and registration workflow.
- Booking.com B.XML/OTA XML parser and authenticated staging endpoint.
- Customer-facing commercial Booking.com onboarding that asks for the Booking property ID, not developer credentials.
- Secret-authenticated Channex booking-revision receiver for new, modified and cancelled reservations.
- Strict bridge-property mapping so one Rosa customer's booking cannot enter another customer's account.
- NTAK/VIZA connection registry and durable government-report outbox populated from imported reservation changes.
- Connector readiness endpoint exposing mapping, credential and inbox health without leaking secrets.
- Local Channex staging-key setup utility with hidden input, live validation, and non-destructive `.env.local` merging.
- Owner-facing Channex staging link that reads accessible properties and idempotently creates the Rosa apartment's room type and Standard Rate through the API.
- Clear per-apartment `CHANNEX READY` state, staging details, and a structured success receipt instead of an ambiguous browser alert.
- Standalone-release configuration: API secrets live in Rosa's persistent application-data directory and can be adopted once from a sibling older release folder.
- Connection readiness is derived from persisted Channex property/room/rate mappings, so reservation test-sync status can no longer hide a valid connection.
- Real Channex booking revision feed ingestion with automatic polling and an immediate manual check.
- Full webhook notification handling: fetch revision, route by room type, save, then acknowledge.
- Durable acknowledgement status with idempotent redelivery and retry after upstream errors.
- Direct new/modified/cancelled reservation application that preserves manually enriched fields and regenerates cleaning work.

## Intentionally not claimed

- A live Booking.com connection before Channex certification, production access, and each property connection are authorized.
- Live Szallas.hu access. Rosa needs approved provider documentation/credentials or a channel-manager bridge.
- Government transmission before MTÜ has certified commercial Rosa and issued the required credentials. Events remain queued until then.
