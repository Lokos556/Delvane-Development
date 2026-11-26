# Delvane UAT V2 release

Both clients use `https://api.delvane.app` with the existing staging session and role checks. On mobile, the primary workspaces are Reception, Intelligence, Today, Reservations and Operations. Swipe the workspace header or the unobstructed Today and Operations content to move between them. Use the property icon and Settings for properties and secondary workspaces. Calendar gestures stay inside the calendar.

## Backend prerequisites for V2

The old public ingress returns HTTP 404 for an anonymous reporting-details probe and HTTP 401 for the same reservation's detail route. The editor needs both. V2 adds the exact read route to the allowlist and keeps the existing reservation authorization. Names saved on a new guest profile are encrypted and retain their draft status. A reason is required for corrections to submitted information and for reporting edits. Cleaning uses the existing assigned-cleaner and checklist completion checks. V2 keeps schema 3091.

The candidate is staged with mode `0600` at `/home/delvane-uat/delvane-uat-v2`. Both remote checksums matched the local manifest. For a future transfer, run `powershell -NoProfile -ExecutionPolicy Bypass -File .\deploy\guest-uat\stage-files.ps1 -PermanentV2` from the Windows repository root. In the root session, compare the checksums again with the local manifest before executing the script. Cutover and live rollback verification are pending.

```sh
install -d -m 0700 /root/delvane-uat-v2
install -m 0600 /home/delvane-uat/delvane-uat-v2/{delvane-permanent-v2-3091-local.tar.gz,replace-release.py,SHA256SUMS} /root/delvane-uat-v2/
cd /root/delvane-uat-v2
sha256sum -c --strict SHA256SUMS
# Use the archive digest independently confirmed against your local manifest.
python3 -I replace-release.py apply delvane-permanent-v2-3091-local.tar.gz 73d7754b939a657931ef560cd970163a20b6cb10993f91af1808fd1cd785e7d8
python3 -I /opt/delvane-permanent-uat/permanent.py status
```

The installer imports the pinned image, checks the existing isolation and disk-backed database, backs up schema 3091, retains the previous application container and restarts the managed proxy, relay, connector and workers. The hostname, published guest route, PostgreSQL volume, account allowlist and Resend test-recipient setting come from the existing deployment. If the application checks fail, the script attempts to restore the previous release. Manual application rollback uses `python3 -I /root/delvane-uat-v2/replace-release.py rollback`. Database records written before or after the switch stay on the same volume. Official government transmission remains disabled.

## Device retest

1. Update the Xiaomi by opening the signed V2 APK. Open the Windows V2 executable from its own complete Release folder. Sign in with the same approved account and verify Today on launch.
2. Create one synthetic booking on Android, open and edit the dates on Windows, then reload Android. Give Guest 2 a fictional family and given name, save, and confirm the Hungarian success message. Reopen from both devices and check the draft and unverified status.
3. Open a cleaning task from Operations and from an assigned cleaner's work list. Start, check off items, finish, and confirm the relevant property or room readiness. Open the property selector and verify only authorized properties appear.
4. Test the moving navigation curve at all five positions, header swipes, calendar month swipes, search result return and explicit Back. Check the rolling calendar across a year boundary and after switching property.
5. Open Today and Reservations online, toggle airplane mode, close and reopen the app, and inspect the cache indicator and timestamp. Try a server action, restore connectivity and verify the session and refreshed data. Sign out and reopen offline to confirm access was removed.
6. With a native password service enabled, confirm the operating system offers the credential after successful authentication. iOS shared web credentials need the verified Apple team and bundle ID, `webcredentials:api.delvane.app` in Associated Domains and a matching `/.well-known/apple-app-site-association` document. This release leaves those publishing steps pending.

The secure read-only cache expires after 12 hours or session expiry, whichever is earlier. It stores limited dates, status, property names and assigned-task projections. Conversations, documents, guest names and reporting details require live access. Lists too large for the platform credential store are unavailable offline. Reception polls while foregrounded. The server creates scheduled drafts and handles the existing Resend path. Other external inbox sources still depend on separately connected and authorized integrations.

## Release verification

- Flutter analysis clean and 322 tests passed. The signed ARM64 Android build and Windows release succeeded. Android signature and 16 KiB alignment checks passed. Physical V2 testing remains pending.
- 51 focused backend checks passed. A seven-test ingress rerun also passed and added the assigned cleaner checklist and completion scenario. The image passed disposable PostgreSQL 17.12 startup and restart, mock delivery recovery, booking date edits and encrypted guest name drafts through two native sessions, and cross-tenant denial.
- Remote Docker logs require administrator access. Anonymous native route probes independently confirmed the live allowlist discrepancy. The current owner property count requires an authenticated live property read. The selector uses only properties returned by that read.
