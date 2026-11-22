#!/bin/sh
# Local disposable lab using the already-reviewed UAT runtimes. No image pulls.
set -eu
root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
docker_local() { command docker --host unix:///var/run/docker.sock "$@"; }

backend=sha256:08b340b1e459d2a8ecedbaa06c1317ef22c9cb2f87412dee0bfe7db07182fe35
postgres=sha256:39d36505873241b90584a61078c0a3af0a226a363854fcc2d722a72ce7a00500
docker_local image inspect "$backend" "$postgres" >/dev/null
suffix=$(od -An -N8 -tx1 /dev/urandom | tr -d ' \n')
net=delvane-pilot-$suffix
pg=$net-pg
app=$net-app
db=delvane_uat_pilot_$suffix
cleanup() {
    docker_local rm -f "$app" "$pg" >/dev/null 2>&1 || true
    docker_local network rm "$net" >/dev/null 2>&1 || true
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
docker_local network create --internal --driver bridge \
  --opt com.docker.network.bridge.gateway_mode_ipv4=isolated "$net" >/dev/null
test "$(docker_local network inspect --format '{{.Internal}} {{.EnableIPv6}} {{index .Options "com.docker.network.bridge.gateway_mode_ipv4"}}' "$net")" = 'true false isolated'

POSTGRES_PASSWORD=$(od -An -N24 -tx1 /dev/urandom | tr -d ' \n')
PILOT_DB_PASSWORD=$(od -An -N24 -tx1 /dev/urandom | tr -d ' \n')
export POSTGRES_PASSWORD PILOT_DB_PASSWORD
docker_local run -d --pull=never --name "$pg" --network "$net" --network-alias isolated-pg \
  --memory 384m --pids-limit 128 --dns 127.0.0.1 --sysctl net.ipv6.conf.all.disable_ipv6=1 \
  --tmpfs /var/lib/postgresql/data:rw,noexec,nosuid,size=256m \
  -e POSTGRES_PASSWORD "$postgres" >/dev/null
for _ in $(seq 1 45); do
    docker_local exec "$pg" pg_isready -h 127.0.0.1 -U postgres -q && break
    sleep 1
done
docker_local exec -i -e PILOT_DB_PASSWORD "$pg" psql -q -v ON_ERROR_STOP=1 -v db="$db" -U postgres <<'SQL'
\getenv role_password PILOT_DB_PASSWORD
CREATE ROLE delvane_uat LOGIN PASSWORD :'role_password' NOSUPERUSER NOCREATEDB NOCREATEROLE;
CREATE DATABASE :"db" OWNER delvane_uat;
REVOKE CONNECT ON DATABASE postgres FROM PUBLIC;
REVOKE CONNECT ON DATABASE template1 FROM PUBLIC;
SQL

ROSA_DATABASE_URL="postgresql://delvane_uat:$PILOT_DB_PASSWORD@isolated-pg:5432/$db?connect_timeout=3"
ROSA_ENCRYPTION_KEY=$(head -c 32 /dev/urandom | base64 | tr '+/' '-_')
export ROSA_DATABASE_URL ROSA_ENCRYPTION_KEY
docker_local run -d --pull=never --name "$app" --network "$net" \
  --memory 512m --pids-limit 128 --read-only --cap-drop ALL \
  --security-opt no-new-privileges --dns 127.0.0.1 --sysctl net.ipv6.conf.all.disable_ipv6=1 \
  --tmpfs /tmp:rw,noexec,nosuid,size=32m --tmpfs /var/lib/delvane:rw,noexec,nosuid,uid=10001,gid=10001,size=32m \
  --mount "type=bind,src=$root/app.py,dst=/app/app.py,readonly" \
  --mount "type=bind,src=$root/guest_stays.py,dst=/app/guest_stays.py,readonly" \
  --mount "type=bind,src=$root/tests/uat_postgres_smoke.py,dst=/pilot/uat_postgres_smoke.py,readonly" \
  --mount "type=bind,src=$root/tests/pilot_postgres_rehearsal.py,dst=/pilot/pilot_postgres_rehearsal.py,readonly" \
  -e ROSA_DATABASE_URL -e ROSA_ENCRYPTION_KEY -e ROSA_APP_ENV=production \
  -e ROSA_DEPLOYMENT_ENVIRONMENT=staging -e "ROSA_DEPLOYMENT_ID=delvane-uat-pilot-$suffix" \
  -e ROSA_DEMO_MODE=0 -e ROSA_SECURE_COOKIES=1 -e ROSA_AI_PROVIDER=local \
  -e DELVANE_NTAK_CREDENTIAL_ROOT=/var/lib/delvane/empty-credentials -e PYTHONPATH=/app \
  "$backend" python -m uvicorn app:app --host 127.0.0.1 --port 8080 --no-access-log >/dev/null
test "$(docker_local inspect --format '{{.HostConfig.ReadonlyRootfs}} {{len .HostConfig.PortBindings}}' "$app")" = 'true 0'
test "$(docker_local inspect --format '{{len .HostConfig.PortBindings}}' "$pg")" = '0'

wait_ready() {
    for _ in $(seq 1 45); do
        if docker_local exec "$app" python -c \
          'from urllib.request import urlopen; assert urlopen("http://127.0.0.1:8080/health/ready", timeout=2).status == 200' 2>/dev/null; then
            return 0
        fi
        sleep 1
    done
    docker_local logs --tail 30 "$app"
    return 1
}
docker_local exec "$pg" postgres --version
wait_ready
docker_local exec "$app" python /pilot/pilot_postgres_rehearsal.py
docker_local restart "$app" >/dev/null
wait_ready
docker_local exec "$app" python /pilot/pilot_postgres_rehearsal.py --restart
