#!/usr/bin/env bash
# Run in the Hetzner root console after the reviewed app upgrade. Ctrl+C closes the socket.
set -euo pipefail
umask 077
[[ $(id -u) == 0 && $(hostname -s) == delvane-test-01 ]]
expected=${1:?Supply the verified installed ID of the migration-3091 app image}
[[ $expected =~ ^sha256:[a-f0-9]{64}$ ]]
mode=${2:-isolated}
[[ $mode == isolated || $mode == resend-trial ]]
docker_local() { docker --host unix:///var/run/docker.sock "$@"; }
unset DOCKER_CONTEXT DOCKER_HOST

network=delvane-ntak-preflight
format='{{.Id}}|{{.Driver}}|{{.Internal}}|{{.EnableIPv6}}|{{index .Options "com.docker.network.bridge.gateway_mode_ipv4"}}|{{index .Options "com.docker.network.bridge.name"}}|{{range .IPAM.Config}}{{if not (eq (printf "%v" .Gateway) "" "invalid IP")}}present{{end}}{{end}}|{{len .Containers}}'
settings=$(docker_local network inspect -f "$format" "$network")
net_id=${settings%%|*}
[[ -z $(ip -4 -o addr show dev br-delvane-uat) ]]
[[ -z $(ip -6 -o addr show scope global dev br-delvane-uat) ]]
policy=/root/delvane-uat-preflight/tests/uat_preflight_egress.nft
installed=$(nft -s -y -n list table inet delvane_uat_preflight)
[[ $(tr -d '[:space:]' <<<"$installed") == "$(tr -d '[:space:]' <"$policy")" ]]

peers=$(docker_local network inspect -f '{{range $id,$peer := .Containers}}{{printf "%s %s\n" $id $peer.Name}}{{end}}' "$network")
app=$(awk '$2 ~ /^delvane-uat-[a-f0-9]{12}-restored$/ {print $1}' <<<"$peers")
name=$(awk -v id="$app" '$1 == id {print $2}' <<<"$peers")
pg_name=${name%-restored}-pg
pg=$(awk -v name="$pg_name" '$2 == name {print $1}' <<<"$peers")
durable=$(awk -v name="$pg_name-durable" '$2 == name {print $1}' <<<"$peers")
[[ $app =~ ^[a-f0-9]{64}$ && $durable =~ ^[a-f0-9]{64}$ ]]
containers=("$app" "$durable")
if [[ -n $pg ]]; then
    [[ $pg =~ ^[a-f0-9]{64}$ ]]
    containers+=("$pg")
fi
[[ $settings == "$net_id|bridge|true|false|isolated|br-delvane-uat||${#containers[@]}" ]]
for container in "${containers[@]}"; do
    info=$(docker_local inspect -f '{{.State.Running}}|{{len .HostConfig.PortBindings}}|{{.HostConfig.PublishAllPorts}}|{{.HostConfig.Privileged}}|{{range .NetworkSettings.Networks}}{{.NetworkID}}|{{end}}' "$container")
    [[ $info == "true|0|false|false|$net_id|" ]]
done
[[ $(docker_local inspect -f '{{range .Mounts}}{{if eq .Destination "/var/lib/postgresql/data"}}{{.Type}}{{end}}{{end}}' "$durable") == volume ]]
[[ $(docker_local inspect -f '{{.Image}}|{{.HostConfig.ReadonlyRootfs}}|{{.Config.User}}' "$app") == "$expected|true|10001:10001" ]]
docker_local exec -i "$app" python - "$mode" <<'PY'
import json
import os
from pathlib import Path
import sys
from urllib.parse import urlsplit
from urllib.request import urlopen

env = os.environ
assert env['ROSA_DEPLOYMENT_ENVIRONMENT'] == 'staging'
assert env['ROSA_DEMO_MODE'] == '0'
assert env['DELVANE_GUEST_PUBLIC_ORIGIN'] == 'https://guest.delvane.app'
if sys.argv[1] == 'resend-trial':
    assert env['DELVANE_GUEST_EMAIL_PROVIDER'] == 'resend'
    assert env['DELVANE_GUEST_EMAIL_ENABLED'] in ('0', '1')
    assert env['RESEND_FROM_EMAIL'] == 'checkin@mail.delvane.app'
    assert env['RESEND_WEBHOOK_SECRET'] and env['RESEND_TEST_RECIPIENT']
    assert env['RESEND_HTTPS_PROXY'] == 'http://127.0.0.1:3128'
    assert bool(env.get('RESEND_API_KEY')) == (env['DELVANE_GUEST_EMAIL_ENABLED'] == '1')
else:
    assert env.get('DELVANE_GUEST_EMAIL_ENABLED', '0') == '0'
    assert not any(env.get(key) for key in ('RESEND_API_KEY', 'RESEND_WEBHOOK_SECRET', 'DELVANE_GUEST_EMAIL_PROVIDER', 'RESEND_HTTPS_PROXY'))
assert not any(name.lower().endswith('_proxy') and name != 'RESEND_HTTPS_PROXY' for name in env)
db = urlsplit(env['ROSA_DATABASE_URL'])
assert db.hostname == 'guest-pg' and db.path.startswith('/delvane_uat_') and db.path.endswith('_restored')
assert not Path('/proc/net/if_inet6').read_text().strip()
assert all(line.split()[1] != '00000000' and line.split()[2] == '00000000'
           for line in Path('/proc/net/route').read_text().splitlines()[1:])
with urlopen('http://127.0.0.1:8080/health/ready', timeout=3) as response:
    status = json.load(response)
assert status['schema_version'] == 3091 and status['database'] == 'postgresql'
with urlopen('http://127.0.0.1:8080/api/client/environment', timeout=3) as response:
    deployment = json.load(response)
assert deployment['environment'] == 'staging' and deployment['secure_cookies'] is True
assert deployment['deployment_id'].startswith('delvane-uat-')
PY

pid=$(docker_local inspect -f '{{.State.Pid}}' "$app")
[[ $pid =~ ^[1-9][0-9]*$ && $(readlink "/proc/$pid/ns/net") != "$(readlink /proc/self/ns/net)" ]]
dir=/run/delvane-guest-uat
config=${3:-/etc/delvane-guest-uat/nginx.conf}
[[ $config == /etc/delvane-guest-uat/nginx.conf || $config == /etc/delvane-permanent-uat/nginx.conf ]]
group=delvane-guest-tunnel
getent group "$group" >/dev/null
mkdir -m 0700 "$dir"
origin_pid=
cleanup() {
    if [[ -n $origin_pid ]]; then
        kill "$origin_pid" 2>/dev/null || true
        wait "$origin_pid" 2>/dev/null || true
    fi
    rm -f -- "$dir/origin.sock" "$dir/nginx.pid"
    rmdir -- "$dir"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
nsenter --target "$pid" --net -- /usr/sbin/nginx -e /dev/null -t -c "$config"
nsenter --target "$pid" --net -- /usr/sbin/nginx -e /dev/null -c "$config" &
origin_pid=$!
for _ in {1..30}; do
    [[ -S $dir/origin.sock ]] && break
    kill -0 "$origin_pid"
    sleep .1
done
[[ -S $dir/origin.sock ]]
chgrp "$group" "$dir" "$dir/origin.sock"
chmod 0660 "$dir/origin.sock"
chmod 0710 "$dir"
printf 'Private Unix origin socket ready.\n'
wait "$origin_pid"
