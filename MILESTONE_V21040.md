# Rosa v2.10.40 — Channex certification room mapping/cap repair

- Repairs certification-only room mappings by matching local room names to the corresponding Channex room type.
- Aligns the remote Channex room inventory count with Rosa's configured room count.
- Removes certification-only `max_availability` rules that cap a mapped room below its configured inventory.
- Clears stale queued/retry availability jobs and rebuilds the authoritative certification availability state after repair.
- Leaves normal production properties and their availability rules unchanged.
