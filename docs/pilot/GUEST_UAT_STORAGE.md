# Guest UAT PostgreSQL storage recovery

The failed upgrade restored a second database into the original PostgreSQL cluster. Its 256 MiB tmpfs already held about 224 MiB of database files and 32 MiB of WAL. Files on the host disk could not use the unallocated space inside that separate mount. The live resize to 512 MiB provided room for recovery. That mount still depends on the original PostgreSQL container staying up and still counts toward its 768 MiB container limit. Restarting the original PostgreSQL container would also reapply the configuration it was created with. [Docker tmpfs behavior](https://docs.docker.com/engine/storage/tmpfs/)

The revised cutover creates a second PostgreSQL 17.12 container with a named disk-backed volume and the private alias `guest-pg`. It runs on the existing internal bridge with IPv6 disabled and no published ports. The new container is capped at 384 MiB with 64 MiB of shared buffers. The original PostgreSQL stays running on `isolated-pg` with its original data. The previous FastAPI container and original database remain available for rollback. The guest application image, Cloudflare connector image and tunnel token workflow are unchanged. Resend, NTAK and VIZA transmissions stay disabled.

Before creating a new database workload, the script checks the live source mount for at least 64 MiB free and the host for at least 512 MiB available memory. It also checks the Docker and backup filesystems for the greater of 4 GiB or three times the source database size plus 1 GiB. After initializing the new PostgreSQL server, it verifies the named mount is disk-backed and checks its headroom again before stopping the original app. Monitor free bytes on the source and durable mounts while they coexist. [Docker volume persistence](https://docs.docker.com/engine/storage/volumes/)

## Next approved action

Stage the revised controls using the pinned SSH workflow in [Guest UAT Cloudflare](GUEST_UAT_CLOUDFLARE.md). Verify the root copy of the revised deploy script against `STORAGE-STAGE-SHA256SUMS-v2`. Its SHA-256 is `30462ffd6e2997f04b1d455dac93970eeefe1cc04bce7f707b867f262a32561f`. For an online snapshot before deploying, run:

```sh
bash /root/delvane-guest-deploy-storage.sh --backup-only
```

Run this from the Hetzner root console. It saves a custom-format dump and SHA-256 manifest under `/var/lib/delvane-uat-backups/`, verifies that `pg_restore --list` reads the archive, verifies the checksum, and checks the running app's private readiness. It stores the matching application encryption key under `/var/lib/delvane-uat-recovery-keys/` with mode 0600. Both directories are root-only. It works with the recovered 3090 app or the verified 3091 durable deployment. Keep the displayed backup directory and its matching key association private. The online command keeps both existing containers running and does not activate the guest origin.

The first storage bundle had a mistyped PostgreSQL OCI manifest ID. The v2 controls accept only the two IDs independently recalculated from the previously verified `postgres-17.12-linux-amd64-local.tar.gz` archive and check the locally installed image platform.

| Docker image identity | Expected digest |
| --- | --- |
| Image config | `sha256:39d36505873241b90584a61078c0a3af0a226a363854fcc2d722a72ce7a00500` |
| OCI manifest | `sha256:ab4586ee3c07b4f65cf3daaf55ed008ff619b496bff60e361c30d664bca78401` |

After approval for the cutover, verify the snapshot manifest in its reported directory with `sha256sum -c SHA256SUMS`, close the Windows relay from its root console if it is active, then run:

```sh
bash /root/delvane-guest-deploy-storage.sh
```

The deploy command repeats preflight, creates the named volume and validates it before stopping only the original FastAPI app. It then takes a fresh quiesced snapshot to include all writes up to cutover. It checks the archive, restores it into the new isolated PostgreSQL server, compares schema and row counts for properties, reservations and registrations, and runs the new app to migration 3091. It verifies the private guest origin before the separate connector step. If the upgrade fails, it restores access through the original app and retains the snapshot and any newly created volume for inspection. The old failed clone, if present, is left in place.

## Recovery and rollback

**Container restart or replacement.** Reuse the same recorded named volume and the reviewed PostgreSQL 17.12 image with the same isolated attachment and `guest-pg` alias. Keep a single PostgreSQL process on that volume. Docker container removal should specify only the intended container, and storage cleanup should be handled independently. Check mount type, free disk and PostgreSQL readiness before reconnecting the app. The deployment does not change PostgreSQL on the original tmpfs.

**Restore a snapshot without overwriting a live database.** Use the verified PostgreSQL 17.12 durable server on the isolated bridge. If its storage was lost, provision it with a fresh named volume and the same unpublished, isolated runtime options in `create_postgres` in the upgrade script. Provision the limited `delvane_uat` role privately if the server is new. Verify the snapshot on the host, then restore into a fresh database name.

```sh
# Set snapshot to the reported private backup directory and pg to the
# reviewed -pg-durable container name. Use a fresh recovery database name.
(cd "$snapshot" && sha256sum -c SHA256SUMS) || exit 1
docker --host unix:///var/run/docker.sock exec "$pg" \
    createdb -U postgres -O delvane_uat "$recovery_db" || exit 1
docker --host unix:///var/run/docker.sock exec -i "$pg" \
    pg_restore -U postgres --exit-on-error --no-owner --role=delvane_uat \
    -d "$recovery_db" <"$snapshot/synthetic.dump" || exit 1
docker --host unix:///var/run/docker.sock exec "$pg" \
    psql -X -U postgres -d "$recovery_db" -Atqc 'SELECT MAX(version) FROM schema_migrations'
```

Compare the schema with `recovery.json` and any recorded counts. For application recovery, use the matched encryption key file from `recovery.json` through the private runtime environment, point a separately isolated candidate app at the restored database, and verify readiness and encrypted evidence before any cutover. Put credentials only in the private runtime environment. A 3090 backup should restore as 3090 before running the 3091 app. Back up regularly while testing. These copies survive container loss. A separate protected copy would be needed to recover from host disk loss. [PostgreSQL backup format](https://www.postgresql.org/docs/17/app-pgdump.html) · [PostgreSQL restore](https://www.postgresql.org/docs/17/app-pgrestore.html)

**Return to the previous app.** Stop the guest connector, private guest origin and Windows relay first. Stop the replacement app and the new `-pg-durable` container, preserving its volume. Rename the replacement app, rename the `-previous` app back, and start it against the original PostgreSQL. Verify readiness through the old private access path. The original app remains on its 3090 database. During a later return to 3091, reconcile any newer synthetic writes made on either side before reusing a copy.

## Local verification

- A disposable PostgreSQL 17.12 lab rejected a low source-mount capacity and a low host-disk capacity before stopping the original app or creating a database container.
- The lab took an online 3090 snapshot, restored a fresh quiesced copy to a named volume and migrated that copy to 3091. A fictional encrypted record still decrypted with the preserved key. The stored archive also restored into another database at 3090. A snapshot taken from the durable app recorded schema 3091.
- The durable PostgreSQL container restarted with the migrated data intact. Rollback restored the original 3090 app and the original PostgreSQL container ID and start time stayed the same. The normal Pilot journey and fake email delivery also passed their separate app restart rehearsals on disk-backed volumes.
- Shell and PowerShell syntax, both artifact manifests and Git whitespace checks passed. The broader historical UAT harness stopped at its existing swap guard because WSL has active swap and its Docker engine cannot enforce the swap limit. The guard was kept intact.

The original storage rehearsals were local. The v2 patch uploaded only the replacement control archive, wrapper and checksum manifest to the existing private stage. Focused checks accepted both reviewed digests and rejected unreviewed digests, an inconsistent image inspection and the wrong platform. The full repeat rehearsal stopped before starting containers because the local Docker daemon was unavailable.
