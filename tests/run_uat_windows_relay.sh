#!/usr/bin/env bash
# Run from the delvane-test-01 root console. Ctrl+C stops the temporary access.
set -euo pipefail
umask 077
[[ $(id -u) == 0 && $(hostname -s) == delvane-test-01 ]]
unset DOCKER_HOST DOCKER_CONTEXT
docker_local() { docker --host unix:///var/run/docker.sock "$@"; }

network=delvane-ntak-preflight
settings=$(docker_local network inspect -f '{{.Id}}|{{.Driver}}|{{.Internal}}|{{.EnableIPv6}}|{{index .Options "com.docker.network.bridge.gateway_mode_ipv4"}}|{{index .Options "com.docker.network.bridge.name"}}|{{range .IPAM.Config}}{{if not (eq (printf "%v" .Gateway) "" "invalid IP")}}present{{end}}{{end}}|{{len .Containers}}' "$network")
network_id=${settings%%|*}
[[ $settings == "$network_id|bridge|true|false|isolated|br-delvane-uat||2" ||
   $settings == "$network_id|bridge|true|false|isolated|br-delvane-uat||3" ]]
[[ -z $(ip -4 -o addr show dev br-delvane-uat) ]]
policy=/root/delvane-uat-preflight/tests/uat_preflight_egress.nft
rules=$(nft -s -y -n list table inet delvane_uat_preflight)
[[ $(printf '%s\n' "$rules" | tr -d '[:space:]') == "$(tr -d '[:space:]' <"$policy")" ]]

peers=$(docker_local network inspect -f '{{range $id, $peer := .Containers}}{{printf "%s %s\n" $id $peer.Name}}{{end}}' "$network")
app=$(awk '$2 ~ /^delvane-uat-[a-f0-9]{12}-restored$/ {print $1}' <<<"$peers")
name=$(awk -v id="$app" '$1 == id {print $2}' <<<"$peers")
pg_name=${name%-restored}-pg
pg=$(awk -v name="$pg_name" '$2 == name {print $1}' <<<"$peers")
[[ $app =~ ^[a-f0-9]{64}$ ]]
installed_image=$(docker_local inspect -f '{{.Image}}' "$app")
if [[ -n ${1-} ]]; then
    [[ $1 =~ ^sha256:[a-f0-9]{64}$ && $installed_image == "$1" ]]
else
    case $installed_image in
        sha256:08b340b1e459d2a8ecedbaa06c1317ef22c9cb2f87412dee0bfe7db07182fe35|sha256:59220537262a50c84cc66be88890a5485d9a7da2f2b5fa91a10e90b8f5171720) ;;
        *) echo 'Unexpected Delvane image.' >&2; exit 1 ;;
    esac
fi
containers=("$app")
if [[ -n $pg ]]; then
    [[ $pg =~ ^[a-f0-9]{64}$ ]]
    containers+=("$pg")
fi
db_host=isolated-pg
durable=$(awk -v name="$pg_name-durable" '$2 == name {print $1}' <<<"$peers")
if [[ -n $durable ]]; then
    [[ -n ${1-} && $durable =~ ^[a-f0-9]{64}$ ]]
    [[ $(docker_local inspect -f '{{range .Mounts}}{{if eq .Destination "/var/lib/postgresql/data"}}{{.Type}}{{end}}{{end}}' "$durable") == volume ]]
    containers+=("$durable")
    db_host=guest-pg
fi
[[ $settings == "$network_id|bridge|true|false|isolated|br-delvane-uat||${#containers[@]}" ]]
for container in "${containers[@]}"; do
    info=$(docker_local inspect -f '{{.State.Running}}|{{len .HostConfig.PortBindings}}|{{.HostConfig.PublishAllPorts}}|{{.HostConfig.Privileged}}|{{range .NetworkSettings.Networks}}{{.NetworkID}}|{{end}}' "$container")
    [[ $info == "true|0|false|false|$network_id|" ]]
done
[[ $(docker_local inspect -f '{{.HostConfig.ReadonlyRootfs}}|{{.Config.User}}' "$app") == 'true|10001:10001' ]]
pid=$(docker_local inspect -f '{{.State.Pid}}' "$app")
[[ $pid =~ ^[1-9][0-9]*$ && $(readlink "/proc/$pid/ns/net") != "$(readlink /proc/self/ns/net)" ]]

