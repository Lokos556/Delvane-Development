# NTAK extended UAT execution

## Outcome

The updated harness ran the original Delvane image against disposable PostgreSQL 17.12 on local Linux Docker. It passed on the dedicated isolated bridge with the reviewed dual-stack host policy active. The optional retention path left the restored app ready on loopback and the rollback removed only the two lab containers. Delvane is awaiting deployment on Hetzner. The pinned SSH login succeeded, and the `delvane-uat` account could not access the Docker socket or read active nftables policy. The root-console setup and subsequent transfer remain pending. Both reporting gates stayed disabled.

## Changes

| File | Change |
| --- | --- |
| `tests/run_uat_postgres_smoke.sh` | Reuses and verifies the dedicated empty bridge and active host policy. Keeps the temporary isolated bridge option for local use. Checks network attachments, port bindings, resource limits, temporary mounts and app UID/root settings. Runs DNS, proxy and routing checks inside the application container before starting Uvicorn on loopback. Exercises stop, restart, crash recovery, backup and restore. Can retain the restored synthetic instance and prints the exact IDs for cleanup. |
| `tests/uat_preflight_egress.nft` | Dedicated `inet` table denies bridge-to-host and cross-network traffic in both address families. |
| `tests/uat_postgres_smoke.py` | Exercises ordinary owner historical stock and business-day correction actions, verifies encrypted snapshot lineage and current selling stock, rejects a blocked resend, and checks recovery of the stored evidence and daily history. |
| `.gitattributes` | Preserves LF on the three Linux control files when staging from Windows. |
| `docs/ntak/NTAK_UAT_PREPARATION.md` | Documents the approved administrator setup, validated image import, rehearsal and rollback commands. |

There are no application-source, schema, Flutter or runtime image changes. Migration **3090** and VIZA V01–V08 remain the application baseline.

## Local Docker and PostgreSQL

- Alpine WSL2, Docker Engine 28.3.3, cgroup v2 memory and swap controls, PostgreSQL 17.12. The test-only daemon was launched in a memory-enabled cgroup to exercise the actual limits. The first WSL attempt failed closed because its daemon could not enforce the swap cap. The daemon configuration correction was made for the local rehearsal.
- `nft -c`, atomic load, live rule comparison and removal succeeded in the local Linux environment. Real Docker negative checks rejected an internal bridge without isolated gateway mode, an IPv6-enabled bridge, a missing or changed host egress policy, and an unexpected running peer. The app namespace used the exact PostgreSQL peer with no published ports, IPv6 addresses, external or host IPv4 routes, or proxy variables. Kernel route checks used the documentation addresses `192.0.2.1` and `2001:db8::1` without sending packets. Embedded DNS resolved `isolated-pg` and failed to resolve `example.com.` with the loopback-only upstream. The local host policy was checked independently of these application gates.
- Verified PostgreSQL migration ledger through 3090, NTAK contracts, VIZA assets, two synthetic tenants, role and property isolation, CSRF, secure cookies, missing credentials, blocked reporting with zero attempts, redacted evidence and both transmission gates. The dated correction preserved two encrypted daily snapshots, their source-correction lineage and the selling count. A blocked job rejected explicit replay. The first historical fixture attempt lacked the effective IFA rate. The passing run recorded that rate through the ordinary PMS API.
- Graceful app restart and forced app-process crash recovery retained the existing PostgreSQL data and evidence. The logical dump restored into a separate database under the limited app role. The restored instance passed readiness, migration and evidence decryption, and retained both daily snapshots. The source database and dump stayed in disposable PostgreSQL tmpfs.
- Docker reported about 106 MiB for Delvane and 109–110 MiB for PostgreSQL after the workflow, and about 70 MiB and 146–147 MiB after restore. Cgroup peaks across verified runs were up to approximately **229 MiB for Delvane** and **173 MiB for PostgreSQL**. The caps are 320 MiB and 768 MiB. The application cap was raised after a repeat measured a 229 MiB peak under the initial 256 MiB limit. This measures the synthetic lab and leaves headroom for the database's memory-backed data and restore. The final retained-instance run passed at those caps, with peaks of 166 MiB and 122 MiB. The test runs one app at a time. The local rollback preserved existing stopped lab assets and left the dedicated bridge empty.

## Hetzner status and administrator action

| Stage | Actual result |
| --- | --- |
| A — Inspection and network preparation | Pinned ED25519 SSH succeeded as `delvane-uat` on `delvane-test-01`. Socket permissions remain `root:docker`, and API access returned permission denied. The unprivileged systemd query reported UFW active while the administrator described filtering as inactive. Review the effective IPv4 and IPv6 rules in the root console. Bridge and host policy remain to be verified there. The previous host measurement showed 1,510 MiB available and zero swap. |
| B — Archive transfer | Local SHA-256 hashes verified. Remote transfer, checksum and imports remain pending. |
| C — Application execution | Pending the root-console isolation proof and administrator execution. No remote containers were started. The local rehearsal and rollback are ready to repeat with the reviewed control bundle. |

