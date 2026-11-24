# Permanent Delvane Business UAT

## What changes at cutover

The existing Hetzner PostgreSQL 17.12 named volume and schema 3091 stay in place. A systemd service starts the isolated database and read-only application, restores the reviewed scoped firewall rules, establishes the guest/Nginx Unix socket and restricted Resend relay, then starts the existing Cloudflare connector. The same supervisor detects stopped or unhealthy components and recovers them. Docker publishes zero ports. The retired PostgreSQL container is outside the managed lifecycle.

The guest origin keeps its published hostname, route allowlist, signed Resend receipts and `no-store` behavior. The separate `api.delvane.app` virtual host accepts forwarded HTTPS requests from the connector, applies IP-based request limits and runs a method-and-path allowlist. Login and every authenticated request require an explicitly approved organization and user ID in addition to the existing session, role, CSRF and property checks. Build-time staging identity verification remains in the Flutter client. Private health routes, provider configuration, management and transmission/replay APIs remain off the native ingress. NTAK and VIZA official adapters remain disabled. There is no direct public host listener, database access or SSH dependency for the client.

Scheduled operations use the existing booking, automation rule and cleaning paths. The existing delivery worker handles approved invitations and retries. Signed receipts continue through the guest origin while owners are offline. The cutover preserves the prior Resend enabled or disabled state, existing secret and required test-recipient restriction. The application has no new Channex egress. Reservations already inside UAT can run through the normal workflows; live channel imports still need their separately authorized integration and network policy.

## Approved activation

1. The first package is staged and verified over the pinned SSH connection. For a subsequent transfer, run `deploy/guest-uat/stage-files.ps1 -Permanent`. On the UAT root console, copy `install-delvane-permanent.sh` to a root-owned path and compare its checksum with the value below before running it with the stage manifest checksum. The installer only imports the verified image and installs disabled units.
2. Use an existing approved synthetic UAT account. Create `/etc/delvane-permanent-uat/approved-accounts.json` as root with mode `0600`. The schema is a JSON array of pairs `[["organization_id", "user_id"]]`. Existing active accounts are verified against their tenant before the switch. Keep the actual allowlist outside Git. Use the existing UAT account password through the app login screen.
3. After explicit approval for the cutover, run `python3 -I /opt/delvane-permanent-uat/permanent.py approved-cutover /etc/delvane-permanent-uat/approved-accounts.json`. The script verifies the target and firewall policy, makes a fresh checksummed database backup, retains the previous app container, and probes the guest and native virtual hosts privately. A failed switch attempts to bring back the previous app against the same volume. No schema migration is required for this release.
4. After private checks pass and explicit hostname publication approval is recorded, add one published application to the existing Cloudflare Tunnel. Set hostname to `api.delvane.app`, service type **UNIX** and path `/run/delvane-guest-uat/origin.sock`, and HTTP Host Header to `api.delvane.app`. Leave the existing guest route unchanged. Set HTTPS redirection and a cache-bypass rule for `api.delvane.app`. The route must have a valid public Cloudflare certificate and preserve `X-Forwarded-Proto` and `CF-Connecting-IP`. Native clients use Delvane's HTTPS session login.
5. Double-click the bundled Windows release from its build folder and sign in with the approved account. Confirm authenticated dashboard and reservation reads, one controlled synthetic reservation, approval and receipt for the authorized Resend test recipient, failed login from a separate unapproved account, and 404 on both hosts for private routes that are outside each allowlist. Repeat after an approved reboot. Android, iOS and macOS releases can use the same `DELVANE_ENV=staging` and `DELVANE_API_ORIGIN=https://api.delvane.app` build definitions and require their own native smoke tests.

### Staged release

The archives and installer are owner-only under `/home/delvane-uat/delvane-guest-storage-3091/`. The application image combines the already verified guest UAT runtime with the source allowlist from the current working tree based on `4bdff53`. The image uses the existing Linux/AMD64 base and does not install new dependencies. `deploy/permanent-uat/package.py` checks the archive's OCI manifest against its Docker config digest and creates the controls and manifest. Preserve both files with any new build record.

