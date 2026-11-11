# Rosa v2.10.38 — Channex certification delta/ACK fixes

## Certification issues addressed

1. **Single Date Update for Multiple Rates**
   - Batch restrictions updates are now true deltas.
   - A rate-only change sends only `rate`.
   - A restriction-only change does not carry the stored rate.
   - Stored restrictions are still updated locally, but are not copied into unrelated outbound requests.

2. **Multiple Date Update for Multiple Rates**
   - Decimal certification prices use `Decimal` end-to-end at the API boundary and are converted to Channex minor units exactly (for example `312.66` -> `31266`).
   - Batch rows no longer infer `min_stay_through` from `min_stay_arrival` unless it was explicitly changed.
   - Consecutive identical delta states continue to be merged into `date_from` / `date_to` ranges.

3. **Booking Receiving acknowledgement**
   - Booking revision ACKs, including cancelled revisions, now get one immediate retry after a transient Channex failure.
   - The existing durable inbox state is still updated only after the ACK result is known.
   - The manual ACK retry endpoint uses the same retry path.

## Validation

Targeted Channex certification/integration tests:

- **27 passed**
- Includes existing availability reconciliation, booking new/modified/cancelled ACK, full-sync, and certification ARI tests.
- Added regression tests for rate-only and min-stay-only delta payloads.

The repository also contains older runtime-version assertions unrelated to these fixes; the full legacy suite is not treated as a clean certification signal.
