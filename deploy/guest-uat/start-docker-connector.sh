#!/usr/bin/env bash
# Run only after private-origin verification and with the Cloudflare Routes tab empty.
set +x
set -euo pipefail
umask 077
[[ $(id -u) == 0 && $(hostname -s) == delvane-test-01 && -t 0 ]]
unset DOCKER_CONTEXT DOCKER_HOST
docker_local() { docker --host unix:///var/run/docker.sock "$@"; }

directory=/etc/delvane-guest-uat
name=delvane-guest-tunnel
origin=/run/delvane-guest-uat/origin.sock
secret=$directory/tunnel.token
tunnel=94dab672-b04b-4fcb-83d6-ee8e1c3bdca7
uid=$(id -u "$name")
gid=$(id -g "$name")
[[ $uid != 0 && $gid != 0 && -S $origin && ! -e $secret ]]
[[ $(stat -c '%u:%g:%a' "$origin") == "0:$gid:660" ]]
[[ -s $directory/connector-image-id ]]
image=$(<"$directory/connector-image-id")
[[ $image =~ ^sha256:[a-f0-9]{64}$ ]]
[[ $(docker_local image inspect -f '{{.Id}}|{{.Os}}|{{.Architecture}}' "$image") == "$image|linux|amd64" ]]
[[ $(docker_local info -f '{{json .SecurityOptions}}') != *rootless* ]]
if docker_local inspect "$name" >/dev/null 2>&1 ||
   nft list table inet delvane_guest_connector >/dev/null 2>&1 ||
   systemctl is-active --quiet delvane-guest-tunnel.service; then
    printf 'A guest connector or its firewall already exists.\n' >&2
    exit 1
fi
[[ -z $(ss -H -ltn 'sport = :19764') ]]
[[ -n $(ss -H -lun 'sport = :53' | awk '$4 ~ /^127\.0\.0\.53(%lo)?:53$/') ]]
status=$(curl -fsS --max-time 4 -o /dev/null -w '%{http_code}' --unix-socket "$origin" \
    -H 'X-Forwarded-Proto: https' http://guest.delvane.app/static/guest-checkin.css)
[[ $status == 200 ]]
status=$(curl -sS --max-time 4 -o /dev/null -w '%{http_code}' --unix-socket "$origin" \
    -H 'X-Forwarded-Proto: https' http://guest.delvane.app/api/reservations)
[[ $status == 404 ]]

printf 'Confirm Cloudflare shows no published applications or private routes.\n'
read -r -p 'Type EMPTY to continue: ' confirmed
[[ $confirmed == EMPTY ]]
read -rs -p 'Paste the Cloudflare connector token: ' token
printf '\n'
[[ -n $token && ${#token} -le 4096 ]]

created=
firewall=
written=
cleanup_failed_start() {
    if [[ -n $created ]]; then
        docker_local rm -f "$name" >/dev/null 2>&1 || return
    fi
    [[ -z $firewall ]] || nft delete table inet delvane_guest_connector
    [[ -z $written ]] || rm -f -- "$secret"
}
trap cleanup_failed_start EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
python_code=$(cat <<'PY'
import base64
import json
import os
import sys

path, group, expected = sys.argv[1:]
token = sys.stdin.buffer.read().strip()
try:
    parsed = json.loads(base64.b64decode(token, validate=True))
    if parsed['t'] != expected or not parsed['a'] or not parsed['s']:
        raise ValueError
except (KeyError, TypeError, ValueError):
    raise SystemExit('Token does not match delvane-guest-uat.')
with open(path, 'xb') as locked:
    locked.write(token + b'\n')
    os.fchown(locked.fileno(), 0, int(group))
    os.fchmod(locked.fileno(), 0o440)
PY
)
printf '%s' "$token" | python3 -I -c "$python_code" "$secret" "$gid" "$tunnel"
unset token
written=1

# Keep the existing app bridge and firewall unchanged. The connector runs in the
# host namespace as its dedicated host UID. This rule only permits local metrics
# replies in addition to the reviewed Cloudflare TCP 7844 and trusted DNS access.
rules_and_metrics() {
    cat "$directory/connector-egress.nft"
    printf '%s\n' 'insert rule inet delvane_guest_connector connector_only oifname "lo" ip daddr 127.0.0.1 tcp sport 19764 ct state established accept'
}
rules_and_metrics | nft -c -f -
rules_and_metrics | nft -f -
firewall=1
[[ $(nft -n list chain inet delvane_guest_connector output) == *"skuid $uid"* ]]

docker_local create --pull=never --name "$name" --network host --userns host \
    --user "$uid:$gid" --read-only --cap-drop ALL --security-opt no-new-privileges \
    --pids-limit 48 --memory 160m --memory-swap 160m --log-driver none \
    --label "com.delvane.tunnel.id=$tunnel" \
    --mount "type=bind,src=$origin,dst=$origin,readonly" \
    --mount "type=bind,src=$secret,dst=/run/delvane-token,readonly" \
    "$image" tunnel --no-autoupdate --edge-ip-version 4 --metrics 127.0.0.1:19764 \
    run --protocol http2 --dns-resolver-addrs 127.0.0.53:53 --token-file /run/delvane-token >/dev/null
created=1
[[ $(docker_local inspect -f '{{.HostConfig.NetworkMode}}|{{.HostConfig.UsernsMode}}|{{.Config.User}}|{{.HostConfig.ReadonlyRootfs}}|{{len .HostConfig.PortBindings}}' "$name") == "host|host|$uid:$gid|true|0" ]]
docker_local start "$name" >/dev/null
for _ in {1..35}; do
    if curl -fsS --max-time 2 -o /dev/null http://127.0.0.1:19764/ready 2>/dev/null; then
        trap - EXIT INT TERM
        printf 'Connector is ready. No public Cloudflare route was created.\n'
        exit 0
    fi
    [[ $(docker_local inspect -f '{{.State.Running}}' "$name") == true ]] || break
    sleep 1
done
printf 'Connector did not become ready. The private guest origin is still available.\n' >&2
exit 1
