# Rosa v2.10.39 — Channex certification availability baseline repair

- Fixed the Channex certification workspace retaining stale `0` availability as a manual override after earlier certification runs.
- The certification workspace now derives untouched availability from each room's configured inventory count, reduced by confirmed reservations.
- The repair clears stale certification-only manual availability, rebuilds stored dates, and republishes the authoritative 500-day availability baseline to Channex.
- Production properties and their explicit manual availability behavior are unchanged.
- Added regression coverage for the stale-zero certification state.
