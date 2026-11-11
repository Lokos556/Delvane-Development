# Rosa v2.10.50 — Guest self-check-in foundation

Implemented a first production-shaped mobile guest journey without disturbing the Channex-certified core.

## Guest flow

- Owner/manager can generate an individual secure check-in link for every guest slot on a reservation.
- Links are bearer tokens stored only as SHA-256 hashes and expire two days after checkout.
- Guest opens `/guest/checkin/<token>` without a Rosa account.
- Mobile camera capture happens in the browser.
- Tesseract.js performs OCR locally in the browser; Rosa does not receive the document image.
- ICAO-style MRZ parsing extracts name, nationality, date of birth, sex, document type and document number where available.
- Guest can manually correct/complete all fields before confirmation.
- VIZA-relevant additional fields are stored only in Rosa's encrypted sensitive guest record.
- Guest confirmation creates an auditable `guest_checkin_event` and queues the existing government event pipeline.
- Owner/manager can query per-guest pre-check-in status.

## Privacy boundary

The server never receives a passport/ID image from the guest flow. `government_scan_events` stores scan metadata only; structured identity data is kept in the existing guest record/encrypted sensitive-data layer.

## VIZA boundary

This milestone is the PMS-side guest experience and scanner ingestion layer. It does not claim final VIZA transport certification. The official VIZA storage-forwarding module and validation package remain required before production transmission.
