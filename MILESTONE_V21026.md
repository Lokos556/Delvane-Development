# Rosa V2.10.26 — Channex certification date-window fix

## Purpose
Fix the remaining Channex certification rejection shown by V2.10.25 diagnostics.

## Root cause
V2.10.25 still built the 500-day certification restrictions window starting on
`date.today()`. Channex validates update dates against its provider clock and
can reject the current calendar date as invalid after its clock rolls forward.

## Changes
- 500-day full sync now sends exactly 500 dates starting tomorrow.
- Existing queued/retry certification-sized restriction jobs are repaired on
  startup to the same future 500-day window.
- Ordinary ARI updates are not rewritten.
- Version bumped to 2.10.26.

## Verification
- `python -m py_compile app.py` passed.
- Added V2.10.26 regression tests for the future 500-day window and queued-job repair.
