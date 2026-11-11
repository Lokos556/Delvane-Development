# Rosa v2.10.52 — Guest identity verification gate

## Added
- Owner/manager identity review panel available from a reservation's Preparation tab.
- Per-guest verification states: not submitted, needs review, verified, or rejected.
- Verification method tracking (in person, video call, reviewed identity image, manual review), optional note, actor, and timestamp.
- New schema migration `3071` creates `guest_identity_verifications` and safely marks existing completed guest records as needing review.
- Guest self-check-in and imported scanner results now remain pending owner verification; they do not queue government submission events by themselves.
- Government events are queued only when every guest record is complete and explicitly verified by an owner/manager.
- Verification actions are audited. Document images are not accepted or stored by these endpoints.

## Validation
- `python -m py_compile app.py` — passed.
- `node --check static/app.js` — passed.
- `pytest -q tests/test_guest_checkin.py tests/test_v21042.py tests/test_v21046.py` — 5 passed.
- Full repository suite not run as part of this change.

## Important
This is a workflow gate in Rosa's application logic, not VIZA certification. Production transmission still requires the official VIZA/THF integration, credentials, and successful validation/certification.
