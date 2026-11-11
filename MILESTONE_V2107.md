# Rosa V2.10.8 — Channex existing-inventory mapping

- Added a dedicated Channex inventory mapping flow for existing staging properties.
- The mapping flow reads existing Channex room types and rate plans and never creates remote inventory.
- Supports explicit many-room/many-rate mapping and persists durable room/rate mappings.
- Updates the integration's primary Channex property/room/rate references for compatibility with existing ARI paths.
- Full Sync continues to use the durable multi-room/multi-rate mapping layer.
- Version: 2.10.7 / schema unchanged.
