#!/bin/sh
# Linux only. Pass a verified, empty preflight bridge as argument 3 on Hetzner.
# Without argument 3, provision a temporary bridge for a local rehearsal.
set -eu
umask 077
cd "$(dirname "$0")"
image=${1:-delvane-uat:local}
postgres=${2:-postgres:17-bookworm}
network=${3:-}
keep=${DELVANE_UAT_KEEP_RUNNING:-0}
created_network=
unset DOCKER_CONTEXT DOCKER_HOST
docker_config=$(mktemp -d)
containers=

docker_local() {
    docker --config "$docker_config" --host unix:///var/run/docker.sock "$@"
}

cleanup() {
    status=$?
    for container in $containers; do
        docker_local container rm --force --volumes "$container" >/dev/null || status=1
    done
    if [ -n "$created_network" ]; then
        docker_local network rm "$created_network" >/dev/null || status=1
    fi
    rmdir "$docker_config" || status=1
    exit "$status"
}
trap cleanup EXIT
trap 'exit 1' INT TERM

random_hex() {
    od -An -N24 -tx1 /dev/urandom | tr -d ' \n'
}

image=$(docker_local image inspect -f '{{.Id}}' "$image")
postgres=$(docker_local image inspect -f '{{.Id}}' "$postgres")
suffix=$(random_hex | cut -c1-12)
run_name=delvane-uat-$suffix
case $keep in
    0) ;;
    1) [ -n "$network" ] || { echo 'Keeping the lab requires a dedicated preflight bridge.' >&2; exit 1; } ;;
    *) echo 'DELVANE_UAT_KEEP_RUNNING must be 0 or 1.' >&2; exit 1 ;;
esac
if [ -z "$network" ]; then
    created_network=$(docker_local network create --internal --ipv6=false \
        --opt com.docker.network.bridge.gateway_mode_ipv4=isolated \
        --opt com.docker.network.bridge.name="br-uat-$(printf %.8s "$suffix")" "$run_name")
    network=$created_network
fi
network=$(docker_local network inspect -f '{{.Id}}' "$network")
network_name=$(docker_local network inspect -f '{{.Name}}' "$network")
bridge=$(docker_local network inspect -f '{{index .Options "com.docker.network.bridge.name"}}' "$network")

check_host_guard() {
    if [ -z "$created_network" ]; then
        [ "$network_name|$bridge" = 'delvane-ntak-preflight|br-delvane-uat' ] ||
            { echo 'Expected the dedicated delvane-ntak-preflight bridge.' >&2; exit 1; }
        rules=$(nft -s -y -n list table inet delvane_uat_preflight) ||
            { echo 'Cannot verify the host-level UAT egress policy.' >&2; exit 1; }
        [ "$(printf '%s\n' "$rules" | tr -d '[:space:]')" = "$(tr -d '[:space:]' <uat_preflight_egress.nft)" ] ||
            { echo 'Host-level UAT egress policy differs from the reviewed rules.' >&2; exit 1; }
    fi
}

check_network() {
    # Docker versions may render an unset gateway as empty or "invalid IP".
    settings=$(docker_local network inspect -f '{{.Internal}}|{{.EnableIPv6}}|{{.Driver}}|{{.Scope}}|{{index .Options "com.docker.network.bridge.gateway_mode_ipv4"}}|{{range .IPAM.Config}}{{if not (eq (printf "%v" .Gateway) "" "invalid IP")}}present{{end}}{{end}}' "$network")
    if [ "$settings" != 'true|false|bridge|local|isolated|' ]; then
        echo "Unexpected UAT Docker network settings: $settings" >&2
        exit 1
    fi
    addresses=$(ip -o addr show dev "$bridge")
    if printf '%s\n' "$addresses" | grep -Eq ' inet | inet6 .* scope global'; then
        echo 'UAT bridge has a host-facing address.' >&2
        exit 1
    fi
    peers=$(docker_local network inspect -f '{{range $id, $_ := .Containers}}{{$id}} {{end}}' "$network")
    [ "$peers" = "${1-}" ] || { echo 'Unexpected peer on the UAT bridge.' >&2; exit 1; }
    check_host_guard
}

check_network
host_ipv4=$(ip -4 -o addr show | awk '$2 != "lo" { split($4, a, "/"); print a[1] }')
pg=$run_name-pg
app=$run_name-app
restored_app=$run_name-restored
db=delvane_uat_$suffix
restore_db=${db}_restored