account_code=$(cat <<'PY'
import os
import sys
from urllib.parse import urlsplit
from urllib.request import urlopen
import json
import app

def require(condition):
    if not condition:
        raise SystemExit("Unexpected UAT workspace or operator identity.")

environment = json.load(urlopen("http://127.0.0.1:8080/api/client/environment", timeout=3))
require(environment["environment"] == "staging" and environment["secure_cookies"] is True)
require(environment["deployment_id"].startswith("delvane-uat-"))
require(app.APP_ENV == "production" and app.DB_BACKEND == "postgresql")
url = urlsplit(os.environ["ROSA_DATABASE_URL"])
require(url.hostname == sys.argv[2] and url.username == "delvane_uat"
        and url.path.startswith("/delvane_uat_") and url.path.endswith("_restored"))
user = "owner_uat_windows"
email = "owner-windows@uat.invalid"
org = "org_uat_a"
with app.db() as con:
    require({row["id"] for row in con.execute("SELECT id FROM organizations")}
            == {"org_uat_a", "org_uat_b"})
    require(con.execute("SELECT 1 FROM properties WHERE id='prop_uat_a' AND organization_id=?", (org,)).fetchone())
    existing = con.execute("SELECT id, organization_id, email, role FROM users WHERE id=? OR email=?", (user, email)).fetchall()
    require(not existing or len(existing) == 1 and dict(existing[0]) ==
            {"id": user, "organization_id": org, "email": email, "role": "owner"})
    if sys.argv[1] == "enable":
        password = sys.stdin.readline().rstrip("\n")
        require(12 <= len(password) <= 128)
        con.execute("""INSERT INTO users (id, organization_id, full_name, email, password_hash, role, active)
                       VALUES (?, ?, 'Fictional Windows UAT operator', ?, ?, 'owner', 1)
                       ON CONFLICT (id) DO UPDATE SET password_hash=excluded.password_hash, active=1""",
                    (user, org, email, app.hash_password(password)))
    else:
        con.execute("UPDATE users SET active=0 WHERE id=? AND organization_id=?", (user, org))
    con.execute("UPDATE secure_sessions SET revoked_at=? WHERE user_id=? AND organization_id=? AND revoked_at IS NULL",
                (app.now_iso(), user, org))
    app.audit_event(con, org, "uat.windows_operator." + sys.argv[1], "Synthetic Windows UAT operator access.",
                    actor_type="system", entity_type="user", entity_id=user)
PY
)

uid=$(id -u delvane-uat)
gid=$(id -g delvane-uat)
[[ $uid != 0 && $gid != 0 ]]
access=/run/delvane-uat-access
mkdir -m 0711 "$access"
relay_pid=
account_enabled=
cleanup() {
    if [[ -n $relay_pid ]]; then
        kill "$relay_pid" 2>/dev/null || true
        wait "$relay_pid" 2>/dev/null || true
    fi
    rm -f -- "$access/https.sock" "$access/cert.pem" "$access/key.pem"
    rmdir -- "$access"
    if [[ -n $account_enabled ]]; then
        docker_local exec "$app" python -c "$account_code" disable "$db_host" ||
            echo 'The synthetic account could not be disabled. Review before opening a new relay.' >&2
    fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

read -rs -p 'Choose a disposable password for owner-windows@uat.invalid (12–128 characters): ' password
printf '\n'
[[ ${#password} -ge 12 && ${#password} -le 128 ]]
printf '%s\n' "$password" | docker_local exec -i "$app" python -c "$account_code" enable "$db_host"
unset password
account_enabled=1

openssl req -x509 -newkey rsa:2048 -nodes -days 1 -sha256 \
    -subj /CN=Delvane-UAT-Loopback -addext subjectAltName=IP:127.0.0.1 \
    -addext basicConstraints=critical,CA:FALSE -addext extendedKeyUsage=serverAuth \
    -keyout "$access/key.pem" -out "$access/cert.pem" >/dev/null 2>&1
chmod 0600 "$access/key.pem"
chmod 0644 "$access/cert.pem"

nsenter --target "$pid" --net -- python3 -I - "$access" "$uid" "$gid" <<'PY' &
import asyncio
from contextlib import suppress
import os
import socket
import ssl
import sys

directory, uid, gid = sys.argv[1:]
context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
context.minimum_version = ssl.TLSVersion.TLSv1_2
context.load_cert_chain(directory + "/cert.pem", directory + "/key.pem")
listener = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
path = directory + "/https.sock"
listener.bind(path)
os.chmod(path, 0o600)
os.chown(path, int(uid), int(gid))
os.setgroups([])
os.setgid(int(gid))
os.setuid(int(uid))
active = 0


async def copy(source, target):
    while chunk := await source.read(65536):
        target.write(chunk)
        await target.drain()


async def handle(reader, writer):
    global active
    if active >= 16:
        writer.close()
        return
    active += 1
    upstream_writer = None
    tasks = []
    try:
        async with asyncio.timeout(120):
            upstream_reader, upstream_writer = await asyncio.open_connection("127.0.0.1", 8080)
            tasks = [asyncio.create_task(copy(reader, upstream_writer)),
                     asyncio.create_task(copy(upstream_reader, writer))]
            await asyncio.wait(tasks, return_when=asyncio.FIRST_COMPLETED)
    except (OSError, TimeoutError):
        pass
    finally:
        for task in tasks:
            task.cancel()
        await asyncio.gather(*tasks, return_exceptions=True)
        if upstream_writer is not None:
            upstream_writer.close()
        with suppress(OSError):
            writer.close()
        active -= 1


async def serve():
    server = await asyncio.start_unix_server(
        handle, sock=listener, ssl=context, ssl_handshake_timeout=5, backlog=16,
    )
    print("Delvane UAT relay is ready. Ctrl+C closes it. Automatic stop in four hours.", flush=True)
    async with server:
        await asyncio.sleep(4 * 60 * 60)


asyncio.run(serve())
PY
relay_pid=$!
wait "$relay_pid"
