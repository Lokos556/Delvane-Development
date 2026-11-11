# Rosa v2.10.21 — Certification Rate-Plan Cleanup

## Fixed
- Stopped startup from seeding a local `Standard Rate` onto properties that already have active rate plans.
- Removed the legacy local `Standard Rate` fallback from Channex room synchronization; existing remote Channex rate plans are mirrored by their real titles.
- Added migration `3055` to deactivate the legacy local `Standard Rate` in the dedicated `Test Property - Rosa AI` certification workspace and deactivate any mapping attached to it.
- Normal single-rate properties remain supported: an empty property can still receive the local Standard Rate seed.
- Bumped application/connector version to `2.10.21`.

## Certification impact
The certification workspace now exposes only the real Channex rate plans:
- Twin Room — Best Available Rate
- Twin Room — Bed & Breakfast Rate
- Double Room — Best Available Rate
- Double Room — Bed & Breakfast Rate

The bogus `Standard Rate -> Best Available Rate` duplicate mapping is no longer active and will not be offered by the mapping UI.

## Validation
- `pytest -q tests/test_v21021.py tests/test_v3050.py tests/test_v21017.py tests/test_v21014.py`
- Result: **9 passed**
- `python -m py_compile app.py`
