# NTAK UAT preparation

Baseline `ntak-offline-rehearsal-checkpoint` → `290b361d3027a457604abbdc0c5e1f35d78e9df2`, migration **3090**. The [27-case matrix](TASK20_READINESS.md#validation-matrix) records 22 offline passes, three partial and two externally blocked. There are zero official results. VIZA V01–V08 and both transmission gates are preserved. The owner has authorized the isolated synthetic Hetzner preflight. [Current execution status and artifacts](UAT_EXTENDED_EXECUTION_REPORT.md)

## First three actions

1. **Request the authoritative v9 packet under support ticket 150337.** Ask for a working signed request and its receipt and verification exchange, the complete profile and trust materials, the AD_01 result schema, and confirmation that the proposed first booking test is eligible against the assigned test property. Use the questions below. Send public support information only.
2. **Finish local release checks.** The image and disposable PostgreSQL verification are complete. Use the verified archive and dependency manifest below. Finish the listed Windows release UI and Xiaomi checks on approved test environments. Keep both reporting transports disabled.
3. **Complete the authorized Hetzner preflight.** Have the administrator verify the host and apply the dedicated bridge policy below. Transfer the pinned images after isolation is verified, then run the synthetic rehearsal. An official test and any government credential access require separate authorization.

## Work and approvals

| Status | Work |
| --- | --- |
| **Ready now** | Tagged baseline, reviewed local package and digest, embedded WSDL/XSD validation, PostgreSQL migration 3090 and restart check, disabled adapters, encrypted evidence and redacted exports, Windows launch smoke and unsigned Android release package. |
| **Can be prepared locally** | Review deployment and backup/restore procedures. Finish the Windows release UI and Xiaomi checks. After authoritative answers arrive, implement and verify only the approved signer, response security and onboarding contract offline. |
| **Requires administrator execution** | Inspect Docker and nftables, provision and verify the bridge, and run the already-authorized synthetic lab. The SSH user's existing access is sufficient for the subsequent verified file transfer. |
| **Requires official clarification or materials** | Signing references/digests/namespaces and time rules, inbound response security, current certificate profile and trust material, portal identity binding, authoritative start-date payload or approved provisioning basis, and first-test eligibility. Separate full-suite blockers are listed below. |
| **Requires an official interoperability test** | A separately approved one-booking submit and correlated verification on the designated test endpoint. Record mTLS and response validation results. Leave all other government traffic denied. |

## Authoritative prerequisites to resolve

Local source references use the printed pages of the [v9.07 interface PDF](<v9/ntak-pms-interface-v907-eng-1794401423%20(1).pdf>), the [supplied contract inventory](CONTRACT_INVENTORY.json) and the [Task 18 security review](TASK18_SIGNING_READINESS.md).

| Gate | Required decision or material |
| --- | --- |
| **Test address and portal authorization** | Ticket 150337 supplied the exact endpoint `https://pms.tesztntak.hu/ntak/v9` and reports issuance for DELVANEAI using the existing Hetzner CSR. Confirm the authorized test property, service/operation routes, permitted source network and test window with NTAK. Obtain the **assigned 10-character accommodation registration number**, provider tax number, portal-selected software ID/version, and approved onboarding date. The eight-character reporting identifier belongs outside the v9 registration-number field. Do not obtain destination URLs from the WSDL's localhost example. PDF §5.3 pp. 28–29, §9.1.8 p. 64, §9.5.4 pp. 99–100. |
| **Certificate and trust** | The issued universal certificate serves as both mTLS client identity and message-signing identity. Verify in place that the certificate matches the key and the approved property/software pairing. Obtain the current client chain, approved NTAK test server trust anchors/intermediates, revocation checking policy and any separate response signer trust. Confirm the exact CN and OID `2.5.4.97` representations and portal software mapping. The existing certificate and key are to be reused. The documented CSR profile for a future issuance is PKCS#10, SHA-256 and RSA-4096. Issuance is recorded. Installation, binding, validity, chain, revocation and interoperability have not been verified. PDF §3.2 p. 16, §6.1 pp. 30–33, §9.1.8 p. 64. |
| **Request signing** | Supply a known-good signed SOAP envelope and confirm ID/reference coverage. §9.1.7 pp. 61–63 shows Timestamp and Body in an example while p. 63 specifies one Body reference. Confirm allowed digest algorithms and pairings, exclusive canonicalization prefix lists, DirectReference to the Base64 X.509 token, and the strict Reference resolver rules. The documented signature family is RSA-SHA256/384/512. SHA1 is excluded. Confirm Created/Expires and skew/replay policy, including how a permitted unchanged resend refreshes its security envelope within the documented 300-second Created window. The checkpoint implements independent primitives, with no complete signer or official HTTP connector. |
| **Response security** | Obtain the correspondence between request, synchronous receipt, verification and fault responses. Confirm whether each response must be signed, trusted signer roles/chain, required signed elements and timestamps, and acceptable security correlation. Verify mTLS trust, response authentication under that profile, schema and processing-ID correlation before using any response. The supplied business schemas and PDF §§7.1, 9.1.7 do not establish a response signature policy. |
| **Start date and scheduling** | PDF §7.3.3 p. 46 places `elvartAdatszolgaltatasKezdoDatuma` after processing. The information/verification WSDL responses omit it, and the pp. 41–42 request interval is absent from the supplied request. Ask for a matching WSDL/XSD and a signed example with exact namespace, nesting and retrieval operation, or explicit confirmation of an authorized operator-provisioned start date for the initial booking smoke. Keep automatic information submission and scheduling blocked without valid evidence and a supported contract. The existing configuration accepts an operator-entered date with evidence. That input does not implement AD_01. |

For full validation also resolve `EGYEBKULFOLDI` versus `OrszagKodType` for ELO_01B/ELO_03 (§9.3.1 p. 86 and booking WSDL), the after-arrival booking policy (pp. 54/87), first-identity normalization (pp. 57–59), and the repeated ES_01A/ES_02 and ES_04B/ES_05 instructions in the v1.07 checklist. Obtain the municipality's IFA policy if required by the property. None of those gaps permits a substitute value, duplicate stay, or change to an official schema. [Handoff and blockers](NTAK_HANDOFF.md#unresolved-technical-requirements)

## Isolated Hetzner setup

**Package and boot.** Target a supported Linux distribution with a reliable UTC time source, TLS trust tooling, the repository's Python 3.12 container runtime and dedicated PostgreSQL with the `requirements-production.txt` driver. Deploy the verified, versioned artifact only after approval. Use a dedicated unprivileged service account with read-only code and a dedicated writable data directory. Keep the previous package available for rollback. The updated Docker allowlist includes the backend modules and their in-code migrations, the five NTAK WSDLs with embedded XSDs, the VIZA schema and runtime lookups, and the served browser pages and assets. The build compiles both contract sets and the application runs as UID/GID 10001. The container contains no developer or operator environment file, credentials or database. Demo seeding is disabled in the test environment. The local smoke seeds its two synthetic tenants through its test harness only. Agree an authorized first-owner provisioning procedure for any later server installation. [Repository deployment prerequisites](../../POSTGRESQL_DEPLOYMENT.md)

**Environment.** For the existing Flutter HTTPS handshake, use production **runtime hardening** with `ROSA_APP_ENV=production`, `ROSA_DEPLOYMENT_ENVIRONMENT=staging`, a unique non-secret `ROSA_DEPLOYMENT_ID`, `ROSA_SECURE_COOKIES=1`, `ROSA_DEMO_MODE=0` and `ROSA_AI_PROVIDER=local`. Use a new UAT-only `ROSA_DATABASE_URL`, `ROSA_DATA_DIR` and `ROSA_ENCRYPTION_KEY` sourced from the server's protected secret store. Put no `.env.local` in the application tree or service user's environment adoption paths and mount no sibling operational checkouts. Give the UAT service access to one PostgreSQL database and its role only. Verify by access denial and separate database identity, not by copying a working database. Keep local reporting preparation paused at first. After UAT-only isolation is proved, local synthetic preparation may be enabled for one test property while transmission remains blocked. NTAK's property configuration uses `environment=test`. Keep VIZA unconfigured for official delivery and omit all unrelated provider credentials.

**Ingress and egress.** Use a separate HTTPS hostname for the PMS behind VPN or a restricted test network. Give testers only the PMS origin. Terminate its trusted web TLS certificate at the ingress, bind the app privately and trust forwarding headers only from that ingress. Restrict SSH to the approved management path and keep PostgreSQL and health endpoints private. Initially block outbound connections from the application to all government and production hosts. Permit only required internal services such as the isolated DB, DNS resolver and time source. Fetch reviewed dependency artifacts on the build side. After an approved live-test decision, allow only the confirmed test host on TCP 443 and any explicitly approved revocation infrastructure. Keep exact URL and hostname verification in the adapter, reject redirects and alternate destinations, use the approved CA chain, and use TLS 1.2 or better as the local floor. Allow egress without TLS interception. There must be no UAT code/configuration route to production, including through an owner changing the property's environment. Require the future test adapter to reject other properties, non-test environments and unapproved operations independently of the firewall. Close the egress window after the test or upon a stop condition.

**Certificate installation and renewal.** Reuse the certificate issued from the existing server-held key and CSR. With separate authorization, an authorized host operator installs the public certificate and required chain beside the existing key through the server's protected credential facility. Never move or expose the private key. The current file loader expects an operator-managed credential root and scope-specific reference containing `certificate.pem` and `private-key.pem`. Use owner-restricted directories and service-readable files only, for example service-owned mode 0700 directories and 0600 files or an equivalent read-only credential mount. Keep the approved server CA store separate from the client chain. If the key is encrypted or non-exportable, the current file loader cannot use it directly. Preserve that protection and resolve an approved local credential integration. Keep `binding.json` outside Git, with explicit system, tenant, property, environment, registration, tax/software identity, allowed endpoint, reference and public SHA-256 certificate fingerprint. Enable the property only after permission, RSA strength, key-match, binding, expiry and chain checks succeed. Until key access is separately approved, leave `DELVANE_NTAK_CREDENTIAL_ROOT` and `DELVANE_NTAK_CREDENTIAL_REFERENCES` unset. The management status endpoint can read the private-key file to test the match when both are configured. Public metadata may be checked separately with dates and fingerprint only, then compared in place. Record pass/fail and expiry instead of collecting certificate/key files. Schedule renewal ahead of NTAK's cutoff three days before the certificate expiry. Later renewal follows the authorized portal's process and in-place key management, with egress closed during changeover. Confirm the updated chain and binding before any new run. On compromise or loss, stop traffic and use the authorized full revocation procedure. Preserve the issuance rule of one certificate per key. [Certificate profile, renewal and open trust questions](TASK18_SIGNING_READINESS.md#normative-security-contract-and-boundaries)

**Logging, backup and rollback.** Limit logs to UTC timestamps, scoped correlation IDs, state transitions and structured codes. Suppress headers, bodies, private-key data, secret values, guest identity, raw diagnostics and submitted field values. Restrict owners' evidence access to the relevant property and retain encrypted protocol evidence server-side with audited access. Give any reviewer the redacted export by default. Back up the dedicated DB and evidence before startup migrations and before opening egress. Store the UAT encryption key separately in the secret manager and test restoration into another isolated database with the corresponding key. Do not include the private signing key in an application image, database dump or run evidence. For rollback, close egress, pause dispatch, preserve jobs/receipts/evidence, and return to the known disabled package. Coordinate a schema-compatible restore of the UAT-only snapshot if needed. A database restore can reintroduce jobs already attempted remotely. Reconcile any such job from the retained processing IDs and evidence before reopening egress. Never blindly replay it.

**Preflight evidence.** After approval, verify the PMS liveness and private readiness endpoints from the isolated network. `/health/ready` checks database connectivity and the actual migration ledger, which must report **3090** for this baseline. Verify the Flutter deployment handshake, Secure/HttpOnly cookies, CSRF, logout and role/property denial. Record the code revision, tenant/property scope, empty or reviewed outboxes, certificate metadata checks and disabled NTAK/VIZA statuses. Leave the certificate-preflight result labeled local. [Flutter deployment and authentication controls](../../apps/delvane_business/API_ENVIRONMENTS.md)

## Action 2 local verification

**Package.** Built Linux x86-64 `delvane-uat:290b361-local` from the checkpoint plus the reviewed packaging and PostgreSQL query changes. The Docker image ID is `sha256:08b340b1e459d2a8ecedbaa06c1317ef22c9cb2f87412dee0bfe7db07182fe35`. The ignored local bundle is `build/ntak-uat/delvane-uat-290b361-local.tar.gz`. Its SHA-256 is `d991b2e6ea3cd35a181971c80cf1132f7f82aea656a31db6745dba79d84ea732`. The same directory contains the exact packaged dependency list, image ID and checksum. Rebuilding from the unconstrained base/package references can resolve different versions, so use the reviewed archive for this candidate and repeat verification for a new build.

The final `/app` contained 50 runtime files. Six fictional exclusion probes covered a development module, stray browser asset, environment file, database, VIZA fixture and NTAK PDF. All were absent. The initial image admitted stray files through re-included directories. The final allowlist re-excludes their contents before admitting each required asset.

**PostgreSQL.** A fresh PostgreSQL 17.12 database passed liveness and readiness, then passed again after app restart. The production-hardened staging app reported migration 3090, and the contiguous government migrations 3074–3090 were checked in the ledger. The database role was neither a superuser nor able to create roles/databases or connect to the administrative database. The smoke verified both compiled contract sets, a synthetic booking automatically captured into the blocked NTAK queue, diagnostic lookup, encrypted stored evidence, redaction and evidence hash, CSRF, secure session cookies, same-tenant wrong-property and cross-tenant denial, and denial of an in-place switch to production reporting. Missing NTAK credentials produced `missing_certificate_or_key`. No NTAK delivery attempt occurred and VIZA returned disabled status. Neither lab container published a port. The network was internal with no default egress, and restart retained the blocked evidence. The first startup failed on literal percent signs in SQL `LIKE` patterns with psycopg. The shared PostgreSQL SQL adapter now escapes literal percent signs before translating parameters. SQLite is unaffected. No new migration or protocol behavior was added.

For a repeat run on a local Linux Docker engine, first build or load the candidate image and pull the named disposable PostgreSQL image. Then run the checked-in harness. It creates a temporary internal Docker network, seeds only an empty synthetic database, checks the actual HTTP app, restarts it, restores a synthetic backup into a separate database and cleans up its own containers and network.

```sh
docker --host unix:///var/run/docker.sock build --tag delvane-uat:local .
docker --host unix:///var/run/docker.sock pull postgres:17-bookworm
sh tests/run_uat_postgres_smoke.sh delvane-uat:local postgres:17-bookworm
```

**Windows.** The existing x64 release opened a responsive sign-in window against a verified disposable 39847 loopback backend and accepted an individual keyboard-input probe. Desktop automation did not reliably complete text entry and sign-in. The real loopback API separately passed fictional owner authentication, owner historical stock correction, NTAK diagnostics and redacted export. Flutter widget tests exercised the reservation views and inventory, diagnostics and evidence controls. The manual release-window steps below remain open.

**Android.** The existing unsigned APK passed manifest and ZIP alignment checks. The application ID and launch activity are `com.delvane.delvane_business` and `com.delvane.delvane_business.MainActivity`. Minimum API is 24, and the package includes arm64-v8a, armeabi-v7a and x86_64. APK signature verification reports the expected missing signature. There was no authorized device or configured emulator. Install only a compatible signed build and use the Xiaomi steps below. Physical-device verification remains pending.

**Regressions.** The final selected backend run passed 160 checks in 173.93 seconds with two existing dependency deprecation warnings. It covered deployment metadata, NTAK contracts/reporting/security/evidence/shared chronology and VIZA contracts/security/delivery/rehearsal. The separate baseline subset passed 108 overlapping checks. Flutter 3.50.0 / Dart 3.14.0 passed 304 tests and analysis with no issues. The documented `test_v293` baseline discrepancy remains outside this change. `git diff --check` passed.

**Disposition.** The reviewed archive is ready for an explicitly approved, egress-blocked Hetzner preflight. That approval covers inspection only unless the user also authorizes installation. Test-server bootstrap, ingress and credential checks, Windows release UI and Xiaomi checks, and the official signing, response security and onboarding materials remain open. No server or government endpoint was contacted. Both official transmission gates stayed closed.

## Local package checkpoint

The annotated tag `ntak-uat-package-checkpoint` identifies the reviewed source. Resolve its commit with `git rev-parse 'ntak-uat-package-checkpoint^{}'`. The preflight uses the original checksummed archive above. Its build inputs were baseline `290b361d3027a457604abbdc0c5e1f35d78e9df2` plus the then-uncommitted runtime changes below. Test harness and runbook changes are excluded from the image. No Compose configuration was present in this checkout.

| Archive build input | Git blob ID with Git line-ending normalization |
| --- | --- |
| `.dockerignore` | `a116124ed1e1a68f0675fa3369f7f97694155b36` |
| `Dockerfile` | `16ab519c32a6453277e8c0e24ef85fac9bd53a8f` |
| `app.py` | `f9e36ca8dcf6cf3a17b9b618b071205ed953df79` |

The checkpoint rebuild used 52 allowlisted Git index inputs. Their SHA-256 manifest is `74eadd3dd74bd27bfbeeb49a8b4cb99fade62050882d2d2631f9dcb859e35e14` in `build/ntak-uat/checkpoint-source-sha256.txt`. The rebuild image ID is `sha256:c2c5f55dcc9c5218e8271b0fa9a598bbbfa982bd98e82ab2a25d5ea2fe9d213b`. It matches the archive's 50 runtime file paths and contents after CRLF/LF normalization, Python 3.12.16, 23 installed package versions and UID 10001. Thirty-five files differ only in line endings. The archive carries mode 0777 on its files from the Windows build context. The checkpoint Dockerfile now normalizes file modes to 0644 and directory modes to 0755 on future builds. This changes permissions and the image ID. The image is not byte-for-byte reproducible from this revision.

**Use the original archive only with the harness's verified read-only app root and unprivileged account.** The harness checks both before app startup. The ignored comparison report is `build/ntak-uat/checkpoint-image-comparison.json`, SHA-256 `af9552aa593a470d640f684c06097c06dc8019540a9aa304ab545c4f7c781dc8`. Archive, release APK/Windows artifacts and the comparison files stay outside Git.

Both the reloaded archive and the rebuild passed the fresh PostgreSQL 17.12 smoke, migration 3090, app restart and a fresh-database backup/restore with decryptable blocked evidence. The archived image checksum was reverified. The latest focused run passed **150 deployment and NTAK/VIZA backend checks**, with two existing dependency deprecation warnings. The prior 304 Flutter checks and clean analysis remain the client baseline. No Flutter code changed. NTAK has zero attempted deliveries and its unresolved signer gate remains active. The VIZA default adapter and monitor remain fail-closed. The previous NTAK and VIZA checkpoint tags and official case counts were preserved.

## Hetzner preflight execution gate

**Approval boundary.** The isolated synthetic preflight is approved, including inspection, scoped bridge controls, archive transfer and disposable execution. Use the established host pin and SSH agent. Administrator execution uses the existing root console. Keep official adapters disabled and omit government keys and credentials.

### 1. Verified SSH and private staging from Windows

The initial SSH inspection can run without Docker privileges. The PowerShell block re-verifies the existing host-key pin, checks the unlocked identity and prepares a private staging directory. Run it with the control archive first. Set the input file to an approved image archive only after the administrator verifies isolation.

```powershell
$uatHost = '2.29.168.55'
$uatRemote = "delvane-uat@$uatHost"
$uatGit = 'C:\Program Files\Git\usr\bin'
$uatSshDirectory = Join-Path $env:USERPROFILE '.ssh'
$env:SSH_AUTH_SOCK = (Get-Content -LiteralPath (Join-Path $uatSshDirectory 'delvane-uat-agent-socket') -Raw).Trim()
$uatKey = Join-Path $uatSshDirectory 'id_ed25519'
& "$uatGit\ssh-add.exe" -l
if ($LASTEXITCODE -ne 0) { throw 'The Git for Windows SSH agent has no unlocked key.' }
$uatEntry = @(& "$uatGit\ssh-keygen.exe" -F $uatHost -f (Join-Path $uatSshDirectory 'known_hosts') |
    Where-Object { $_ -match '^[^#]+\s+ssh-ed25519\s+' })
if ($uatEntry.Count -ne 1) { throw 'Expected one locally pinned ED25519 host key.' }
$uatPin = [IO.Path]::GetTempFileName()
try {
    Set-Content -LiteralPath $uatPin -Value $uatEntry[0] -Encoding ascii
    $uatFingerprint = (& "$uatGit\ssh-keygen.exe" -lf $uatPin -E sha256) -split '\s+'
    if ($LASTEXITCODE -ne 0 -or $uatFingerprint[1] -cne 'SHA256:H+UWQhcjqvjgZuv9U+24xKnSy6K254h9zDm6TKh9rCo') {
        throw 'The saved host key does not match the verified fingerprint.'
    }
    $uatOptions = @('-F', 'none', '-i', $uatKey, '-o', 'Port=22', '-o', 'BatchMode=yes',
        '-o', 'IdentitiesOnly=yes', '-o', 'StrictHostKeyChecking=yes', '-o', 'HostKeyAlgorithms=ssh-ed25519',
        '-o', "UserKnownHostsFile=$uatPin", '-o', 'GlobalKnownHostsFile=none')
    & "$uatGit\ssh.exe" @uatOptions $uatRemote 'test "$(hostname -s)" = delvane-test-01 && umask 077 && install -d -m 0700 "$HOME/delvane-uat-preflight"'
    if ($LASTEXITCODE -ne 0) { throw 'Verified SSH staging failed.' }
    $uatFile = 'build/ntak-uat/preflight-control-1fc6512-v2.tar.gz'
    & "$uatGit\scp.exe" @uatOptions $uatFile "$($uatRemote):delvane-uat-preflight/"
    if ($LASTEXITCODE -ne 0) { throw 'Verified SSH file transfer failed.' }
} finally {
    Remove-Item -LiteralPath $uatPin
}
```

### 2. Isolated network and application execution

The [extended execution report](UAT_EXTENDED_EXECUTION_REPORT.md) identifies the reviewed control bundle, both image archives and their SHA-256 digests. Keep the software checkpoint separate from the control bundle, which contains the working-tree harness changes. Complete the root-console inspection first. The current SSH account cannot perform the Docker or nftables steps. Use the pinned Git for Windows SSH channel to place the control bundle in the operator's private staging directory. Wait for independent network verification before transferring the images.

#### Administrator setup on delvane-test-01

Verify the Hetzner Cloud firewall attachment and approved IPv4/IPv6 SSH sources in the console. Run the following as the existing administrator from the root console. Review the daemon, existing workload and firewall output before changing anything.

```sh
test "$(hostname -s)" = delvane-test-01
docker --host unix:///var/run/docker.sock version
docker compose version
docker ps -a --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
docker network ls
iptables --version
ip6tables --version
sshd -T | grep -E '^(permitrootlogin|passwordauthentication|kbdinteractiveauthentication|pubkeyauthentication|allowusers|allowgroups) '
nft list ruleset
ss -lntup
free -m
df -h /var/lib/docker
```

Verify the dedicated host has no conflicting workloads or listeners. Confirm the effective filter and forwarding rules in both address families. UFW service state alone does not show these rules. Staging paths below assume the previously verified SSH account. The commands reject a network, interface or table that already occupies the reserved names. Review any collision before reuse.

```sh
set -eu
umask 077
test "$(hostname -s)" = delvane-test-01
stage=/home/delvane-uat/delvane-uat-preflight
lab=/root/delvane-uat-preflight
install -d -m 0700 "$lab"
install -m 0600 "$stage/preflight-control-1fc6512-v2.tar.gz" "$lab/"
cd "$lab"
printf '%s  %s\n' \
  26d835571136275d0d2a6b3e76c4c6505cd34984416b6c58c3fc602a64bfeec1 \
  preflight-control-1fc6512-v2.tar.gz | sha256sum -c -
tar -xzf preflight-control-1fc6512-v2.tar.gz
sha256sum -c CONTROL-SHA256SUMS
docker_local() { docker --host unix:///var/run/docker.sock "$@"; }
network=delvane-ntak-preflight
if docker_local network inspect "$network" >/dev/null 2>&1 ||
   ip link show dev br-delvane-uat >/dev/null 2>&1 ||
   nft list table inet delvane_uat_preflight >/dev/null 2>&1; then
    echo 'A reserved UAT network, bridge or table name already exists.' >&2
    exit 1
fi
nft -c -f tests/uat_preflight_egress.nft
nft -f tests/uat_preflight_egress.nft
docker_local network create --driver bridge --internal --ipv6=false \
    --opt com.docker.network.bridge.gateway_mode_ipv4=isolated \
    --opt com.docker.network.bridge.name=br-delvane-uat "$network"
settings=$(docker_local network inspect -f '{{.Driver}}|{{.Internal}}|{{.EnableIPv6}}|{{index .Options "com.docker.network.bridge.gateway_mode_ipv4"}}|{{range .IPAM.Config}}{{if not (eq (printf "%v" .Gateway) "" "invalid IP")}}present{{end}}{{end}}|{{len .Containers}}' "$network")
test "$settings" = 'bridge|true|false|isolated||0'
test -z "$(ip -4 -o addr show dev br-delvane-uat)"
rules=$(nft -s -y -n list table inet delvane_uat_preflight)
test "$(printf '%s\n' "$rules" | tr -d '[:space:]')" = "$(tr -d '[:space:]' <tests/uat_preflight_egress.nft)"
printf '%s\n' "$settings" "$rules"
```

The dedicated nftables table drops host and routed traffic for this bridge in both address families. It leaves the host and Docker-managed policy in place. The two workloads share only this bridge. PostgreSQL listens on TCP 5432, and the application listens on its own loopback. Neither publishes a port. The harness verifies the live rules and bridge again before using them. It disables container IPv6, overrides upstream DNS to container loopback, checks for proxy variables and verifies external and host route denial inside the application namespace before launching the server. It resolves and connects to the disposable PostgreSQL peer, then verifies that a harmless public DNS name fails resolution. No government URL is required.

#### Verify images and run the lab

Both original archives are staged and SHA-256 verified. The first Phase C attempt imported the images and stopped at image ID verification. The build records pinned the classic Docker config digests. Docker's containerd image store reports the target manifest digest as the image ID. Both reported Hetzner prefixes match the OCI manifest digests independently recalculated from the pinned archives. Full installed image ID and platform checks run at the root console before startup. [Docker storage documentation](https://docs.docker.com/engine/storage/containerd/), [Moby image inspection implementation](https://github.com/moby/moby/blob/master/daemon/containerd/image_inspect.go)

| Archive | Config digest | OCI manifest digest |
| --- | --- | --- |
| Delvane | `sha256:08b340b1e459d2a8ecedbaa06c1317ef22c9cb2f87412dee0bfe7db07182fe35` | `sha256:59220537262a50c84cc66be88890a5485d9a7da2f2b5fa91a10e90b8f5171720` |
| PostgreSQL 17.12 | `sha256:39d36505873241b90584a61078c0a3af0a226a363854fcc2d722a72ce7a00500` | `sha256:ab4586ee3c07b4f65cf3daaf55ed008ff619b496bff60e361c30d664bca78401` |

The corrected block reuses images already installed by either full archive-derived ID. It verifies the live, scoped firewall policy and dedicated bridge. An unset gateway can render as an empty field or `invalid IP`. A real configured gateway still fails. The harness separately checks bridge addresses, network attachments and routes. [Go address formatting](https://pkg.go.dev/net/netip#Addr.String)

```sh
(
set -eu
umask 077
test "$(id -u)" -eq 0
test "$(hostname -s)" = delvane-test-01
unset DOCKER_CONTEXT DOCKER_HOST
docker_local() { docker --host unix:///var/run/docker.sock "$@"; }
verify() { printf '%s  %s\n' "$1" "$2" | sha256sum -c -; }
image_format='{{.Id}}|{{.Os}}|{{.Architecture}}'

verified_id() {
    case "$1" in
        "$2|linux|amd64"|"$3|linux|amd64") printf '%s\n' "${1%%|*}" ;;
        *) printf 'Unexpected installed image or platform for %s: %s\n' "$4" "$1" >&2; return 1 ;;
    esac
}

resolve_image() {
    for reference in "$1" "$3" "$2"; do
        if info=$(docker_local image inspect -f "$image_format" "$reference" 2>&1); then
            verified_id "$info" "$2" "$3" "$1"
            return $?
        fi
        case "$info" in
            *'No such image:'*|*'No such object:'*) ;;
            *) printf '%s\n' "$info" >&2; return 1 ;;
        esac
    done
    docker_local image load -i "$4" >&2 || return 1
    info=$(docker_local image inspect -f "$image_format" "$1") || return 1
    verified_id "$info" "$2" "$3" "$1"
}

home_dir=/home/delvane-uat
stage="$home_dir/delvane-uat-preflight"
install -d -m 0700 /root/delvane-uat-preflight
cd /root/delvane-uat-preflight
control=preflight-control-1fc6512-v2.tar.gz
install -m 0600 "$stage/$control" .
verify 26d835571136275d0d2a6b3e76c4c6505cd34984416b6c58c3fc602a64bfeec1 "$control"
tar -xzf "$control"
sha256sum -c CONTROL-SHA256SUMS

uat_archive=delvane-uat-290b361-local.tar.gz
pg_archive=postgres-17.12-linux-amd64-local.tar.gz
install -m 0600 "$home_dir/$uat_archive" .
verify d991b2e6ea3cd35a181971c80cf1132f7f82aea656a31db6745dba79d84ea732 "$uat_archive"
install -m 0600 "$stage/$pg_archive" .
verify c790ed591c8913ca82e11bffb265ba43efe8a9a80ce365bf40f68892128ab994 "$pg_archive"

network=delvane-ntak-preflight
settings=$(docker_local network inspect -f '{{.Driver}}|{{.Internal}}|{{.EnableIPv6}}|{{index .Options "com.docker.network.bridge.gateway_mode_ipv4"}}|{{index .Options "com.docker.network.bridge.name"}}|{{range .IPAM.Config}}{{if not (eq (printf "%v" .Gateway) "" "invalid IP")}}present{{end}}{{end}}|{{len .Containers}}' "$network")
test "$settings" = 'bridge|true|false|isolated|br-delvane-uat||0'
addresses=$(ip -4 -o addr show dev br-delvane-uat)
test -z "$addresses"
if ! nft list table inet delvane_uat_preflight >/dev/null 2>&1; then
    nft -c -f tests/uat_preflight_egress.nft
    nft -f tests/uat_preflight_egress.nft
fi
rules=$(nft -s -y -n list table inet delvane_uat_preflight)
test "$(printf '%s\n' "$rules" | tr -d '[:space:]')" = "$(tr -d '[:space:]' <tests/uat_preflight_egress.nft)"

uat_id=$(resolve_image delvane-uat:290b361-local \
    sha256:08b340b1e459d2a8ecedbaa06c1317ef22c9cb2f87412dee0bfe7db07182fe35 \
    sha256:59220537262a50c84cc66be88890a5485d9a7da2f2b5fa91a10e90b8f5171720 "$uat_archive")
pg_id=$(resolve_image postgres:17-bookworm \
    sha256:39d36505873241b90584a61078c0a3af0a226a363854fcc2d722a72ce7a00500 \
    sha256:ab4586ee3c07b4f65cf3daaf55ed008ff619b496bff60e361c30d664bca78401 "$pg_archive")
printf 'Verified installed Delvane image %s\nVerified installed PostgreSQL image %s\n' "$uat_id" "$pg_id"
DELVANE_UAT_KEEP_RUNNING=1 sh tests/run_uat_postgres_smoke.sh "$uat_id" "$pg_id" "$network"
)
```

The harness enforces a read-only application root under UID/GID 10001, a 320 MiB application limit and a 768 MiB PostgreSQL limit. It records live and peak memory, verifies migrations and runtime assets, exercises blocked reporting and authorized redacted evidence, and checks application restart, application crash recovery and restoration into a new database. The retained instance uses restored synthetic data. Its readiness is accessible inside the application container. PostgreSQL's data and backup are in memory, so this is a disposable lab. A host reboot or PostgreSQL container stop ends that run.

**Rollback.** Before removing the isolation policy, remove only the two container IDs printed by the successful run. After confirming the dedicated network is empty, remove that network and its nftables table.

```sh
docker --host unix:///var/run/docker.sock rm -fv <printed-app-id> <printed-postgres-id>
docker --host unix:///var/run/docker.sock network rm delvane-ntak-preflight
nft delete table inet delvane_uat_preflight
```

On harness failure its trap removes the containers it created. If administrator setup failed after applying the rules, keep the scoped table in place while checking no container is attached, then remove any lab bridge created by that attempt and delete only the dedicated table. Do not flush a ruleset. The locally verified archives can be reapplied if another disposable run is needed.

**TLS boundary.** This preflight uses loopback HTTP inside the application container. The Windows operator can use the temporary SSH relay with loopback HTTPS and explicit certificate trust. A remote Xiaomi release would require separate restricted HTTPS access. Live NTAK signing and response security remain gated. No government certificate or private key is required for this preflight. [Windows UAT access procedure](NTAK_UAT_WINDOWS_ACCESS.md)

## First official interoperability test after approval

**Preferred minimum** is a single supported ELO_01A advance booking and its verification poll chain. It exercises request signing, mTLS, response trust and queue correlation without guest identity normalization, closing, other-foreign encoding or intentionally erroneous data. Obtain NTAK confirmation that the assigned test property is allowed to send this case at the approved start date. If NTAK requires AD_01 first, stop at environment preparation until its contract is resolved. Then the first exchange is the authorized information request and correlated poll for that one property. Do not use a guessed date or call a different operation to work around the gate.

1. Have the authorized owner configure only the assigned isolated test property, registration, provider tax and software identity. Start with empty official queues and an approved business calendar/start-date basis. Create one fictional guest booking through the normal PMS workflow, with the reporting configuration eligible for that one case. Use room 101 with STANDARD three regular places, one expected guest, arrival TX+1 and departure TX+2, HUF 20,000 gross, `HU`, `DIREKT_ONLINE`, `UZLETI_EGYENI`, guaranteed and `lemondva=false`. TX is the allowed current calendar date for this run. Keep the reservation's native stable booking ID. Record the test account, room, local ticket/case identifier and booking-to-report mapping. No identity document, VIZA report, intentional error or duplicate is needed. [Validation DOCX, ELO_01A table 4](<validation/PMS_v9_Interfész_Validációs_Tesztfeladatok_v1.07.docx>)
2. Inspect one automatically captured reservation job. The request is UTF-8 SOAP 1.1 document/literal (`text/xml`, WSDL empty SOAPAction), with `foglalasEsemenyRequest` in `http://mtu.gov.hu/ntak/v9`. The body carries `uzenetAdatok` (UUID and send time), `szoftverAdatok`, `szallashely` and `foglalasEsemeny` (booking ID, event and original booking timestamps, dates, classifications and amounts). Before release, validate the embedded XSD, approved WS-Security references and digests, timestamp/freshness, signer and certificate/property binding. Verify that the exact test endpoint, CA and hostname are pinned by configuration and the client supports mTLS. Compare the retained business body/hash to the sole reviewed job. No raw SOAP editing or duplicate submission.
3. In the authorized window, allow dispatch of that single job and its `ellenorzesRequest` polling only. The expected synchronous HTTP 200 response supplies `feldolgozasAzonosito` after receipt. Validate the response under the approved security and schema rules, store and correlate that ID to the PMS UUID and job/version, then poll with the returned ID. `BEFOGADVA` is pending. A correlated, authenticated `TELJESEN_SIKERES` with empty errors and warnings is the goal. Log receipt and final result separately. Use the agreed window and poll schedule. Hold the one-case scope if a warning, rejection or explicit resend instruction arrives. Do not auto-resubmit on timeout or uncertain acceptance. [Interface §§7.1–7.2 pp. 34–39](<v9/ntak-pms-interface-v907-eng-1794401423%20(1).pdf>)
4. Record the approved test window, target, public certificate fingerprint, chain/hostname and signature outcomes, deployed revision, UTC timestamps, booking/job/version linkage, request and response hashes, processing ID, final state and redacted diagnostics. Keep any required raw protocol evidence encrypted in the scoped store and follow the authorized validation submission channel and retention policy. Capture full-screen screenshots of the synthetic action, receipt and final result after checking them for secrets and unrelated records. Finish by closing egress and checking that no other NTAK jobs and no VIZA or production traffic were sent. A single successful exchange establishes interoperability for that case and environment.

**Stop conditions.** Hold the test if any of the following occurs:

- Target, scope, certificate, trust chain, revocation status or clock is unknown or changes.
- Schema, signature, replay or response correlation checks fail. The response is a warning or rejection.
- A documented blocker, unexpected queued job or unexpected network traffic appears.
- Delivery evidence is missing or ambiguous, or the poll is still pending when the approved window closes.

Quarantine the job and preserve the evidence. Ask the operator and NTAK to resolve uncertain acceptance before considering a retry, resend or correction. A receipt remains an intermediate state.

## Local Windows and Xiaomi smoke checklist

The checkpoint built both platforms. Windows opened a responsive release window, and the unsigned Android APK passed static packaging checks. Neither result establishes full manual PMS workflow or physical Android verification. Start the following on a trusted Windows test workstation with Flutter 3.50.0/Dart 3.14.0 and use **only fictional data**.

**Shared backend.** In a separate PowerShell window run the disposable launcher from the checkpoint. Enter a disposable password at the prompt and keep that terminal open. It installs the network, database and credential guards and binds only to loopback. Before signing in, require the workspace marker to report `isolated=true` and `mode=disposable`.

```powershell
Set-Location C:\Delvane\Delvane-Development
.\.venv\Scripts\python.exe -B run_development_workspace.py
```

In another terminal, inspect the marker before launching clients. Use `owner@workspace.invalid` and then `manager@workspace.invalid` or `cleaner@workspace.invalid` for role checks, with the password entered at the prompt.

```powershell
$uatMarker = Invoke-RestMethod 'http://127.0.0.1:8765/api/development/workspace' -TimeoutSec 5 -MaximumRedirection 0
if ($uatMarker.isolated -ne $true -or $uatMarker.mode -ne 'disposable') { throw 'Disposable workspace required' }
$uatMarker | Select-Object isolated, mode, date
Set-Location C:\Delvane\Delvane-Development\apps\delvane_business
powershell -NoProfile -ExecutionPolicy Bypass -File .\tool\build_windows.ps1 -DartDefineFromFile .\config\local.json
```

Launch the new executable from the successful build directory. The standard output is `build\windows\x64\runner\Release\delvane_business.exe`. The VS2026 fallback uses `build\windows-vs2026\x64\runner\Release\delvane_business.exe`. The existing dedicated release smoke bundle points at the earlier temporary port 39847. Use the fresh 8765 build for this walkthrough. Confirm the displayed property and separate test profile before opening its reservations.

**Xiaomi 15 or other authorized physical Android device.** Manually confirm the phone is a test device or managed test profile, enable Developer Options/USB debugging, connect it by USB, unlock it and accept the workstation's debugging prompt. If the package is already installed for another environment or has a signing conflict, stop and use a dedicated test device/profile. Preserve its existing app and data. The debug build uses the local-only USB path. The unsigned release APK cannot be installed for this smoke, and release Android requires a trusted dedicated HTTPS staging origin for later signed-device verification.

```powershell
Set-Location C:\Delvane\Delvane-Development\apps\delvane_business
adb devices
flutter --no-version-check build apk --debug --dart-define-from-file=config/local.json
powershell -NoProfile -ExecutionPolicy Bypass -File .\tool\connect_android.ps1 -Install
```

Require exactly one authorized device or use the helper's `-DeviceId`. Its isolation-marker check and `adb reverse tcp:8765 tcp:8765` forward the phone's loopback to the guarded Windows PMS. Use both clients against the same disposable backend:

1. Sign in as the fictional owner. Open **Integrations → NTAK reporting → Reporting settings** for the synthetic property. Select **Test environment** and use the [guarded test fixture values](../../tests/test_ntak_reporting.py) for the four identity fields. Leave the confirmed start date empty and select **Prepare reporting automatically**. Verify the top of the panel still reports blocked official transmission. Create one fictional future booking with a physical room. From the other client, refresh, confirm the booking and room match, move the booking by one day and read the same reference and revised dates on the first client. Cancel it after observing both versions.
2. In **Apartments and rooms**, refresh a prior business date. Use a prepared synthetic mismatch (one active physical room and aggregate count two for its room type). As owner, open **Correct historical room count**, enter `1` and a fictional reason, save and refresh. Verify the selected date is reconciled and the live selling count is still two. Repeat the view as manager and confirm the edit action is absent. Use normal property/room setup in a disposable fixture if the mismatch is missing.
3. Take the marker's business date as today. On an otherwise idle synthetic property with matching inventory, book one overnight stay from two days ago to yesterday with one guest and one valid physical room. Add a fictional reporting profile and an itemized lodging charge for the first day. In reservation detail, record arrival at 14:00 on the first day and departure at 09:00 the next day, in property time. Verify both events in **Actual stay history**. In **Daily closing and finances → Open daily closing**, set the selected date and first business date to the stay's first day, save the calendar with automatic closing off, confirm operating state, and save a fixed HUF 400 tourism tax rate for that date. Enter a fictional reason and close the day. Verify one local closing version and confirm a repeated close does not add one. With no approved frozen guest identity, expect `identity_normalization_unresolved` in reporting. Leave that gate in place.
4. In that property's **NTAK reporting**, open **Reporting diagnostics** and the evidence export for a prepared job. Provide a fictional audit reason and use **Copy redacted JSON** to check scope, status and redaction. Keep clipboard history off and clear the test clipboard after review. Switch properties and confirm the other queue shows none of those jobs. Confirm the cleaner cannot access reporting management. Confirm VIZA displays disabled official transmission.
5. On the physical device, repeat the key actions in Hungarian and English, including form entry with accents, scrolling and the confirmation dialogs. Rotate or background/restore the app, sign out and verify previous data cannot be reached through Back. Test camera permission only with a synthetic specimen, then verify return to the app. Capture the physical camera/OCR result separately from this NTAK smoke. Record model, OS, build mode, language, result and any failure. Restore the test phone's USB debugging and remove the reverse mapping only if this run added it.

Close both apps and stop the disposable backend with Ctrl+C. Keep redacted screenshots and a pass/fail log outside Git. For later remote device verification, build with `DELVANE_ENV=staging` and the approved PMS HTTPS origin using a reviewed copy of `config/staging.example.json`. The Android release must be separately signed for that device with authorized test signing. Never point a Flutter build at the NTAK SOAP endpoint. [Native environment and USB instructions](../../apps/delvane_business/API_ENVIRONMENTS.md)
