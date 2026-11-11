# Rosa V2.6.4.2 — Single-thread Intelligence + Operations Desk

## Goal
Make Rosa AI feel like the primary product while keeping operational intelligence readable and first-class.

## Changes
- Removed selectable/multiple chat UI. Each user now has one persistent Rosa operational thread.
- Added a singular `/api/rosa/conversation` endpoint and made the backward-compatible create endpoint reuse the same primary thread.
- Replaced the narrow context sidebar with an always-visible Operations Pulse.
- Clicking briefing/metrics opens a large Operations Desk that occupies most of the working area rather than a cramped sidebar.
- Operations Desk preserves the live briefing, decisions, exceptions, next-48-hour arrivals and currently handled work.
- Decision approvals remain actionable inside the desk.
- Rosa chat remains full-height with its own scroll and fixed composer.
- Existing local-first routing, governed actions and 18-language UI system remain intact.

## Port
Local launcher: `http://127.0.0.1:8814`.

## Schema
Still 2620. No migration is required for this UI-focused release.