check_container() {
    settings=$(docker_local inspect -f '{{.HostConfig.NetworkMode}}|{{len .HostConfig.PortBindings}}|{{.HostConfig.PublishAllPorts}}|{{.HostConfig.Privileged}}|{{range .Mounts}}{{if ne .Type "tmpfs"}}{{.Type}}{{end}}{{end}}|{{range .HostConfig.Dns}}{{.}}{{end}}|{{index .HostConfig.Sysctls "net.ipv6.conf.all.disable_ipv6"}}|{{index .HostConfig.Sysctls "net.ipv6.conf.default.disable_ipv6"}}|{{.HostConfig.Memory}}|{{.HostConfig.MemorySwap}}' "$1")
    expected="$network|0|false|false||127.0.0.1|1|1|$2"
    case $settings in
        "$expected|$2") ;;
        "$expected|-1")
            [ "$(wc -l </proc/swaps)" -eq 1 ] ||
                { echo 'The host has active swap and Docker did not enforce a swap limit.' >&2; exit 1; } ;;
        *) echo "Unexpected UAT container settings: $settings" >&2; exit 1 ;;
    esac
    attachments=$(docker_local inspect -f '{{range $name, $endpoint := .NetworkSettings.Networks}}{{$name}}|{{$endpoint.NetworkID}}|{{end}}' "$1")
    case "$3|$attachments" in
        "created|$network_name||"|"created|$network||"|"running|$network_name|$network|") ;;
        *) echo "Unexpected UAT container network attachment: $attachments" >&2; exit 1 ;;
    esac
}

create_isolated() {
    memory=$1
    shift
    docker_local create --pull=never --network "$network" --dns 127.0.0.1 \
        --dns-option timeout:1 --dns-option attempts:1 \
        --sysctl net.ipv6.conf.all.disable_ipv6=1 --sysctl net.ipv6.conf.default.disable_ipv6=1 \
        --security-opt no-new-privileges --pids-limit 128 \
        --memory "$memory" --memory-swap "$memory" "$@"
}

POSTGRES_PASSWORD=$(random_hex)
UAT_ROLE_PASSWORD=$(random_hex)
export POSTGRES_PASSWORD UAT_ROLE_PASSWORD
pg_id=$(create_isolated 768m --name "$pg" --network-alias isolated-pg \
    --tmpfs /var/lib/postgresql/data:rw,noexec,nosuid,size=256m \
    --tmpfs /tmp:rw,noexec,nosuid,size=64m -e POSTGRES_PASSWORD "$postgres" \
    -c max_connections=20 -c shared_buffers=64MB)
