# Guest check-in UAT at guest.delvane.app

The first public trial uses fictional guests and the existing single-use check-in links. Cloudflare terminates public HTTPS and forwards to a private Unix socket. A dedicated Nginx instance in the application container's network namespace checks the exact host, HTTPS scheme, HTTP method and request path before forwarding to the app's loopback. The application independently restricts routes on the guest host. Owner and admin routes, both government integrations, health, docs, and email webhooks return 404 at the guest origin. The Windows operator continues to use the separate SSH path.

The guest hostname serves only the current token page, its four assets, and the token read and submit API. Responses are marked `no-store` and `no-referrer`. The proxy strips cookies and authorization headers, bounds form bodies at 64 KiB and keeps URL and body logs disabled. Manual guest entry is available on the public hostname. Browser OCR still needs same-origin assets and device verification. Guest email remains disabled, so create and share test links manually from the operator app. Resend keys and signing secrets are outside this deployment.

## Reviewed local files

The application archive was built offline from source `4bdff53` plus the current working-tree implementation. Both dependency files match the reviewed UAT base image. The Linux amd64 archive was checked for its Docker configuration and OCI manifest digests. It contains the migration-3091 application and no environment files, keys or databases.

| Local file in `build/guest-uat` | SHA-256 |
| --- | --- |
| `delvane-guest-3091-local.tar.gz` | `cb8d8a885cc41fe2752424598256793a8a150a2b2add1676c0b0d47ddb744250` |
| `delvane-guest-uat-storage-controls-v2.tar.gz` | `7c2ffe8b89cc288fe4801c2567c6170bdb30f44f4204cf46034b219220dba530` |
| `IMAGE-RECORD.json` | `b2eb76cefa5b17ef8a1e50d0332d8ae04073b869034051ff0e78db72aed39df6` |

The image passed the Pilot guest journey on disposable PostgreSQL 17.12 through an app restart. The storage revision migrates the clone on a separate disk-backed PostgreSQL volume. See the [storage recovery runbook](GUEST_UAT_STORAGE.md) for the backup, preflight, verification and rollback instructions. The real Nginx configuration passed the local socket smoke with 21 denied route and method cases and a successful guest form POST to a synthetic origin. Connector firewall syntax and 22 backend guest-delivery and check-in regressions passed. The actual Cloudflare connector, public TLS and guest-host routing await the authorized live preflight.

## Publish only after approval

### Docker connector for the existing tunnel

