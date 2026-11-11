# Rosa v2.10.42 — Channex Test 9 stale availability retry fix

The Test 9 failure was caused by an older queued/retry availability job being merged with the new reservation update. That stale job could still contain the previous Double Room availability of 4, while Channex correctly rejected it because the certification room capacity was 1 for the Test 9 scenario.

## Fix

- Certification-workspace reservation creation now clears queued/retry Channex availability jobs before calculating the new reservation delta.
- The fresh reservation remains the authoritative state for the affected room/date.
- Test 9 therefore sends only the requested Double Room update: 1 -> 0 on 25 November 2026.
- Added `tests/test_v21042.py` reproducing the stale `availability=4` retry and verifying that only `availability=0` is delivered.