| File or digest | SHA-256 |
| --- | --- |
| Application archive | `0f6350117698813c3e49e09a0385818deee62885b67307de6c7b9dad6582a949` |
| Controls archive | `6166304a00ee04f63250e93042affe4cb4095cdf1aee98fcfe2c7f467775510e` |
| Installer | `54e2aaa3e6ad5c2e1e44eb94308e49f15eab8d4088eca6ca98aef9b262864b0e` |
| Stage manifest | `958ac0091c6bdabbad3260067acf6ce0054aca09efb18193c983d4bf57960f29` |

```sh
install -m 0700 /home/delvane-uat/delvane-guest-storage-3091/install-delvane-permanent.sh /root/install-delvane-permanent.sh
sha256sum /root/install-delvane-permanent.sh
# Compare with the installer checksum above before proceeding.
bash /root/install-delvane-permanent.sh 958ac0091c6bdabbad3260067acf6ce0054aca09efb18193c983d4bf57960f29
```

Windows release bundle location is `apps/delvane_business/build/windows-remote-uat/x64/runner/Release/`. Keep the executable, DLLs and `data` directory together. It uses the normal HTTPS client and can be launched directly once the API hostname is published.

### Verification record

- 95 focused backend tests passed, including the native account, CSRF, role, tenant, scheduler, guest delivery, NTAK evidence and VIZA checks. Flutter analysis passed and the Windows x64 release built.
- Local Nginx over a Unix socket enforced host separation, HTTPS, login rate limits and `no-store`. It preserved native session cookies and CSRF headers, and forwarded the guest webhook body and signature headers intact.
- The candidate image ran on an isolated disposable PostgreSQL 17.12 database at schema 3091. Both worker health checks passed. Mock delivery retried after an app restart and processed an authenticated receipt, guest registration and link revocation. A checksummed dump restored into a separate database with tenant, delivery and encrypted contact data intact. Official reporting attempts stayed at zero.
- The older PostgreSQL smoke harness stopped at the WSL host's missing swap-limit enforcement. The disposable Pilot PostgreSQL lab supplied the startup, restart and restore results above. Service installation, remote worker health, approved reboot and real Windows sign-in are pending cutover and hostname publication.

## Recovery and operations

Run `python3 -I /opt/delvane-permanent-uat/permanent.py status` for service health, worker heartbeats, disk and memory headroom. The supervisor reports via systemd, and the daily backup status is recorded in `delvane-permanent-uat-backup.service`. Guest and native proxy access logs are off. No secret should be placed on a command line or pasted into logs. The initial server observation showed 1 vCPU, 1.9 GiB RAM, approximately 609 MiB available, 31 GiB free disk and no swap. This supports a small UAT workload. Routine backup, restart and operator smoke results should confirm headroom before higher concurrency.

The timer runs at 03:15 UTC daily with up to 15 minutes of jitter. It verifies a PostgreSQL custom-format dump, records SHA-256 and keeps the seven most recent scheduled copies under `/var/lib/delvane-uat-backups/permanent/`. The corresponding root-only recovery keys stay under `/var/lib/delvane-uat-recovery-keys/permanent/`. Earlier recovery snapshots are outside this retention path. Backups are local to the server. An off-host encrypted copy and monitoring destination would require separately authorized storage and credentials.

For application rollback, remove the API hostname from the Cloudflare Tunnel, then run `python3 -I /opt/delvane-permanent-uat/permanent.py rollback`. This disables the supervisor and timer and restores the previous guest application, relay and connector on the unchanged disk volume. Data written since cutover stays in PostgreSQL. No database restore is necessary for this release's application rollback.

For database loss, choose the most recent successful backup that predates the failure. On the UAT host, verify `sha256sum -c SHA256SUMS` inside the snapshot directory and check the archive with `pg_restore --list`. Restore to a **new** named disk-backed volume on a separate isolated PostgreSQL 17.12 instance. Initialize the least-privilege `delvane_uat` login with a new private password and restore with `pg_restore --no-owner --exit-on-error --role=delvane_uat` into the new target database. Use the matching root-only recovery key for the isolated app, verify schema 3091, decryption, and guest/private route behavior before proposing any database cutover. Keep the original volume and a report of changes after the snapshot recovery point. Do not start a clone with the existing live Resend credentials or any official reporting credentials.