containers="$containers $pg_id"
check_container "$pg_id" 805306368 created
check_network
docker_local start "$pg_id" >/dev/null
check_container "$pg_id" 805306368 running
check_network "$pg_id "
pg_address=$(docker_local inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$pg_id")
for attempt in $(seq 1 45); do
    if docker_local exec "$pg" pg_isready -h 127.0.0.1 -U postgres -q; then break; fi
    sleep 1
done
docker_local exec -i -e UAT_ROLE_PASSWORD "$pg" psql -q -v ON_ERROR_STOP=1 -v db="$db" -U postgres <<'SQL'
\getenv app_password UAT_ROLE_PASSWORD
CREATE ROLE delvane_uat LOGIN PASSWORD :'app_password' NOSUPERUSER NOCREATEDB NOCREATEROLE;
CREATE DATABASE :"db" OWNER delvane_uat;
REVOKE CONNECT ON DATABASE postgres FROM PUBLIC;
REVOKE CONNECT ON DATABASE template1 FROM PUBLIC;
SQL

# Fernet uses 32 random bytes encoded as URL-safe Base64. Keep the value off
# container stdout and out of the Docker logs.
ROSA_ENCRYPTION_KEY=$(head -c 32 /dev/urandom | base64 | tr '+/' '\055_')
[ "${#ROSA_ENCRYPTION_KEY}" -eq 44 ]
export ROSA_ENCRYPTION_KEY

# Run the network checks in the app's own namespace before importing the app.
# Re-run them on every container restart, including the restored instance.
check_and_start=$(cat <<'PY'
import errno
import os
from pathlib import Path
import socket
import sys

assert not any(name.lower().endswith("_proxy") for name in os.environ), "Proxy environment present"
assert Path("/proc/sys/net/ipv6/conf/all/disable_ipv6").read_text().strip() == "1"
assert not Path("/proc/net/if_inet6").read_text().strip(), "IPv6 addresses present"
routes = [line.split() for line in Path("/proc/net/route").read_text().splitlines()[1:]]
assert all(route[1] != "00000000" and route[2] == "00000000" for route in routes), "External route present"
nameservers = [line.split()[1] for line in Path("/etc/resolv.conf").read_text().splitlines()
               if line.startswith("nameserver ")]
assert nameservers == ["127.0.0.11"], "Unexpected resolver"

# UDP connect checks the kernel route without sending a request or datagram.
ipv4_destinations = ["192.0.2.1", *sys.argv[2].split()]
destinations = [(socket.AF_INET, address) for address in ipv4_destinations]
destinations.append((socket.AF_INET6, "2001:db8::1"))
for family, address in destinations:
    try:
        with socket.socket(family, socket.SOCK_DGRAM) as probe:
            probe.connect((address, 443))
    except OSError as exc:
        if exc.errno not in {errno.ENETUNREACH, errno.EHOSTUNREACH, errno.EAFNOSUPPORT, errno.EADDRNOTAVAIL}:
            raise
    else:
        raise SystemExit(f"Unexpected route to {address}")

database_address = socket.gethostbyname("isolated-pg")
assert database_address == sys.argv[1], "Unexpected destination for PostgreSQL"
with socket.create_connection((database_address, 5432), timeout=5):
    pass
try:
    socket.gethostbyname("example.com.")
except socket.gaierror as exc:
    if exc.errno not in {socket.EAI_AGAIN, socket.EAI_NONAME}:
        raise
else:
    raise SystemExit("Unexpected external DNS resolution")
print("Container isolation and internal PostgreSQL connectivity verified.", flush=True)
os.execvp("uvicorn", ["uvicorn", "app:app", "--host", "127.0.0.1", "--port", "8080", "--proxy-headers"])
PY
)

start_app() {
    check_network "$pg_id "
    ROSA_DATABASE_URL="postgresql://delvane_uat:$UAT_ROLE_PASSWORD@isolated-pg:5432/$2?connect_timeout=3"
    export ROSA_DATABASE_URL
    app_id=$(create_isolated 320m --name "$1" --read-only --cap-drop ALL --entrypoint python \
        --tmpfs /tmp:rw,noexec,nosuid,size=32m \
        --tmpfs /var/lib/delvane:rw,noexec,nosuid,size=32m,uid=10001,gid=10001 \
        -e ROSA_APP_ENV=production -e ROSA_DEPLOYMENT_ENVIRONMENT=staging -e ROSA_DEPLOYMENT_ID="$run_name" \
        -e ROSA_SECURE_COOKIES=1 -e ROSA_DEMO_MODE=0 -e ROSA_AI_PROVIDER=local -e ROSA_ENCRYPTION_KEY -e ROSA_DATABASE_URL \
        -e DELVANE_NTAK_CREDENTIAL_ROOT=/var/lib/delvane/empty-credentials \
        -e 'DELVANE_NTAK_CREDENTIAL_REFERENCES={"prop_uat_a":"synthetic-missing"}' "$image" \
        -I -c "$check_and_start" "$pg_address" "$host_ipv4")
    containers="$containers $app_id"
    check_container "$app_id" 335544320 created
    [ "$(docker_local inspect -f '{{.HostConfig.ReadonlyRootfs}}|{{.Config.User}}' "$app_id")" = 'true|10001:10001' ]
    docker_local start "$app_id" >/dev/null
    check_container "$app_id" 335544320 running
}

wait_for_app() {
    for attempt in $(seq 1 30); do
        if docker_local exec "$1" python -c 'from urllib.request import urlopen; urlopen("http://127.0.0.1:8080/health/ready", timeout=1).close()' 2>/dev/null; then
            return 0
        fi
        if [ "$(docker_local inspect -f '{{.State.Status}}' "$1")" = exited ]; then break; fi
        sleep 1
    done
    printf '%s\n' "Isolated application did not become ready: $1" >&2
    docker_local inspect -f 'Container state={{.State.Status}} exit={{.State.ExitCode}} oom={{.State.OOMKilled}}' "$1" >&2
    return 1
}

start_app "$app" "$db"
wait_for_app "$app"
docker_local exec -i "$app" python - <uat_postgres_smoke.py
docker_local stats --no-stream --format '{{.Name}} {{.MemUsage}}' "$app" "$pg"
docker_local exec "$app" sh -c 'if [ -r /sys/fs/cgroup/memory.peak ]; then printf "App startup peak bytes: "; cat /sys/fs/cgroup/memory.peak; fi'
check_host_guard
docker_local restart "$app" >/dev/null
wait_for_app "$app"
docker_local exec -i "$app" python - --verify-restart <uat_postgres_smoke.py
docker_local kill --signal KILL "$app_id" >/dev/null
check_network "$pg_id "
docker_local start "$app_id" >/dev/null
wait_for_app "$app"
docker_local exec -i "$app" python - --verify-crash <uat_postgres_smoke.py

# Freeze the writer, then restore a synthetic dump into a separate database.
# PostgreSQL data and the dump are both held in the disposable container's tmpfs.
docker_local stop "$app" >/dev/null
docker_local exec "$pg" sh -c 'umask 077; exec pg_dump -U postgres -Fc -f /tmp/delvane-uat.dump "$1"' sh "$db"
docker_local container rm --volumes "$app_id" >/dev/null
containers=$pg_id
docker_local exec "$pg" createdb -U postgres -O delvane_uat "$restore_db"
docker_local exec "$pg" pg_restore -U postgres --exit-on-error --no-owner --role=delvane_uat \
    -d "$restore_db" /tmp/delvane-uat.dump
start_app "$restored_app" "$restore_db"
wait_for_app "$restored_app"
docker_local exec -i "$restored_app" python - --verify-restore <uat_postgres_smoke.py
docker_local stats --no-stream --format '{{.Name}} {{.MemUsage}}' "$restored_app" "$pg"
docker_local exec "$pg" sh -c 'if [ -r /sys/fs/cgroup/memory.peak ]; then printf "PostgreSQL run peak bytes: "; cat /sys/fs/cgroup/memory.peak; fi'
if [ "$keep" = 1 ]; then
    printf 'Running synthetic UAT app: %s\nRunning disposable PostgreSQL: %s\n' "$app_id" "$pg_id"
    printf 'Stop and remove this run with: docker --host unix:///var/run/docker.sock rm -fv %s %s\n' "$app_id" "$pg_id"
    containers=
fi
