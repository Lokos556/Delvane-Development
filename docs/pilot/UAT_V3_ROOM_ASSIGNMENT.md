# UAT V3 room assignment update

## Cause and behaviour

Selecting a property and room type reserves aggregate inventory. Before this update, a physical room was persisted only when the operator separately selected planned units in the booking editor. Check-in correctly requires a physical allocation covering the arrival business date. The gap was in booking and assignment, and the check-in validation still applies.

- New confirmed overnight bookings and newly confirmed inquiries use the smallest sufficient compatible physical unit available for the entire stay. Building and room number break ties consistently. A room expressly selected in the booking form is revalidated at save.
- Options account for effective room type and capacity, OOO/OOS periods, overlapping bookings, actual occupancy and aggregate availability. The booking remains unassigned if no safe match exists. Set up a real physical unit under Apartments and rooms when a property has only aggregate inventory. Delvane does not infer a room or its beds from the property.
- Reservations display the assigned building, unit and date interval. Owners and managers can select or review a room from reservation details or assign a missing room from check-in. The quick picker covers one unit for the whole overnight stay. Existing advanced planning still supports day-use, split stays and multiple rooms.
- Unrelated edits preserve the assignment. A stale manual selection returns a conflict. The server rechecks availability while holding a property lock. An occupied room cannot be silently changed through the planner. Use the existing actual stay transfer process for an observed move.
- Mapped Channex imports use the same assignment logic. Routine provider updates preserve existing assignments, cancellations release them, and conflicting revisions require operator review. Imports without a resolvable room type or safe physical match can stay unassigned. Same-type assignments do not consume aggregate stock twice.

Planned rooms feed unit-level cleaning and readiness and supply room facts to NTAK reservation snapshots. An actual arrival or departure still requires an explicit stay event. Checkout unlocks the unit's cleaning task through the existing workflow. VIZA and NTAK stay reporting still derives from recorded events, and their transmission gates are unchanged.

## Package and deployment

This release is backend **2.10.61** on the existing PostgreSQL schema **3091**. No migration is required. The archive layers four backend sources over the checksum-verified 2.10.60 image. The candidate passed the disposable PostgreSQL 17.12 smoke test through the native ingress, including concurrent assignments from separate sessions, check-in, checkout, cleaning, and tenant isolation. The same run checked mock guest delivery through an application restart.

After deployment approval, stage the bundle from the Windows repository root using the existing Git for Windows SSH agent:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\deploy\guest-uat\stage-files.ps1 -PermanentV3Rooms
```

From the Hetzner root session:

```bash
(
  set -eu
  install -d -m 0700 /root/delvane-uat-v3-rooms
  install -m 0600 /home/delvane-uat/delvane-uat-v3-rooms/{delvane-permanent-v3-rooms-3091-local.tar.gz,replace-release.py,SHA256SUMS} /root/delvane-uat-v3-rooms/
  cd /root/delvane-uat-v3-rooms
  sha256sum -c --strict SHA256SUMS
  echo 'c0dd788e84be4ad70bdafd1740627f3ac7c43ada1279ce98b96486449cee2307  replace-release.py' | sha256sum -c --strict
  python3 -I replace-release.py apply-v3-rooms delvane-permanent-v3-rooms-3091-local.tar.gz f0e7b0f75fbd1b4bc779a48b29866c58f4f9eb85685083c851225085196d396d
  python3 -I /opt/delvane-permanent-uat/permanent.py status
)
```

The installer verifies and backs up the existing database before switching. It retains the previous application and uses the same database volume. It checks the new backend version and private origin and restores the previous release on a switch failure. Manual application rollback uses `python3 -I /root/delvane-uat-v3-rooms/replace-release.py rollback-v3-rooms`.

## Verification

- Focused backend and shared NTAK/VIZA regressions: 112 passed. The separate Channex regression run had 12 passes and reproduced the documented `test_v293.py::test_modification_preserves_manual_fields_and_cancellation_updates_cleaning` failure, where registration is `incomplete` and the test expects `complete`.
- Flutter 3.50.0 and Dart 3.14.0: analysis clean, 333 tests passed. Windows and signed Android release builds succeeded. Both binaries contain the remote UAT origin and the new assignment flow. Android signature and ZIP alignment checks passed, and ADB had no connected device.

For live acceptance, use a fictional confirmed overnight booking for a room type with a configured physical unit. Verify that the booking displays the assigned room, then repeat with a legacy unassigned booking and use **Assign a room** from check-in. Record arrival and checkout and verify the cleaning task for that unit. Android and Windows build 6 both use the existing remote UAT API. Activation and live device testing remain pending.