For `delvane-guest-uat` (tunnel `94dab672-b04b-4fcb-83d6-ee8e1c3bdca7`), the staged Docker procedure below uses the already reviewed application and controls. The official Linux amd64 connector is pinned at cloudflared 2026.11.1. Its archive, also verified locally, is `cloudflared-2026.11.1-linux-amd64.tar.gz`, SHA-256 `c28ea5d1302e42417865d57f63f9c3279ed2d4984e1a425ce89489b4c9de3fa3`. The Docker procedure uses a dedicated connector UID, disables container logs, and mounts only the exact private socket and token read-only. It uses the existing connector-specific firewall, with local responses on the loopback-only readiness port allowed. No app or database container has an external route. [Cloudflare's Docker guidance](https://developers.cloudflare.com/tunnel/guides/update-cloudflared/)

1. From Windows, stage the prepared files over the pinned Git SSH connection with `deploy/guest-uat/stage-files.ps1`. The private staging path is `/home/delvane-uat/delvane-guest-storage-3091`. The script verifies remote hashes and sets private permissions. The stage contains no tunnel token or email key.
2. From the Hetzner root console, copy the entry point and verify its SHA-256 using the local `STORAGE-STAGE-SHA256SUMS-v2` before running it.

   ```sh
   install -m 0700 /home/delvane-uat/delvane-guest-storage-3091/deploy-private-storage-v2.sh /root/delvane-guest-deploy-storage.sh
   sha256sum /root/delvane-guest-deploy-storage.sh
   bash /root/delvane-guest-deploy-storage.sh --backup-only
   ```

   After the online backup is confirmed and cutover is approved, close the Windows relay if active and run `bash /root/delvane-guest-deploy-storage.sh`. The script checks storage before cutover, clones the synthetic database to a new disk-backed volume, starts the isolated migration-3091 app and checks the private socket. The Cloudflare connector is still stopped. Retain the same private operator access by restarting the Windows relay with the approved image ID.

   ```sh
   cd /root/delvane-guest-uat-3091
   bash tests/run_uat_windows_relay.sh "$(cat app-image-id)"
   ```

3. After private origin checks have passed, confirm that the existing Cloudflare tunnel has no published applications or private routes. From the Hetzner root console, run `bash /root/delvane-guest-uat-3091/start-docker-connector.sh`. Enter `EMPTY` to confirm the route check and enter the token only at the masked prompt. The script checks the token's tunnel ID locally, stores it with private permissions, and starts the container, then checks loopback readiness. Leave **Routes → Add route** untouched until separate publication approval.
4. To stop just the Docker connector, remove container `delvane-guest-tunnel` from the root console, then remove its scoped table with `nft delete table inet delvane_guest_connector`. Keep the original UAT isolation table in place. Remove the private token file from `/etc/delvane-guest-uat` when it is no longer needed. If the origin socket is recreated, restart the connector with a new bind mount. The private origin runs under `delvane-guest-origin.service`; stop that unit before changing the app container. Application rollback uses the procedure below.

### 1. Prepare the origin on Hetzner

Stage the checked archive and controls over the existing pinned SSH channel. In the root console on `delvane-test-01`, work from a root-owned staging directory and verify the archive and controls against the recorded SHA-256 values before extraction or loading. Use the existing [UAT runbook](../ntak/NTAK_UAT_PREPARATION.md) for archive verification and console identity. Leave the existing Docker network, firewall table, PostgreSQL container and listening ports in place.

```sh
# In the root-owned directory containing the four staged files.
sha256sum -c STORAGE-STAGE-SHA256SUMS-v2 || exit 1
tar -xzf delvane-guest-uat-storage-controls-v2.tar.gz || exit 1
docker --host unix:///var/run/docker.sock load -i delvane-guest-3091-local.tar.gz || exit 1
VERIFIED_IMAGE_ID=$(docker --host unix:///var/run/docker.sock image inspect -f '{{.Id}}' delvane-uat:guest-3091-local) || exit 1
case "$VERIFIED_IMAGE_ID" in
    sha256:83e46c173f98a144cf985858ad24f423966fcf2adadc550a7adddfff885a7654|sha256:302152b806711f90da59e67cbda43c352ff92a0154f34fba09bcf16c73bcddbb) ;;
    *) printf '%s\n' 'Unexpected installed image ID. Stop.' >&2; exit 1 ;;
esac
```

Install a supported Cloudflare package and Nginx binary using the approved package sources. Check that the ordinary Nginx service is absent or inactive. On a host where Nginx is being installed for the first time, mask its default unit before package installation so the package cannot open its ordinary port 80 listener. Use the dedicated config and connector unit below. Cloudflared must support `--token-file`. Check that the host's trusted DNS stub listens on `127.0.0.53:53`; if it does not, adapt and re-verify the connector-only rule for the actual trusted resolver. [Cloudflared run parameters](https://developers.cloudflare.com/tunnel/reference/run-parameters/)

From the verified, extracted root staging directory, use these commands after approval. Here `VERIFIED_IMAGE_ID` is the full installed ID checked against the verified archive as described below.

```sh
test "$(hostname -s)" = delvane-test-01 && test "$(id -u)" -eq 0 || exit 1
test -x /usr/sbin/nginx && test -x /usr/bin/cloudflared || exit 1
getent passwd delvane-guest-tunnel >/dev/null ||
    useradd --system --user-group --shell /usr/sbin/nologin delvane-guest-tunnel || exit 1
install -d -o root -g root -m 0700 /etc/delvane-guest-uat || exit 1
install -m 0600 deploy/guest-uat/nginx.conf deploy/guest-uat/connector-egress.nft /etc/delvane-guest-uat/ || exit 1
install -m 0644 deploy/guest-uat/delvane-guest-egress.service deploy/guest-uat/delvane-guest-tunnel.service /etc/systemd/system/ || exit 1
nft -c -f /etc/delvane-guest-uat/connector-egress.nft || exit 1
systemctl daemon-reload || exit 1
python3 -B deploy/guest-uat/upgrade-app.py "$VERIFIED_IMAGE_ID" || exit 1
bash deploy/guest-uat/run-origin.sh "$VERIFIED_IMAGE_ID"
```

Close the old Windows relay before the upgrade. The upgrade script recognizes the original restored UAT app and checks storage before making workload changes. It prepares a separate PostgreSQL server on the isolated bridge with a disk-backed named volume. After stopping only the original app, it takes a fresh private host-disk snapshot and verifies restore into the new server. It starts the new read-only app on container loopback with `DELVANE_GUEST_PUBLIC_ORIGIN=https://guest.delvane.app` and `DELVANE_GUEST_EMAIL_ENABLED=0`. It requires readiness on migration 3091 and retains the original app and original PostgreSQL for rollback. For operator access after the upgrade, restart the [Windows relay](../ntak/NTAK_UAT_WINDOWS_ACCESS.md) with the updated reviewed `tests/run_uat_windows_relay.sh` and pass the same verified full image ID as its first argument.

Keep the origin root console open. Before starting Cloudflare, use a second root console to check the private socket and prove that an allowed static route works while operator, government, and webhook routes are blocked.

```sh
for path in /static/guest-checkin.css /api/login /api/reservations /api/government/ntak /api/government/viza /health/ready /docs; do
    curl --unix-socket /run/delvane-guest-uat/origin.sock -sS -o /dev/null \
        -w "%{http_code} $path\n" -H 'X-Forwarded-Proto: https' "http://guest.delvane.app$path"
done
curl --unix-socket /run/delvane-guest-uat/origin.sock -sS -o /dev/null -w "%{http_code}\n" \
    -X POST -H 'X-Forwarded-Proto: https' \
    http://guest.delvane.app/api/public/guest-delivery/resend-webhook
```

Expect 200 for the static asset and 404 for every other probe. Stop if the app has a public port, a default route, enabled government transmission, or a public response for a private route.

### 2. Exact Cloudflare dashboard actions

1. Confirm `delvane.app` is active in the Cloudflare account and that the zone's edge certificate covers `guest.delvane.app`. Go to **Networking → Tunnels → Create Tunnel**. Name it `delvane-guest-uat` and choose **Create Tunnel**. Select the Linux setup option and copy the connector token privately. Use the prepared systemd service instead of the dashboard's token-on-command-line installer. [Cloudflare tunnel setup](https://developers.cloudflare.com/tunnel/get-started/)
2. In a separate root console, store the token without displaying it and start the connector. The connector is limited to the documented Cloudflare edge IPv4 addresses on TCP 7844 and the local resolver. The app and database keep their pre-existing egress block. Ports 80 and 443 stay closed on Hetzner. [Cloudflare firewall requirements](https://developers.cloudflare.com/tunnel/configuration/#firewall-rules)

   ```bash
   umask 077
   read -rsp 'Paste the Cloudflare connector token: ' delvaneTunnelToken
   printf '\n'
   if [[ -n $delvaneTunnelToken ]]; then
       printf '%s\n' "$delvaneTunnelToken" > /etc/delvane-guest-uat/tunnel.token
       unset delvaneTunnelToken
       systemctl start delvane-guest-tunnel.service
   fi
   ```

3. In the `delvane.app` zone, open **Caching → Cache Rules → Create rule**. Match the custom expression `http.host eq "guest.delvane.app"` and set **Cache eligibility → Bypass cache**. Keep the rule scoped to this hostname. Check that Workers, browser analytics scripts, URL rewrites, or request logging rules do not capture or alter the guest URLs or form data. [Create a cache rule](https://developers.cloudflare.com/cache/how-to/cache-rules/create-dashboard/)
4. Wait for **Healthy** under **Networking → Tunnels**. Select `delvane-guest-uat` → **Routes → Add route → Published application**. Set **Subdomain** to `guest`, **Domain** to `delvane.app` and leave **Path** empty. Set **Service URL** to `unix:/run/delvane-guest-uat/origin.sock` (if the UI splits out the service type, select **UNIX** and enter `/run/delvane-guest-uat/origin.sock`). Under **Additional application settings → HTTP Settings → HTTP Host Header**, enter `guest.delvane.app`. Leave **Protect with Access** off for guest use. Select **Add route** only once the origin checks pass. **This click creates the DNS record.** Use no wildcard, SSH or private network route on this tunnel. [Supported services and DNS](https://developers.cloudflare.com/tunnel/concepts/routing/) · [Host header setting](https://developers.cloudflare.com/tunnel/reference/origin-parameters/#httphostheader)
5. From another network, repeat the status-only checks over `https://guest.delvane.app`. Check that HTTP requests cannot serve guest data. If you want redirects, use an explicitly guest-host-only HTTPS redirect rule. Use one fictional future reservation and one pre-check-in link generated in the Windows app. Verify manual submission, single use and cancellation on a separate fictional booking. Keep bearer links and URL paths out of console output, issue reports and screenshots. Review cloud-side settings before any test using identity data other than fictional data.

### Rollback

Stop the connector and private origin before rolling back the app. If the hostname was later published, remove only that published application route and any remaining `guest` DNS record. Leave the original UAT firewall table and Docker bridge in place. Use the [storage rollback steps](GUEST_UAT_STORAGE.md) to return to the original app while retaining the durable volume and snapshots. If the application restarts or is replaced, rerun the origin script against the verified current container before opening the connector again.
