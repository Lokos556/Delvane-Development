#!/usr/bin/env bash
# Stage root-owned code, units and an immutable image. No services are started.
set -euo pipefail
umask 077
[[ $(id -u) == 0 && $(hostname -s) == delvane-test-01 ]]
stage=/home/delvane-uat/delvane-guest-storage-3091
target=/opt/delvane-permanent-uat
etc=/etc/delvane-permanent-uat
manifest_hash=${1:?Supply the independently verified SHA-256 of PERMANENT-STAGE-SHA256SUMS}
[[ $manifest_hash =~ ^[a-f0-9]{64}$ && ! -e $target && ! -e $etc ]]
archive=delvane-permanent-3091-local.tar.gz
controls=delvane-permanent-controls.tar.gz
manifest=PERMANENT-STAGE-SHA256SUMS
work=$(mktemp -d /root/delvane-permanent-stage.XXXXXXXX)
trap 'rm -rf -- "$work"' EXIT
for file in "$archive" "$controls" "$manifest" install-delvane-permanent.sh; do
    install -m 0600 -- "$stage/$file" "$work/$file"
done
cd "$work"
printf '%s  %s\n' "$manifest_hash" "$manifest" | sha256sum -c --strict
sha256sum -c --strict "$manifest"
mkdir -m 0700 files
tar --extract --gzip --file "$controls" --directory files --no-same-owner --no-same-permissions
docker --host unix:///var/run/docker.sock load -i "$archive"
installed=$(docker --host unix:///var/run/docker.sock image inspect -f '{{.Id}}' delvane-uat:permanent-3091-local)
[[ $installed == "$(cat files/image.id)" || $installed == "$(cat files/image-manifest.id)" ]]
install -d -m 0700 "$target" "$etc"
for file in permanent.py upgrade-app.py resend-trial.py resend-connect.py run-origin.sh nginx.conf connector-egress.nft uat_access.py image.id image-manifest.id; do
    install -m 0600 -- "files/$file" "$target/$file"
done
for file in native-api.conf native-upstream.conf; do
    install -m 0600 -- "files/$file" "$etc/$file"
done
for unit in delvane-permanent-uat.service delvane-permanent-uat-backup.service delvane-permanent-uat-backup.timer; do
    [[ ! -e /etc/systemd/system/$unit ]]
    install -m 0644 -- "files/$unit" "/etc/systemd/system/$unit"
done
systemd-analyze verify /etc/systemd/system/delvane-permanent-uat{.service,-backup.service,-backup.timer}
systemctl daemon-reload
printf 'Verified package installed. Live containers, services and Cloudflare routes were not switched.\n'
