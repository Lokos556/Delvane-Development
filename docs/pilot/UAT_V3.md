# Delvane Business UAT V3

The Android and Windows clients use `https://api.delvane.app`. The backend candidate is **2.10.60** on PostgreSQL schema **3091**. The editor needs this backend to display saved invitation addresses. With an older backend the editor explains that the address is unavailable and leaves an untouched contact alone.

## Behaviour and verification

- The foreground timer had excluded Reservations and Maintenance. A 20-second pulse refreshes the visible operational workspace using existing authenticated reads. Resume and mobile pull-to-refresh request a fresh read. In-flight reads cannot overwrite a later local mutation, and recovery verifies the session and deployment before replacing offline data. Open edit forms keep their unsaved input.
- The invitation address was encrypted and used for delivery, but unavailable to the reservation editor. `GET /api/reservations/{id}/booking-contact` returns only the saved booking override to an authorized owner or manager in the reservation's organization. The address remains out of list, detail, outbox and persistent offline projections. Edits send changed fields only. Clearing a loaded override restores the existing primary-guest contact fallback.
- Reception had copied whichever results were present when it mounted. A late inbox response could therefore sit unused until the separate 45-second timer ran. The inbox now renders directly from the active controller and can appear while the outbox is pending. Background refresh reads the active folder and summary. The inbox API serves synchronized records from the database and never triggers provider fetching. Guest context is batched.
- Reservation details, Ma and Operations expose actual stay actions. Check-in shows booking status, registration and allocated-room readiness. Check-out records the actual departure for selected guests and uses the existing cleaning and readiness workflow. The server still enforces permissions, occupancy, allocation and event chronology. Operational recording is independent of official reporting acceptance.

Flutter analysis was clean and all 331 tests passed. The two-session widget test observed a booking at the 20-second tick and an edit on resume. The slow-Reception test held the inbox for three simulated seconds and verified that messages appeared when it completed while the outbox was still pending. The local 14-message API check took 13.9 ms and used two inbox data statements. Previously, guest context used up to three extra statements per linked message. Live server latency has not been measured for V3.

104 focused backend tests passed. The packaged image passed startup and restart on disposable PostgreSQL 17.12 with schema 3091, background worker checks, two separate native sessions, contact round-trip, tenant isolation and the existing mock delivery rehearsal. A checksummed dump restored into a separate database with the encrypted contact intact.

## Deploy after approval

The local bundle is `build/uat-v3`. It contains the image archive, the release installer and `SHA256SUMS`. The image was built from the verified V2 image with only `app.py`, `guest_stays.py` and `uat_access.py` overlaid. It retains the non-root runtime user. No new migrations, credentials, Cloudflare changes or configuration changes are required.

From the repository root on Windows, with the existing Git SSH agent unlocked:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\deploy\guest-uat\stage-files.ps1 -PermanentV3
```

From an approved Hetzner root session, compare the staged checksum manifest with the Windows original and run:

```bash
(
  set -eu
  install -d -m 0700 /root/delvane-uat-v3
  install -m 0600 /home/delvane-uat/delvane-uat-v3/{delvane-permanent-v3-3091-local.tar.gz,replace-release.py,SHA256SUMS} /root/delvane-uat-v3/
  cd /root/delvane-uat-v3
  sha256sum -c --strict SHA256SUMS
  echo '18fc912d351e48cb803b57ebf4fecbd50f06a286ef37c13d8088f46a00303ad8  replace-release.py' | sha256sum -c --strict
  python3 -I replace-release.py apply-v3 delvane-permanent-v3-3091-local.tar.gz 9e56ad7fc47e58a8639280ee37112647428afad0bcfbae77fc8fe065561501a9
  python3 -I /opt/delvane-permanent-uat/permanent.py status
)
```

The installer checks the current application, workers, disk-backed database and isolation. It verifies the image and takes a checksummed backup before replacing the app. It retains the previous container, uses the same PostgreSQL volume, and checks the new app, worker heartbeats, private routes and backend version. It attempts rollback on a critical verification failure. For manual rollback, run `python3 -I /root/delvane-uat-v3/replace-release.py rollback-v3` from the root session. An application rollback continues to use the same database, including writes made after cutover.

## Live UAT acceptance

1. Sign in on both updated clients with an approved test account. Keep Reservations open on the Xiaomi, create a synthetic booking on Windows, then edit its dates. Confirm the changes within one foreground refresh cycle plus request time. Repeat after temporarily disconnecting the Xiaomi and reconnecting.
2. Save an approved test mailbox as the invitation address without sending an invitation. Reopen the editor on both devices and change an unrelated field. Confirm the saved address remains.
3. Open Reception, switch among the three visible folders, and verify the list, unread filter, conversation and draft controls. Verify the existing guest website and approved-account restriction.
4. Use a confirmed synthetic stay with an allocated unit. Record observed arrival and departure from Ma or booking details. Verify the resulting cleaning task, finish its checklist with an authorized worker, and verify readiness. Keep NTAK and VIZA transmission disabled.

Server activation and physical-device retesting remain pending.
