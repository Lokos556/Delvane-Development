# Rosa V2.10.27 — Channex PMS certification scenario hardening

## Purpose
Prepare the fourth Booking.com / Channex certification property for a second PMS certification submission by fixing the remaining gaps exposed by the first certification report.

## Changes
- Added an explicit rate-plan selector to the single-date/range ARI editor.
- Single rate/restriction updates now target the selected Rosa rate-plan mapping instead of silently using the integration's remote default.
- Certification-workspace single-rate prices now accept decimal USD values and convert them to Channex minor units.
- Single rate/restriction state is persisted per rate plan so one certification scenario cannot overwrite another rate plan's state.
- Added an `All mapped room types` availability option so multiple-date availability changes can produce one `Property.UpdateAvailability` request covering every mapped room.
- Preserved legacy integration-level behavior for older mappings that do not yet have local rate-plan mapping rows.
- Corrected the visible/application/asset version from the stale 2.10.25 labels to 2.10.27.
- Kept the V2.10.26 future 500-day full-sync date-window fix and durable retry/diagnostics behavior.

## Certification coverage added
Regression tests now explicitly verify:
- 500-day full sync contains both room types and all four certification rate plans.
- Every full-sync restriction object declares all required restriction fields.
- Single-rate certification updates hit the exact requested rate plan and date.
- Decimal USD certification prices are sent as minor units.
- Multiple-rate updates remain one restrictions request with merged date ranges.
- Multiple-date availability can update both rooms in one availability request.
- New, modified, and cancelled Channex booking revisions are acknowledged after durable save.

## Verification
- `node --check static/app.js` passed.
- `python -m py_compile app.py` passed.
- 27 focused Channex/certification regression tests passed.
- PMS certification has **not** been resubmitted yet; the next step is to install this build, reproduce the certification scenarios against the fourth property, and only then submit.
