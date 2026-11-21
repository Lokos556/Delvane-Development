# NTAK UAT preparation

Baseline `ntak-offline-rehearsal-checkpoint` → `290b361d3027a457604abbdc0c5e1f35d78e9df2`, migration **3090**. The [27-case matrix](TASK20_READINESS.md#validation-matrix) records 22 offline passes, three partial and two externally blocked. There are zero official results. VIZA V01–V08 and both transmission gates are preserved. This plan authorizes no server action or transmission.

## First three actions

1. **Request the authoritative v9 packet under support ticket 150337.** Ask for a working signed request and its receipt and verification exchange, the complete profile and trust materials, the AD_01 result schema, and confirmation that the proposed first booking test is eligible against the assigned test property. Use the questions below. Send public support information only.
2. **Finish local release checks.** The image and disposable PostgreSQL verification are complete. Use the verified archive and dependency manifest below. Finish the listed Windows release UI and Xiaomi checks on approved test environments. Keep both reporting transports disabled.
3. **Approve a separately scoped Hetzner preflight.** Specify the host, operator, inspection window and permitted read-only metadata checks. Verify isolation, the exact assigned property and public certificate metadata with egress blocked. Installation, local key-match preflight and a later official test each require explicit authorization. A successful server preflight does not authorize a request.

## Work and approvals

| Status | Work |
| --- | --- |
| **Ready now** | Tagged baseline, reviewed local package and digest, embedded WSDL/XSD validation, PostgreSQL migration 3090 and restart check, disabled adapters, encrypted evidence and redacted exports, Windows launch smoke and unsigned Android release package. |
| **Can be prepared locally** | Review deployment and backup/restore procedures. Finish the Windows release UI and Xiaomi checks. After authoritative answers arrive, implement and verify only the approved signer, response security and onboarding contract offline. |
| **Requires explicit server access approval** | Inspect host and isolated runtime metadata. Separately approve deployment, migration of the dedicated UAT database and credential provisioning or key-match checks performed entirely by the service account. Server access approval alone does not authorize government network access. |
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

**Approval boundary.** Obtain the exact Hetzner project and server identity, verified SSH host-key fingerprint, approved management source and SSH account, test window and scope. Read-only host inspection is the first approval. File transfer, Docker image import and temporary lab execution require separate explicit authorization unless expressly included in that approval. A preflight never authorizes an application rollout, access to an existing database or key, a firewall rule change, an official test or outbound government traffic.

### 1. Read-only host inspection after approval

Use a trusted Hetzner console or administrator record to verify the server identity and obtain the SSH host-key fingerprint out of band. Prepare a dedicated known-hosts file for that verified host. Run the following from a trusted POSIX workstation only after setting the variables to the approved values. The host commands display operational metadata only.

```sh
: "${APPROVED_UAT_HOST:?}" "${APPROVED_UAT_SSH_USER:?}" "${VERIFIED_UAT_KNOWN_HOSTS:?}"
test -s "$VERIFIED_UAT_KNOWN_HOSTS"
ssh -o BatchMode=yes -o StrictHostKeyChecking=yes \
    -o "UserKnownHostsFile=$VERIFIED_UAT_KNOWN_HOSTS" \
    "$APPROVED_UAT_SSH_USER@$APPROVED_UAT_HOST" 'sh -s' <<'PREFLIGHT'
set -eu
hostname
uname -m
grep -E '^(ID|VERSION_ID|PRETTY_NAME)=' /etc/os-release
date -u
df -h /
free -m
docker --host unix:///var/run/docker.sock version --format '{{.Server.Version}} {{.Server.Os}}/{{.Server.Arch}}'
docker --host unix:///var/run/docker.sock info --format '{{.DockerRootDir}}'
docker_root=$(docker --host unix:///var/run/docker.sock info --format '{{.DockerRootDir}}')
df -h "$docker_root"
docker --host unix:///var/run/docker.sock ps --format '{{.Names}} {{.Image}} {{.Ports}}'
docker --host unix:///var/run/docker.sock network ls
ss -H -ltn
sudo -n sshd -T | grep -E '^(permitrootlogin|passwordauthentication|kbdinteractiveauthentication|pubkeyauthentication|allowusers|allowgroups) '
PREFLIGHT
```

Accept only a Linux amd64 host with sufficient reviewed headroom for both image imports, two temporary databases and a dump, and a working local Docker socket. Match the host against the approved Hetzner record and verify that its Docker daemon, deployment namespace and data stores are dedicated to UAT. Stop on an identity mismatch, shared production dependencies or an unapproved listener. If SSH uses `Match` rules, have the approved network operator run `sudo -n sshd -T -C user=<approved-user>,addr=<management-source-IP>,host=<source-host>` with real approved values to verify the effective rule. Validate the Hetzner firewall attachment independently in the authorized console. SSH should be restricted to the approved VPN or source allowlist using key authentication, with direct root and password logins disabled. The lab needs **no public listener**, including port 5432. Confirm effective inbound and forwarded rules and no public IPv4 or IPv6 publication for PostgreSQL. Inspect the active rules on the authorized host with `sudo -n nft list ruleset`, or with `sudo -n iptables-save` and `sudo -n ip6tables-save` on installations using those tools. A missing permission or unclear rule is a stop condition.

Before granting write approval, have the firewall operator verify default-deny routed egress for the lab and no reachable host gateway service or proxy that could forward its traffic. Allow only the internal test application to reach its disposable PostgreSQL at TCP 5432. Do not add a route, another network, a published port or a host bind mount for the lab. Review both Docker forwarding and host firewall policy. The lab additionally enforces an IPv4-only internal bridge and zero published ports independently of reporting configuration. This proof requires no DNS or connection attempt to a government host.

### 2. Disposable execution after approval to transfer, import and run

Use a private remote work directory on the verified test host. After write approval, run the following at the trusted workstation from the repository root. `REVIEWED_STAGING_DIR` must name a fresh, private local directory. Transfer only these four files.

```sh
: "${REVIEWED_STAGING_DIR:?}"
remote="$APPROVED_UAT_SSH_USER@$APPROVED_UAT_HOST"
git archive --format=tar ntak-uat-package-checkpoint tests/run_uat_postgres_smoke.sh tests/uat_postgres_smoke.py |
    tar -xf - -C "$REVIEWED_STAGING_DIR"
ssh -o BatchMode=yes -o StrictHostKeyChecking=yes -o "UserKnownHostsFile=$VERIFIED_UAT_KNOWN_HOSTS" \
    "$remote" 'install -d -m 0700 "$HOME/delvane-uat-preflight" "$HOME/delvane-uat-preflight/tests"'
scp -o BatchMode=yes -o StrictHostKeyChecking=yes -o "UserKnownHostsFile=$VERIFIED_UAT_KNOWN_HOSTS" \
    build/ntak-uat/delvane-uat-290b361-local.tar.gz build/ntak-uat/SHA256SUMS "$remote:delvane-uat-preflight/"
scp -o BatchMode=yes -o StrictHostKeyChecking=yes -o "UserKnownHostsFile=$VERIFIED_UAT_KNOWN_HOSTS" \
    "$REVIEWED_STAGING_DIR/tests/run_uat_postgres_smoke.sh" "$REVIEWED_STAGING_DIR/tests/uat_postgres_smoke.py" \
    "$remote:delvane-uat-preflight/tests/"
```

The host must already have the verified Linux amd64 PostgreSQL 17.12 image, or an independently checksum-verified copy approved for local import. The PostgreSQL manifest used locally was `postgres:17-bookworm@sha256:837bed18782820fe967067cb5328b02b0d9992c1be9a37ee0c9c492cfc03af3b`. The tested platform image ID is in the command below. No registry pull is needed within this approved lab window.

```sh
set -eu
umask 077
cd "$HOME/delvane-uat-preflight"
docker_local() { docker --host unix:///var/run/docker.sock "$@"; }
uat_tag=delvane-uat:290b361-local
uat_id=sha256:08b340b1e459d2a8ecedbaa06c1317ef22c9cb2f87412dee0bfe7db07182fe35
pg_id=sha256:39d36505873241b90584a61078c0a3af0a226a363854fcc2d722a72ce7a00500
expected_sum=d991b2e6ea3cd35a181971c80cf1132f7f82aea656a31db6745dba79d84ea732
printf '%s  %s\n' "$expected_sum" delvane-uat-290b361-local.tar.gz | cmp -s - SHA256SUMS
sha256sum -c SHA256SUMS
test "$(docker_local image inspect -f '{{.Id}}' "$pg_id")" = "$pg_id"
if existing=$(docker_local image inspect -f '{{.Id}}' "$uat_tag" 2>/dev/null); then
    test "$existing" = "$uat_id"
else
    docker_local image load -i delvane-uat-290b361-local.tar.gz
fi
test "$(docker_local image inspect -f '{{.Id}}' "$uat_tag")" = "$uat_id"
sh tests/run_uat_postgres_smoke.sh "$uat_id" "$pg_id"
```

The harness uses a fresh Docker CLI config and a local Unix socket. It starts each container on the approved type of internal network, verifies placement and privilege settings, checks the staging metadata and migration 3090, exercises scoped synthetic booking and evidence flows, and proves restart and restore with decryptable blocked evidence. It generates only disposable DB and data-encryption values in memory and never mounts an existing key or adds a credential binding to a real file. The test dump stays in the disposable PostgreSQL container's tmpfs. Record only the package IDs, checklist outcomes, readiness version, local status codes and times. Keep any host logs and review data local and access-controlled. Never dump container environments, request bodies, signed wire content, passwords or tokens. Redacted operator export is the approved general diagnostic surface.

**TLS boundary.** This lab uses loopback HTTP exclusively inside the application container and does not test HTTPS ingress or mTLS. Before any later HTTPS operator check, approve a separate UAT ingress hostname and trusted full chain with hostname verification and TLS 1.2 or later. Use the ingress certificate for that hostname only and keep the app port private. After authorization, check only the approved PMS UAT origin with `openssl s_client -connect "$APPROVED_UAT_DNS:443" -servername "$APPROVED_UAT_DNS" -verify_hostname "$APPROVED_UAT_DNS" -verify_return_error -min_protocol TLSv1.2 </dev/null` and `curl --fail --silent --show-error --proto '=https' --tlsv1.2 --max-time 5 "https://$APPROVED_UAT_DNS/api/client/environment"`. Require the expected staging deployment ID and secure cookies. Do not substitute the government hostname or a production ingress. No government client certificate is required for this preflight.

**Rollback.** The first lab has its own names, tmpfs database and backup, and no shared volumes or routes. Its exit cleanup removes only objects it created by ID. The archived candidate may remain after approved import without running services. No pre-existing application or database state is replaced. For a separately approved persistent UAT rollout later, record the previous image ID and private service manifest first, pause its writer and take a verified synthetic DB snapshot with its encryption key available from the approved secret store. On failure, keep egress closed, stop only the candidate, restore the snapshot into a new isolated database under the UAT role, and restart the previous pinned image/config against that restored copy. Require the prior schema/readiness, sample records, readable evidence and disabled gates before resuming use. Preserve the failed candidate database for review. Never restore over the active service or replay unresolved queue entries. The disposable restore drill checks the mechanics and does not certify an existing server's rollback.

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