Start with the [root-console commands](NTAK_UAT_PREPARATION.md#administrator-setup-on-delvane-test-01) to verify the daemon, existing workloads, keys-only management path, Cloud firewall and effective rules. Stage the small control bundle over the pinned channel. The administrator then creates the empty bridge and applies the dedicated table with a syntax check. Once the administrator has verified the live controls, transfer the image archives and run the [pinned-image procedure](NTAK_UAT_PREPARATION.md#verify-images-and-run-the-lab). Run Docker and nftables as the existing administrator. Leave the UAT account's current privileges in place.

## Artifacts and source traceability

Application-source checkpoint `1fc6512d838e1c4f93a67f724b59f444457f820e` (`ntak-uat-package-checkpoint`). The original app archive retains its own build provenance, including the reviewed packaging and database compatibility changes documented in the [UAT runbook](NTAK_UAT_PREPARATION.md). The current working-tree additions are in the separate control bundle and outside the application Docker build context. The bundle contains three reviewed files, their hashes and a source revision record. No runtime rebuild was needed.

| Artifact in ignored `build/ntak-uat` | SHA-256 |
| --- | --- |
| `delvane-uat-290b361-local.tar.gz` | `d991b2e6ea3cd35a181971c80cf1132f7f82aea656a31db6745dba79d84ea732` |
| `preflight-control-1fc6512.tar.gz` | `87ec1b5ae3ff7e9b018f0270a61f36fb96c0617f93f3de076294b3165ea53b78` |
| `postgres-17.12-linux-amd64-local.tar.gz` | `c790ed591c8913ca82e11bffb265ba43efe8a9a80ce365bf40f68892128ab994` |

The application image ID is `sha256:08b340b1e459d2a8ecedbaa06c1317ef22c9cb2f87412dee0bfe7db07182fe35`. The PostgreSQL archive's config matches `sha256:39d36505873241b90584a61078c0a3af0a226a363854fcc2d722a72ce7a00500`. gzip integrity, the bundled file contents, and Git exclusions passed. The Docker allowlist admits runtime modules and official contract resources and excludes the new test controls, release files, databases and secrets.

## Release checks

**Windows x64.** Launched the existing release built for loopback port 39847. The rendered sign-in displayed the isolated workspace address, focus navigation worked, and a direct keystroke reached the password field. Bulk input and accessibility editing did not complete sign-in. An actual disposable backend on that port independently passed owner and manager authentication, loading three properties and reservations, owner historical stock correction, NTAK diagnostics, and redacted export. The manager was denied both owner actions. Those API results leave the authenticated Windows UI walkthrough pending. The window and synthetic backend were closed. To finish manually, use the [Windows checklist](NTAK_UAT_PREPARATION.md#local-windows-and-xiaomi-smoke-checklist) and check Apartments and rooms, the dated stock editor, and the government diagnostics/export panel after owner sign-in.

**Android.** The existing release APK is unsigned and its two output paths have the same SHA-256 `7901f57bd0875076726b4417e886f8260f158e8c2d9e6993e80fbcb3188a2c50`. ZIP CRC and 16 KiB zip alignment passed. Package `com.delvane.delvane_business` version `0.1.0` includes arm64-v8a, armeabi-v7a and x86_64. Minimum SDK is 24 and target SDK is 36. Manifest inspection showed the Internet permission and no native camera declaration in this artifact. The native binary contains the loopback local origin. The native staging build-time configuration check passed separately using the example origin without a connection. ADB listed no devices. Physical verification remains pending.

For the Xiaomi 15, start the disposable local backend, enable USB debugging and approve the workstation on the device, build the debug APK and run `powershell -NoProfile -ExecutionPolicy Bypass -File .\apps\delvane_business\tool\connect_android.ps1 -Install` from the repository root. In the isolated workspace, sign in with a fictional owner, switch properties, open reservations and the dated stock editor, inspect NTAK diagnostics, confirm both reporting gates and check redacted export. Repeat the key screens in Hungarian and English. Recheck session restore and sign-out. Perform the camera/OCR checklist only with a synthetic specimen. A later remote release requires the approved HTTPS staging ingress and a properly signed package. Preserve an existing installation if its build or signing identity conflicts.

## Regression results and remaining official work

- **Backend:** 274 passed, one known failure and two dependency deprecation warnings. The selected suites covered NTAK, VIZA, reservations, physical units, actual stays, guest reporting, financial and business days, environment and tenant isolation. The existing `test_v293.py::test_modification_preserves_manual_fields_and_cancellation_updates_cleaning` still reports `incomplete` where the assertion expects `complete`. No existing assertion was changed.
- **Flutter:** 304 passed on Flutter 3.50.0 / Dart 3.14.0, with clean analysis. The separately configured staging-origin check also passed. All five scanner suites passed on synthetic samples.
- **Git:** Reviewed working-tree changes are uncommitted. Both earlier checkpoints and the UAT package checkpoint remain in place. `git diff --check` passed. Image archives, release builds and runtime data remain ignored or outside the repository.

Official interoperability still requires the documented NTAK v9 signing profile, inbound response security, test certificate and trust/profile verification, property binding, and the authoritative start-date result. Task 5 normalization, country encoding and the unresolved validation chronology stay documented. The rehearsal remains at 22 passed offline, three partial, two externally blocked and zero officially validated. Both government transmissions stayed disabled, and no official endpoint, operational database or existing government key was accessed.
