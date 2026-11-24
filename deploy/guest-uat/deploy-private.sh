#!/usr/bin/env bash
# Root entry point for the reviewed app upgrade and private guest origin.
set -Eeuo pipefail
umask 077
die() { printf '%s\n' "$1" >&2; exit 1; }
step='verify the root console and deployment arguments'
trap 'printf "Deployment stopped while attempting to %s (line %s, exit %s).\n" "$step" "$LINENO" "$?" >&2' ERR
[[ $(id -u) == 0 && $(hostname -s) == delvane-test-01 ]] || die 'Run on delvane-test-01 from the root console.'
unset DOCKER_CONTEXT DOCKER_HOST
docker_local() { docker --host unix:///var/run/docker.sock "$@"; }
stage=/home/delvane-uat/delvane-guest-storage-3091
destination=/root/delvane-guest-uat-3091
etc=/etc/delvane-guest-uat
app_archive=delvane-guest-3091-local.tar.gz
controls=delvane-guest-uat-storage-controls-v4.tar.gz
connector_archive=cloudflared-2026.11.1-linux-amd64.tar.gz
mode=${1:---recover-snapshot}
[[ $# -le 1 && ( $mode == --recover-snapshot || $mode == deploy || $mode == --backup-only || $mode == --check-storage ) ]] ||
    die 'Unrecognized deployment mode.'
exec 9>/run/lock/delvane-guest-uat-deploy.lock
flock -n 9 || die 'Another guest UAT deployment or backup is already running.'
step='prepare the private root staging directory'
install -d -m 0700 "$destination"
cd "$destination"

verify_copy() {
    install -m 0600 -- "$stage/$2" "$2"
    printf '%s  %s\n' "$1" "$2" | sha256sum -c -
}
step='verify and extract the reviewed deployment controls'
verify_copy 6a0ebcbd253198d3047db68070ef5bc730ecd291dcd2403cd19049a479647a97 "$controls"
tar -xzf "$controls"
if [[ $mode == --backup-only || $mode == --check-storage ]]; then
    exec python3 -B deploy/guest-uat/upgrade-app.py "$mode"
fi
[[ ! -S /run/delvane-uat-access/https.sock ]] ||
    die 'Close the existing Windows relay from its administrator console first.'
if [[ -e /run/delvane-guest-uat || -e $etc/tunnel.token ]] ||
   systemctl is-active --quiet delvane-guest-origin.service ||
   systemctl is-active --quiet delvane-guest-tunnel.service ||
   docker_local container inspect delvane-guest-tunnel >/dev/null 2>&1 ||
   nft list table inet delvane_guest_connector >/dev/null 2>&1; then
    die 'An existing guest origin, connector, or connector configuration needs review before this deployment.'
fi
snapshot=/var/lib/delvane-uat-backups/delvane_uat_ed88fcdce45e_restored-20261123T184240Z-4aa68e8f
step='verify the existing private schema-3090 backup on disk'
(
    cd "$snapshot"
    sha256sum -c --strict SHA256SUMS
)
if [[ $mode == deploy ]]; then
    step='check the original database, isolated network, and storage headroom'
    python3 -B deploy/guest-uat/upgrade-app.py --check-storage
fi
step='verify the pinned app and Cloudflare archives'
install -d -m 0700 "$etc"
verify_copy cb8d8a885cc41fe2752424598256793a8a150a2b2add1676c0b0d47ddb744250 "$app_archive"
verify_copy c28ea5d1302e42417865d57f63f9c3279ed2d4984e1a425ce89489b4c9de3fa3 "$connector_archive"
verify_copy 37fe265e6dae47c21da7109313e1c1752658ff6145809be9112d59ae96e5d741 start-docker-connector.sh
step='load and verify the reviewed app and connector images'
docker_local load -i "$app_archive"
docker_local load -i "$connector_archive"
format='{{.Id}}|{{.Os}}|{{.Architecture}}'
app=$(docker_local image inspect -f "$format" delvane-uat:guest-3091-local)
case "$app" in
    'sha256:83e46c173f98a144cf985858ad24f423966fcf2adadc550a7adddfff885a7654|linux|amd64'|'sha256:302152b806711f90da59e67cbda43c352ff92a0154f34fba09bcf16c73bcddbb|linux|amd64') ;;
    *) printf 'Unexpected installed application image ID.\n' >&2; exit 1 ;;
esac
cf=$(docker_local image inspect -f "$format" cloudflare/cloudflared:2026.11.1)
case "$cf" in
    'sha256:fdb93d510a5897d1a4b10350937997d0bd4480a0218db85e9346a2e105aa9d87|linux|amd64'|'sha256:78e09f58bbf9db59bc274b381b8c5e9b43c540be478c1217b06adb99deb39fe1|linux|amd64') ;;
    *) printf 'Unexpected installed Cloudflare image ID.\n' >&2; exit 1 ;;
esac
app=${app%%|*}
cf=${cf%%|*}
printf '%s\n' "$app" >"$destination/app-image-id"
printf '%s\n' "$cf" >"$etc/connector-image-id"

step='prepare the socket-only Nginx origin and validate connector rules'
if systemctl is-active --quiet nginx.service; then
    printf 'The ordinary Nginx service is already active. Review it before deploying.\n' >&2
    exit 1
fi
if [[ ! -x /usr/sbin/nginx ]]; then
    systemctl mask nginx.service
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends nginx
fi
if systemctl is-active --quiet nginx.service; then exit 1; fi
getent passwd delvane-guest-tunnel >/dev/null ||
    useradd --system --user-group --shell /usr/sbin/nologin delvane-guest-tunnel
[[ $(id -u delvane-guest-tunnel) != 0 && $(id -g delvane-guest-tunnel) != 0 ]]
install -m 0600 deploy/guest-uat/nginx.conf deploy/guest-uat/connector-egress.nft "$etc/"
nft -c -f "$etc/connector-egress.nft"
step='restore to disk, migrate the clone, and verify the private guest origin'
if [[ $mode == --recover-snapshot ]]; then
    python3 -B deploy/guest-uat/upgrade-app.py --recover-snapshot "$app"
else
    python3 -B deploy/guest-uat/upgrade-app.py --private-origin "$app"
fi
printf 'Private guest origin verified. Cloudflare connector is staged and stopped.\n'
printf 'For private Windows access, run from this root console after deployment:\n'
printf '%s\n' 'cd /root/delvane-guest-uat-3091' 'bash tests/run_uat_windows_relay.sh "$(cat app-image-id)"'
