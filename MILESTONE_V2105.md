# Rosa V2.10.5 — Channex staging rate-plan mapping

- Staging inventory preparation now imports all rate plans attached to the mapped Channex room.
- If the staging room has only one rate plan, Rosa creates a second `Non-refundable Rate` for certification testing.
- Every imported/staging rate plan gets a local Rosa rate-plan record and a durable Channex mapping.
- Production connections never invent rate plans; they map the real remote rate plans.
- This fixes the multi-rate-plan certification workflow so Test 3 can be performed through Rosa.
