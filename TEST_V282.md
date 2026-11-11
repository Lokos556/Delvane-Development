# Rosa V2.8.2 quick test — Team & Access

1. Run `START_ROSA.bat` and sign in as the demo owner.
2. Open **Settings → Team & access**.
3. **People** should show the owner, Anna, Erika and Bálint with role, contact, access/security state and workload signals.
4. Click **Add team member**. Create a test cleaner. Rosa should show a setup password exactly once.
5. Sign out and verify the new cleaner can sign in with that email/password. Their workspace should only expose worker operations.
6. Sign back in as owner, manage the test person, then try **Revoke sessions**, **Reset access**, and **Suspend**.
7. Open **Access & roles** and compare Owner / Manager / Cleaner / Maintenance access.
8. Open **Workload** and verify cleaning and maintenance work are shown as one part of Team, not the whole page.

No live invitation email is sent in V2.8.2. Account creation itself is real inside Rosa; setup credentials are displayed locally once.
