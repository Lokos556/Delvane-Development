#!/usr/bin/env bash
# Root entry point. The default configures receipts and the egress test with sending paused.
set +x
set -Eeuo pipefail
umask 077
export LC_ALL=C
[[ $(id -u) == 0 && $(hostname -s) == delvane-test-01 ]] || { echo 'Run from the UAT root SSH terminal.' >&2; exit 1; }
action=${1:-configure}
[[ $# -le 1 && ( $action == configure || $action == arm || $action == pause ) ]] || exit 1
exec 9>/run/lock/delvane-guest-uat-deploy.lock
flock -n 9 || { echo 'Another guest UAT change is running.' >&2; exit 1; }
stage=/home/delvane-uat/delvane-guest-storage-3091
work=/root/delvane-resend-trial
archive=delvane-resend-trial-controls-v2.tar.gz
install -d -m 0700 "$work"
cd "$work"
if [[ $action == configure ]]; then
    install -m 0600 -- "$stage/$archive" "$archive"
fi
printf '%s  %s\n' 55776d6cd5420f55f8466831b5001c1381a41c096d9095fc8c2b67d0dae3690a "$archive" | sha256sum -c --strict -
tar -xzf "$archive"
exec python3 -I -B deploy/guest-uat/resend-trial.py "$action"
