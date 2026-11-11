# Rosa V2.10.1

## Government integration developer preparation

- Added schema 3010 for durable government developer test-run previews.
- Expanded government event payloads to include the reservation, property and guest-registration records instead of reservation-only data.
- Added NTAK v9 `adatszolgaltatasKezdoDatumRequest` XML preview generation using the current official v9 namespace and required header fields.
- Added NTAK/VIZA developer-readiness checks so missing official test-package items are explicit.
- Kept live government transmission locked until official MTU/NTAK/VIZA test credentials, certificates and/or the VIZA storage-forwarding module are supplied and Rosa has passed certification.
- Preserved the VIZA ID-scanner integration boundary.

## Validation

- Full automated suite: **137 passed**.
- Added dedicated V2.10.1 government preparation tests.
- No real NTAK/VIZA traffic is attempted without official test-package configuration.
