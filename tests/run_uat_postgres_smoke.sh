#!/bin/sh
# Linux only. Use a local Docker daemon and images already pulled or built.
set -eu
umask 077
cd "$(dirname "$0")"
image=${1:-delvane-uat:local}
postgres=${2:-postgres:17-bookworm}
unset DOCKER_CONTEXT DOCKER_HOST
docker_config=$(mktemp -d)
network=
containers=

docker_local() {
    docker --config "$docker_config" --host unix:///var/run/docker.sock "$@"
}

cleanup() {
    for container in $containers; do
        docker_local container rm --force --volumes "$container" >/dev/null
    done
    if [ -n "$network" ]; then
        docker_local network rm "$network" >/dev/null
    fi
    rmdir "$docker_config"
}
trap cleanup EXIT
trap 'exit 1' INT TERM

random_hex() {
    od -An -N24 -tx1 /dev/urandom | tr -d ' \n'
}

image=$(docker_local image inspect -f '{{.Id}}' "$image")
postgres=$(docker_local image inspect -f '{{.Id}}' "$postgres")
suffix=$(random_hex | cut -c1-12)
network_name=delvane-uat-$suffix
network=$(docker_local network create --internal --ipv6=false "$network_name")
[ "$(docker_local network inspect -f '{{.Internal}}|{{.EnableIPv6}}|{{.Driver}}' "$network")" = 'true|false|bridge' ]
pg=$network_name-pg
app=$network_name-app
restored_app=$network_name-restored
db=delvane_uat_$suffix
restore_db=${db}_restored

check_container() {
    settings=$(docker_local inspect -f '{{.HostConfig.NetworkMode}}|{{len .HostConfig.PortBindings}}|{{.HostConfig.Privileged}}|{{range .Mounts}}{{if eq .Type "bind"}}bind{{end}}{{end}}' "$1")
    [ "$settings" = "$network_name|0|false|" ]
    [ "$(docker_local inspect -f '{{len .NetworkSettings.Networks}}' "$1")" = 1 ]
}

POSTGRES_PASSWORD=$(random_hex)
UAT_ROLE_PASSWORD=$(random_hex)
export POSTGRES_PASSWORD UAT_ROLE_PASSWORD
pg_id=$(docker_local create --pull=never --name "$pg" --network "$network_name" --network-alias isolated-pg \
    --tmpfs /var/lib/postgresql/data:rw,noexec,nosuid,size=512m \
    --tmpfs /tmp:rw,noexec,nosuid,size=64m -e POSTGRES_PASSWORD "$postgres")
containers="$containers $pg_id"
docker_local start "$pg_id" >/dev/null
check_container "$pg_id"
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

ROSA_ENCRYPTION_KEY=$(docker_local run --pull=never --rm --network none --entrypoint python "$image" \
    -c 'from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())')
export ROSA_ENCRYPTION_KEY

start_app() {
    ROSA_DATABASE_URL="postgresql://delvane_uat:$UAT_ROLE_PASSWORD@isolated-pg:5432/$2?connect_timeout=3"
    export ROSA_DATABASE_URL
    app_id=$(docker_local create --pull=never --name "$1" --network "$network_name" --read-only --cap-drop ALL \
        --security-opt no-new-privileges --tmpfs /tmp:rw,noexec,nosuid \
        --tmpfs /var/lib/delvane:rw,noexec,nosuid,uid=10001,gid=10001 \
        -e ROSA_APP_ENV=production -e ROSA_DEPLOYMENT_ENVIRONMENT=staging -e ROSA_DEPLOYMENT_ID="$network_name" \
        -e ROSA_SECURE_COOKIES=1 -e ROSA_DEMO_MODE=0 -e ROSA_AI_PROVIDER=local -e ROSA_ENCRYPTION_KEY -e ROSA_DATABASE_URL \
        -e DELVANE_NTAK_CREDENTIAL_ROOT=/var/lib/delvane/empty-credentials \
        -e 'DELVANE_NTAK_CREDENTIAL_REFERENCES={"prop_uat_a":"synthetic-missing"}' "$image")
    containers="$containers $app_id"
    [ "$(docker_local inspect -f '{{.HostConfig.ReadonlyRootfs}}|{{.Config.User}}' "$app_id")" = 'true|10001:10001' ]
    docker_local start "$app_id" >/dev/null
    check_container "$app_id"
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
    return 1
}

start_app "$app" "$db"
wait_for_app "$app"
docker_local exec -i "$app" python - <uat_postgres_smoke.py
docker_local restart "$app" >/dev/null
wait_for_app "$app"
docker_local exec -i "$app" python - --verify-restart <uat_postgres_smoke.py

# Freeze the writer, then restore a synthetic dump into a separate database.
# PostgreSQL data and the dump are both held in the disposable container's tmpfs.
docker_local stop "$app" >/dev/null
docker_local exec "$pg" sh -c 'umask 077; exec pg_dump -U postgres -Fc -f /tmp/delvane-uat.dump "$1"' sh "$db"
docker_local exec "$pg" createdb -U postgres -O delvane_uat "$restore_db"
docker_local exec "$pg" pg_restore -U postgres --exit-on-error --no-owner --role=delvane_uat \
    -d "$restore_db" /tmp/delvane-uat.dump
start_app "$restored_app" "$restore_db"
wait_for_app "$restored_app"
docker_local exec -i "$restored_app" python - --verify-restore <uat_postgres_smoke.py
