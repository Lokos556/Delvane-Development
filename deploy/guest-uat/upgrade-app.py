"""Replace only the synthetic restored UAT application after deployment approval."""

import hashlib
import json
import os
from pathlib import Path
import re
import secrets
import socket
import stat
import subprocess
import sys
import tempfile
import time
from urllib.parse import urlsplit


DOCKER = ('docker', '--host', 'unix:///var/run/docker.sock')
NETWORK = 'delvane-ntak-preflight'
EGRESS_POLICY = Path('/root/delvane-uat-preflight/tests/uat_preflight_egress.nft')
BACKUPS = Path('/var/lib/delvane-uat-backups')
RECOVERY_KEYS = Path('/var/lib/delvane-uat-recovery-keys')
RECOVERY_DB = 'delvane_uat_ed88fcdce45e_restored'
RECOVERY_POINT = '2026-11-23 18:42:40 UTC (approximately, at backup start)'
RECOVERY_NAME = RECOVERY_DB + '-20261123T184240Z-4aa68e8f'
PGDATA = '/var/lib/postgresql/data'
ORIGIN_UNIT = 'delvane-guest-origin.service'
ORIGIN_SOCKET = '/run/delvane-guest-uat/origin.sock'
MIB = 1024 * 1024
GIB = 1024 * MIB
BASE_IMAGES = {
    'sha256:08b340b1e459d2a8ecedbaa06c1317ef22c9cb2f87412dee0bfe7db07182fe35',
    'sha256:59220537262a50c84cc66be88890a5485d9a7da2f2b5fa91a10e90b8f5171720',
}
GUEST_IMAGES = {
    'sha256:83e46c173f98a144cf985858ad24f423966fcf2adadc550a7adddfff885a7654',
    'sha256:302152b806711f90da59e67cbda43c352ff92a0154f34fba09bcf16c73bcddbb',
}
POSTGRES_IMAGES = {
    'sha256:39d36505873241b90584a61078c0a3af0a226a363854fcc2d722a72ce7a00500',
    'sha256:ab4586ee3c07b4f65cf3daaf55ed008ff619b496bff60e361c30d664bca78401',
}
READY = """import json
import sys
from urllib.request import urlopen
with urlopen('http://127.0.0.1:8080/health/ready', timeout=2) as response:
    facts = json.load(response)
if facts != {'status': 'ready', 'database': 'postgresql', 'schema_version': int(sys.argv[1])}:
    raise SystemExit(1)
"""


class PreflightError(RuntimeError):
    pass


def require(condition, message):
    if not condition:
        raise PreflightError(message)


def docker(*args, **kwargs):
    return subprocess.check_output((*DOCKER, *args), stderr=subprocess.PIPE, **kwargs)


def failure_reason(error):
    # Docker/PostgreSQL output may contain SQL, connection strings or guest data.
    if isinstance(error, subprocess.CalledProcessError):
        diagnostic = (error.stderr or b'').decode(errors='replace').lower()
        for pattern, reason in (
            ('no space left on device', 'filesystem is full'),
            ('permission denied', 'permission denied'),
            ('authentication failed', 'database authentication failed'),
            ('out of memory', 'out of memory'),
            ('connection refused', 'connection refused'),
            ('could not connect', 'connection failed'),
            ('address already in use', 'address already in use'),
            ('no such file', 'required file or socket is missing'),
            ('no such image', 'reviewed image is missing'),
            ('does not exist', 'required object does not exist'),
        ):
            if pattern in diagnostic:
                return f'{reason} (exit {error.returncode})'
        return f'command exited with status {error.returncode}'
    if isinstance(error, OSError):
        return error.strerror or type(error).__name__
    return str(error) if type(error) in (PreflightError, RuntimeError) else type(error).__name__


def container_state(name):
    return docker('inspect', '-f', '{{.State.Status}} (exit {{.State.ExitCode}}, OOM killed: {{.State.OOMKilled}})',
                  name).decode().strip()


def wait_for_application(name, schema):
    for _ in range(40):
        try:
            docker('exec', name, 'python', '-c', READY, str(schema))
            return
        except subprocess.CalledProcessError:
            time.sleep(1)
    raise PreflightError(f'Schema {schema} health check did not succeed. Container state: {container_state(name)}.')


def inspect(*args):
    return json.loads(docker(*args))[0]


def reviewed_postgres_image(image):
    require(isinstance(image, str) and re.fullmatch(r'sha256:[a-f0-9]{64}', image),
            'The PostgreSQL container did not report a valid image ID.')
    require(image in POSTGRES_IMAGES, f'Expected the reviewed PostgreSQL 17.12 image. The container uses {image}.')
    facts = inspect('image', 'inspect', image)
    require((facts['Id'], facts['Os'], facts['Architecture']) == (image, 'linux', 'amd64'),
            'The reviewed PostgreSQL image did not resolve to the expected linux/amd64 platform.')
    return image


def current_workspace(*, for_backup=False):
    network = isolated_network()
    names = [peer['Name'] for peer in network['Containers'].values()]
    apps = [name for name in names if re.fullmatch(r'delvane-uat-[a-f0-9]{12}-restored', name)]
    require(len(apps) == 1, 'Expected the restored UAT application.')
    app, = apps
    original_pg = app.removesuffix('-restored') + '-pg'
    durable = original_pg + '-durable'
    is_durable = for_backup and set(names) in ({app, durable}, {app, original_pg, durable})
    require(is_durable or set(names) == {app, original_pg}, 'Expected only the reviewed UAT peers.')
    for name in names:
        require_private_container(inspect('container', 'inspect', name))
    previous = inspect('inspect', app)
    require(previous['Image'] in (GUEST_IMAGES if is_durable else BASE_IMAGES)
            and previous['HostConfig']['ReadonlyRootfs'], 'The app is not a reviewed UAT image.')
    source = dict(entry.split('=', 1) for entry in previous['Config']['Env'])
    require(source.get('ROSA_DEPLOYMENT_ENVIRONMENT') == 'staging'
            and source.get('ROSA_DEMO_MODE') == '0' and source.get('ROSA_SECURE_COOKIES') == '1'
            and re.fullmatch(r'delvane-uat-[a-f0-9]{12}', source.get('ROSA_DEPLOYMENT_ID', '')),
            'Unexpected UAT deployment configuration.')
    db = urlsplit(source['ROSA_DATABASE_URL'])
    require(db.scheme == 'postgresql' and db.hostname == ('guest-pg' if is_durable else 'isolated-pg')
            and db.username == 'delvane_uat' and db.port == 5432
            and db.path == '/delvane_uat_' + app.split('-')[2] + '_restored',
            'Unexpected UAT database destination.')
    pg = durable if is_durable else original_pg
    details = inspect('inspect', pg)
    if is_durable:
        require(any(m['Type'] == 'volume' and m['Destination'] == PGDATA for m in details['Mounts']),
                'The durable PostgreSQL mount is missing.')
    pg_image = reviewed_postgres_image(details['Image'])
    require(sql(pg, db.path[1:], 'SHOW data_directory') == PGDATA, 'Unexpected source data directory.')
    return app, pg, pg_image, db.path[1:], source


def isolated_network():
    require(os.geteuid() == 0 and socket.gethostname().split('.')[0] == 'delvane-test-01',
            'Run from the delvane-test-01 root console.')
    network = inspect('network', 'inspect', NETWORK)
    require(network['Driver'] == 'bridge' and network['Internal'] and not network['EnableIPv6']
            and network['Options'].get('com.docker.network.bridge.gateway_mode_ipv4') == 'isolated'
            and network['Options'].get('com.docker.network.bridge.name') == 'br-delvane-uat'
            and all(c.get('Gateway', '') in ('', 'invalid IP') for c in network['IPAM']['Config']),
            'The original isolated UAT network is required.')
    nft = subprocess.check_output(['nft', '-s', '-y', '-n', 'list', 'table', 'inet', 'delvane_uat_preflight'])
    policy = EGRESS_POLICY.read_bytes()
    require(nft.split() and b''.join(nft.split()) == b''.join(policy.split()), 'The original UAT firewall is required.')
    require(not subprocess.check_output(['ip', '-4', '-o', 'addr', 'show', 'dev', 'br-delvane-uat'])
            and not subprocess.check_output(['ip', '-6', '-o', 'addr', 'show', 'scope', 'global', 'dev', 'br-delvane-uat']),
            'Unexpected UAT bridge address.')
    return network


def require_private_container(details, *, running=True):
    host = details['HostConfig']
    require((details['State']['Running'] or not running)
            and not (host['PortBindings'] or host['PublishAllPorts'] or host['Privileged'])
            and list(details['NetworkSettings']['Networks']) == [NETWORK], 'Unexpected workload configuration.')


def sql(container, database, statement):
    try:
        return docker('exec', container, 'psql', '-X', '-U', 'postgres', '-d', database, '-v', 'ON_ERROR_STOP=1',
                      '-Atqc', statement).decode().strip()
    except subprocess.CalledProcessError as error:
        raise PreflightError(f'PostgreSQL query {statement.split()[0]} on {container}: {failure_reason(error)}.') from None


def pg_storage(pg):
    row = docker('exec', pg, 'df', '-kPT', PGDATA).decode().splitlines()[-1].split()
    return row[1], int(row[4]) * 1024


def disk_free(path):
    target = path if path.exists() else path.parent
    fs = subprocess.check_output(['stat', '-f', '-c', '%T', str(target)]).decode().strip()
    require(fs not in ('tmpfs', 'ramfs'), 'The backup and Docker storage must be disk-backed.')
    info = os.statvfs(target)
    return info.f_bavail * info.f_frsize


def storage_preflight(pg, db, *, deploy):
    source_size = int(sql(pg, db, 'SELECT pg_database_size(current_database())'))
    backup_required = max(GIB, 2 * source_size)
    require(disk_free(BACKUPS) >= backup_required, f'Backup filesystem needs at least {backup_required // MIB} MiB free.')
    require(disk_free(RECOVERY_KEYS) >= MIB, 'The recovery key filesystem is out of space.')
    if deploy:
        _, source_free = pg_storage(pg)
        require(source_free >= 64 * MIB, 'Source PostgreSQL needs at least 64 MiB free before upgrade. Take a backup first.')
        docker_root = Path(docker('info', '-f', '{{.DockerRootDir}}').decode().strip())
        required = max(4 * GIB, 3 * source_size + GIB)
        require(disk_free(docker_root) >= required and disk_free(BACKUPS) >= required,
                f'Docker and backup filesystems each need at least {required // MIB} MiB free before upgrade.')
        available = next(line.split()[1] for line in Path('/proc/meminfo').read_text().splitlines()
                         if line.startswith('MemAvailable:'))
        require(int(available) >= 512 * 1024, 'The host needs at least 512 MiB available RAM before upgrade.')
        return required


def record_counts(pg, db):
    facts = json.loads(sql(pg, db, """SELECT json_build_object(
        'schema_version', (SELECT MAX(version) FROM schema_migrations),
        'properties', (SELECT COUNT(*) FROM properties),
        'reservations', (SELECT COUNT(*) FROM reservations),
        'registrations', (SELECT COUNT(*) FROM guest_records))"""))
    require(facts['schema_version'] == 3090, 'Expected the original migration-3090 database.')
    return facts


def digest(path):
    with path.open('rb') as data:
        return hashlib.file_digest(data, 'sha256').hexdigest()


def backup(pg, db, source, counts=None, *, backups=None, recovery_keys=None):
    backups = BACKUPS if backups is None else backups
    recovery_keys = RECOVERY_KEYS if recovery_keys is None else recovery_keys
    schema = int(sql(pg, db, 'SELECT MAX(version) FROM schema_migrations'))
    require(schema in (3090, 3091), 'Unexpected schema for a UAT snapshot.')
    key = source['ROSA_ENCRYPTION_KEY']
    require(re.fullmatch(r'[A-Za-z0-9_-]{43}=', key), 'The existing UAT encryption key is invalid.')
    for directory in (backups, recovery_keys):
        directory.mkdir(mode=0o700, exist_ok=True)
        require(not directory.is_symlink() and directory.stat().st_uid == 0
                and directory.stat().st_mode & 0o077 == 0, 'Recovery storage must be root-owned and private.')
    folder = backups / (db + '-' + time.strftime('%Y%m%dT%H%M%SZ', time.gmtime()) + '-' + secrets.token_hex(4))
    folder.mkdir(mode=0o700)
    partial = folder / 'synthetic.dump.partial'
    with partial.open('xb') as dump:
        os.fchmod(dump.fileno(), 0o600)
        subprocess.run((*DOCKER, 'exec', pg, 'pg_dump', '-U', 'postgres', '-Fc', '-d', db),
                       stdout=dump, stderr=subprocess.PIPE, check=True)
        dump.flush()
        os.fsync(dump.fileno())
    with partial.open('rb') as dump:
        docker('exec', '-i', pg, 'pg_restore', '--list', stdin=dump)
    partial.rename(folder / 'synthetic.dump')
    key_path = recovery_keys / (folder.name + '.key')
    with key_path.open('x') as stream:
        key_path.chmod(0o600)
        stream.write(key + '\n')
    metadata = {'database': db, 'deployment_id': source['ROSA_DEPLOYMENT_ID'], 'schema_version': schema, 'counts': counts,
                'key_file': key_path.name, 'postgres': '17.12'}
    (folder / 'recovery.json').write_text(json.dumps(metadata, indent=2) + '\n')
    (folder / 'SHA256SUMS').write_text(''.join(f'{digest(folder / name)}  {name}\n'
                                             for name in ('synthetic.dump', 'recovery.json')))
    subprocess.check_output(['sha256sum', '-c', 'SHA256SUMS'], cwd=folder, stderr=subprocess.DEVNULL)
    print(f'Checksummed UAT snapshot saved to {folder}.', flush=True)
    return folder


def create_postgres(name, image, volume, scratch, *, memory_mib=384):
    # Keep new credentials out of the command line and out of the archived dump.
    config = scratch / 'postgres.env'
    config.write_text('POSTGRES_PASSWORD=' + secrets.token_hex(24) + '\n')
    docker('create', '--pull=never', '--name', name, '--network', NETWORK, '--network-alias', 'guest-pg',
           '--security-opt', 'no-new-privileges', '--memory', f'{memory_mib}m', '--memory-swap', f'{memory_mib}m',
           '--pids-limit', '128',
           '--dns', '127.0.0.1', '--dns-option', 'timeout:1', '--dns-option', 'attempts:1',
           '--sysctl', 'net.ipv6.conf.all.disable_ipv6=1', '--sysctl', 'net.ipv6.conf.default.disable_ipv6=1',
           '--mount', f'type=volume,src={volume},dst={PGDATA},volume-nocopy', '--env-file', str(config), image,
           '-c', 'max_connections=20', '-c', f'shared_buffers={memory_mib // 6}MB',
           '-c', f'maintenance_work_mem={memory_mib // 12}MB', '-c', 'max_wal_size=512MB')


def wait_for_postgres(pg):
    for _ in range(40):
        try:
            docker('exec', pg, 'pg_isready', '-h', '127.0.0.1', '-U', 'postgres', '-q')
        except subprocess.CalledProcessError:
            time.sleep(1)
        else:
            return
    raise PreflightError(f'New PostgreSQL did not become ready. Container state: {container_state(pg)}.')


def restore(pg, db, folder, password):
    # Database names come from the reviewed Docker container naming rule and the
    # password is random hex. Send role bootstrap SQL over stdin only.
    require(re.fullmatch(r'delvane_uat_[a-f0-9]{12}_restored', db) and re.fullmatch(r'[a-f0-9]{48}', password),
            'Invalid restore database or role configuration.')
    subprocess.check_output(['sha256sum', '-c', 'SHA256SUMS'], cwd=folder, stderr=subprocess.DEVNULL)
    bootstrap = f"""CREATE ROLE delvane_uat LOGIN PASSWORD '{password}' NOSUPERUSER NOCREATEDB NOCREATEROLE;
        CREATE DATABASE {db} OWNER delvane_uat;
        REVOKE CONNECT ON DATABASE postgres FROM PUBLIC;
        REVOKE CONNECT ON DATABASE template1 FROM PUBLIC;"""
    docker('exec', '-i', pg, 'psql', '-X', '-q', '-U', 'postgres', '-v', 'ON_ERROR_STOP=1',
           input=bootstrap.encode())
    with (folder / 'synthetic.dump').open('rb') as dump:
        docker('exec', '-i', pg, 'pg_restore', '-U', 'postgres', '--exit-on-error', '--no-owner',
               '--role=delvane_uat', '-d', db, stdin=dump)


def start_private_origin(image, *, resend_trial=False):
    origin_script = Path(__file__).with_name('run-origin.sh').resolve()
    mode = 'resend-trial' if resend_trial else 'isolated'
    subprocess.run(['systemd-run', '--unit', ORIGIN_UNIT, '--collect', '/usr/bin/bash', str(origin_script), image, mode],
                   check=True, stderr=subprocess.PIPE)
    for _ in range(30):
        if Path(ORIGIN_SOCKET).is_socket():
            break
        time.sleep(.2)
    else:
        raise PreflightError('The guest origin service did not create its Unix socket. See its root-only service status.')


def verify_private_origin(image, *, resend_trial=False):
    start_private_origin(image, resend_trial=resend_trial)
    for expected, method, path in (
        (200, 'GET', '/static/guest-checkin.css'),
        (404, 'POST', '/api/login'), (404, 'GET', '/api/reservations'),
        (404, 'GET', '/docs'), (404, 'GET', '/health/ready'),
        (404, 'GET', '/api/government/ntak'), (404, 'GET', '/api/government/viza'),
        (401, 'POST', '/api/public/guest-delivery/resend-webhook'),
    ):
        status = subprocess.check_output(['curl', '--silent', '--show-error', '--max-time', '4', '--noproxy', '*', '--unix-socket',
                                         ORIGIN_SOCKET, '--output', '/dev/null', '--write-out', '%{http_code}', '-X',
                                         method, '-H', 'X-Forwarded-Proto: https', 'http://guest.delvane.app' + path],
                                        stderr=subprocess.PIPE).decode()
        require(status == str(expected), f'{method} {path} returned HTTP {status}; expected {expected}.')
        print(f'{status} {method} {path}', flush=True)
    subprocess.run(['systemctl', 'is-active', '--quiet', ORIGIN_UNIT], check=True, stderr=subprocess.PIPE)


def write_app_config(path, db, role_password, source):
    env = {key: source[key] for key in ('ROSA_DEPLOYMENT_ID', 'ROSA_ENCRYPTION_KEY')}
    env.update(ROSA_APP_ENV='production', ROSA_DEPLOYMENT_ENVIRONMENT='staging', ROSA_AI_PROVIDER='local',
               ROSA_SECURE_COOKIES='1', ROSA_DEMO_MODE='0',
               ROSA_DATABASE_URL=f'postgresql://delvane_uat:{role_password}@guest-pg:5432/{db}?connect_timeout=3',
               DELVANE_NTAK_CREDENTIAL_ROOT='/var/lib/delvane/empty-credentials',
               DELVANE_GUEST_PUBLIC_ORIGIN='https://guest.delvane.app', DELVANE_GUEST_EMAIL_ENABLED='0')
    require(all(value and not any(char in value for char in '\r\n') for value in env.values()),
            'Invalid required UAT runtime configuration.')
    path.write_text(''.join(f'{key}={value}\n' for key, value in env.items()))


def create_app(name, image, config):
    docker('create', '--pull=never', '--name', name, '--network', NETWORK, '--read-only', '--cap-drop', 'ALL',
           '--security-opt', 'no-new-privileges', '--memory', '320m', '--memory-swap', '320m', '--pids-limit', '128',
           '--dns', '127.0.0.1', '--dns-option', 'timeout:1', '--dns-option', 'attempts:1',
           '--sysctl', 'net.ipv6.conf.all.disable_ipv6=1', '--sysctl', 'net.ipv6.conf.default.disable_ipv6=1',
           '--tmpfs', '/tmp:rw,noexec,nosuid,size=32m',
           '--tmpfs', '/var/lib/delvane:rw,noexec,nosuid,size=32m,uid=10001,gid=10001',
           '--env-file', str(config), '--entrypoint', 'uvicorn', image,
           'app:app', '--host', '127.0.0.1', '--port', '8080', '--proxy-headers',
           '--forwarded-allow-ips=127.0.0.1', '--no-access-log')


def upgrade(image, *, with_origin=False):
    app, pg, pg_image, db, source = current_workspace()
    require(re.fullmatch(r'sha256:[a-f0-9]{64}', image), 'Supply the archive-verified installed image ID.')
    candidate = inspect('image', 'inspect', image)
    require((candidate['Id'], candidate['Os'], candidate['Architecture']) == (image, 'linux', 'amd64'),
            'Unexpected installed candidate image.')
    required = storage_preflight(pg, db, deploy=True)
    role_password = secrets.token_hex(24)
    durable = pg + '-durable'
    volume = durable + '-' + secrets.token_hex(6)
    require(not Path('/run/delvane-uat-access/https.sock').exists(), 'Close the current Windows relay before upgrading.')
    old = app + '-previous'
    names = docker('ps', '-a', '--format', '{{.Names}}').decode().splitlines()
    require(old not in names and durable not in names, 'A rollback or durable container name already exists.')

    stopped = renamed = created = pg_created = origin_attempted = False
    step = 'create the disk-backed PostgreSQL volume and container'
    try:
        with tempfile.TemporaryDirectory(prefix='delvane-guest-', dir='/run') as scratch:
            work = Path(scratch)
            docker('volume', 'create', '--driver', 'local', volume)
            create_postgres(durable, pg_image, volume, work)
            pg_created = True
            docker('start', durable)
            step = 'verify disk-backed PostgreSQL readiness and storage'
            wait_for_postgres(durable)
            kind, free = pg_storage(durable)
            if kind in ('tmpfs', 'ramfs') or free < required - 128 * MIB:
                raise RuntimeError('New PostgreSQL mount fails the disk storage preflight.')
            new_pg = inspect('inspect', durable)
            if not any(m['Type'] == 'volume' and m['Name'] == volume and m['Destination'] == PGDATA
                       for m in new_pg['Mounts']):
                raise RuntimeError('New PostgreSQL mount is not the approved named volume.')
            step = 'pause the original app for a consistent snapshot'
            docker('stop', app)
            stopped = True
            step = 'take and verify the fresh schema-3090 snapshot'
            counts = record_counts(pg, db)
            folder = backup(pg, db, source, counts)
            step = 'restore the fresh snapshot into the separate disk-backed PostgreSQL'
            restore(durable, db, folder, role_password)
            if record_counts(durable, db) != counts:
                raise RuntimeError('Restored row counts differ from the frozen source.')
            print('Disk-backed restore verified on schema 3090 with matching PMS row counts.', flush=True)
            step = 'create the replacement app'
            config = work / 'runtime.env'
            write_app_config(config, db, role_password, source)
            docker('rename', app, old)
            renamed = True
            create_app(app, image, config)
            created = True
        step = 'start the replacement app and verify migration 3091'
        docker('start', app)
        wait_for_application(app, 3091)
        if with_origin:
            step = 'verify the private guest origin and its route restrictions'
            origin_attempted = True
            verify_private_origin(image)
        print('Isolated UAT app is ready on migration 3091. The previous app and database are retained.', flush=True)
    except (Exception, KeyboardInterrupt) as error:
        print(f'Upgrade failed while attempting to {step}: {failure_reason(error)}.', file=sys.stderr, flush=True)
        try:
            if origin_attempted:
                subprocess.run(['systemctl', 'stop', ORIGIN_UNIT], stderr=subprocess.DEVNULL)
            if created:
                docker('rm', '-f', app)
            if renamed:
                docker('rename', old, app)
            if stopped:
                docker('start', app)
            if pg_created:
                docker('rm', '-f', durable)
            if stopped:
                wait_for_application(app, 3090)
                print('Original app is ready again on schema 3090.', flush=True)
        except (OSError, subprocess.CalledProcessError, PreflightError) as rollback_error:
            raise SystemExit(f'Automatic rollback needs root-console attention: {failure_reason(rollback_error)} '
                             'Any volume and snapshot were retained.') from None
        raise SystemExit('Upgrade stopped. The previous app was restarted if stopped. Any new volume and backup were retained.') from None


def private_path(path, *, directory=False):
    details = path.lstat()
    expected_type = stat.S_ISDIR if directory else stat.S_ISREG
    require(expected_type(details.st_mode) and details.st_uid == 0 and details.st_mode & 0o077 == 0,
            f'{path.name} must be root-owned, private and of the expected type.')


def recovery_snapshot(deployment_id):
    folder = BACKUPS / RECOVERY_NAME
    for directory in (BACKUPS, folder, RECOVERY_KEYS):
        private_path(directory, directory=True)
    for name in ('SHA256SUMS', 'recovery.json', 'synthetic.dump'):
        private_path(folder / name)
    expected = [f'{digest(folder / name)}  {name}' for name in ('synthetic.dump', 'recovery.json')]
    require((folder / 'SHA256SUMS').read_text().splitlines() == expected,
            'The pinned snapshot does not match its checksum manifest.')
    metadata = json.loads((folder / 'recovery.json').read_text())
    key_file = RECOVERY_NAME + '.key'
    require((metadata.get('database'), metadata.get('deployment_id'), metadata.get('schema_version'),
             metadata.get('postgres'), metadata.get('key_file')) == (RECOVERY_DB, deployment_id, 3090, '17.12', key_file),
            'Snapshot metadata does not match this synthetic workspace and recovery point.')
    key_path = RECOVERY_KEYS / key_file
    private_path(key_path)
    key = key_path.read_text().strip()
    require(re.fullmatch(r'[A-Za-z0-9_-]{43}=', key), 'The recovery key has an invalid format.')
    return folder, key, metadata.get('counts')


def require_memory(minimum):
    available = next(int(line.split()[1]) // 1024 for line in Path('/proc/meminfo').read_text().splitlines()
                     if line.startswith('MemAvailable:'))
    require(available >= minimum, f'Host RAM headroom is {available} MiB; at least {minimum} MiB is required here.')


def recovery_evidence(pg):
    encrypted = sql(pg, RECOVERY_DB, """SELECT e.encrypted_snapshot FROM ntak_evidence_versions e
        JOIN ntak_jobs j ON j.id=e.job_id WHERE e.organization_id='org_uat_a' AND e.property_id='prop_uat_a'
        AND j.operation='reservation' ORDER BY e.job_id LIMIT 1""")
    require(encrypted, 'The restored synthetic NTAK evidence sample is missing.')
    return encrypted


def verify_recovery_key(image, key, encrypted):
    check = """import json, sys
from cryptography.fernet import Fernet
key, token = sys.stdin.buffer.read().splitlines()
if not json.loads(Fernet(key).decrypt(token)):
    raise SystemExit(1)
"""
    try:
        docker('run', '--rm', '--pull=never', '--network', 'none', '--read-only', '--cap-drop', 'ALL',
               '--security-opt', 'no-new-privileges', '--memory', '96m', '--memory-swap', '96m', '--pids-limit', '16',
               '--log-driver', 'none', '-i', '--entrypoint', 'python', image, '-I', '-c', check,
               input=f'{key}\n{encrypted}\n'.encode())
    except subprocess.CalledProcessError as error:
        reason = 'the recovery key could not decrypt the stored evidence' if b'InvalidToken' in error.stderr else failure_reason(error)
        raise PreflightError(f'Encrypted evidence check failed: {reason}.') from None


def recover_snapshot(image):
    deployment_id = 'delvane-uat-ed88fcdce45e'
    app, pg = deployment_id + '-restored', deployment_id + '-pg'
    old, candidate, durable = app + '-previous', app + '-recovery', pg + '-durable'
    names = {peer['Name'] for peer in isolated_network()['Containers'].values()}
    original = inspect('container', 'inspect', app)
    require_private_container(original, running=False)
    require(original['Image'] in BASE_IMAGES and original['HostConfig']['ReadonlyRootfs'],
            'The original UAT app is not the reviewed schema-3090 image.')
    require(names == ({app, pg} if original['State']['Running'] else {pg}), 'Unexpected peers on the isolated UAT network.')
    source_pg = inspect('container', 'inspect', pg)
    require_private_container(source_pg)
    pg_image = reviewed_postgres_image(source_pg['Image'])
    require(image in GUEST_IMAGES, 'The candidate is not the reviewed guest UAT image.')
    installed = inspect('image', 'inspect', image)
    require((installed['Id'], installed['Os'], installed['Architecture']) == (image, 'linux', 'amd64'),
            'Unexpected candidate image identity or platform.')
    existing = docker('ps', '-a', '--format', '{{.Names}}').decode().splitlines()
    require(not {old, candidate, durable}.intersection(existing), 'A recovery or rollback container name already exists.')
    folder, key, expected_counts = recovery_snapshot(deployment_id)
    docker_root = Path(docker('info', '-f', '{{.DockerRootDir}}').decode().strip())
    required = max(4 * GIB, 3 * (folder / 'synthetic.dump').stat().st_size + GIB)
    require(disk_free(docker_root) >= required, 'Insufficient disk space for the new PostgreSQL volume.')
    # Both apps may coexist briefly. Budget 256 MiB for PostgreSQL, 320 MiB for
    # the candidate and 128 MiB for the host. Start the checks one at a time.
    require_memory(704)
    print(f'Verified schema-3090 snapshot recovery point: {RECOVERY_POINT}.', flush=True)
    print('Later changes may be absent. The original PostgreSQL stays online and is never queried by this recovery.', flush=True)

    password = secrets.token_hex(24)
    volume = durable + '-' + secrets.token_hex(6)
    pg_created = app_created = old_stopped = old_renamed = candidate_renamed = origin_attempted = False
    step = 'create the isolated disk-backed PostgreSQL container'
    try:
        with tempfile.TemporaryDirectory(prefix='delvane-guest-recovery-', dir='/run') as scratch:
            work = Path(scratch)
            docker('volume', 'create', '--driver', 'local', volume)
            create_postgres(durable, pg_image, volume, work, memory_mib=256)
            pg_created = True
            docker('start', durable)
            wait_for_postgres(durable)
            new_pg = inspect('container', 'inspect', durable)
            require_private_container(new_pg)
            kind, free = pg_storage(durable)
            require(kind not in ('tmpfs', 'ramfs') and free >= required - 128 * MIB
                    and any(m['Type'] == 'volume' and m['Name'] == volume and m['Destination'] == PGDATA
                            for m in new_pg['Mounts']), 'The recovery PostgreSQL data mount lacks the required disk-backed volume.')
            step = 'restore and verify the pinned schema-3090 snapshot'
            restore(durable, RECOVERY_DB, folder, password)
            counts = record_counts(durable, RECOVERY_DB)
            require(expected_counts is None or counts == expected_counts, 'Restored counts differ from snapshot metadata.')
            require(sql(durable, RECOVERY_DB, 'SELECT id FROM organizations ORDER BY id').splitlines()
                    == ['org_uat_a', 'org_uat_b'], 'Unexpected tenants in the restored synthetic workspace.')
            encrypted = recovery_evidence(durable)
            verify_recovery_key(image, key, encrypted)
            print('Schema 3090, synthetic tenants and decryption of existing evidence verified on the disk-backed restore.', flush=True)
            step = 'start the isolated candidate and migrate the restored copy to 3091'
            require_memory(448)
            config = work / 'runtime.env'
            write_app_config(config, RECOVERY_DB, password, {'ROSA_DEPLOYMENT_ID': deployment_id, 'ROSA_ENCRYPTION_KEY': key})
            create_app(candidate, image, config)
            app_created = True
        docker('start', candidate)
        wait_for_application(candidate, 3091)
        require(secrets.compare_digest(encrypted, recovery_evidence(durable)), 'Migration changed the verified encrypted evidence.')
        print('Private candidate is ready on PostgreSQL schema 3091. The original app has not been switched.', flush=True)
        step = 'confirm the recovery point before cutover'
        require(input(f'Changes after {RECOVERY_POINT} may be absent. Type RESTORE to switch to this restored copy: ') == 'RESTORE',
                'Cutover was declined.')
        require(not Path('/run/delvane-uat-access/https.sock').exists(), 'Close the Windows relay before switching.')
        step = 'switch to the verified restored copy while retaining the original containers'
        if inspect('container', 'inspect', app)['State']['Running']:
            docker('stop', app)
            old_stopped = True
        docker('rename', app, old)
        old_renamed = True
        docker('rename', candidate, app)
        candidate_renamed = True
        step = 'verify the private guest socket and route isolation'
        origin_attempted = True
        verify_private_origin(image)
        original_pg = inspect('container', 'inspect', pg)
        require((original_pg['Id'], original_pg['State']['StartedAt']) == (source_pg['Id'], source_pg['State']['StartedAt']),
                'Original PostgreSQL container identity or start time changed.')
    except (Exception, KeyboardInterrupt) as error:
        print(f'Recovery stopped while attempting to {step}: {failure_reason(error)}', file=sys.stderr, flush=True)
        try:
            if origin_attempted:
                subprocess.run(['systemctl', 'stop', ORIGIN_UNIT], stderr=subprocess.DEVNULL)
            if app_created:
                docker('rm', '-f', app if candidate_renamed else candidate)
            if old_renamed:
                docker('rename', old, app)
            if old_stopped:
                docker('start', app)
            if pg_created:
                docker('rm', '-f', durable)
        except (OSError, subprocess.CalledProcessError) as rollback_error:
            raise SystemExit(f'Rollback needs root-console attention: {failure_reason(rollback_error)}') from None
        raise SystemExit('The original PostgreSQL and pinned snapshot were preserved. The new named volume was retained.') from None
    print(f'Schema 3091 is live privately on disk-backed volume {volume}. Original PostgreSQL and the backup are retained.', flush=True)


if __name__ == '__main__':
    os.umask(0o077)
    os.environ.pop('DOCKER_HOST', None)
    os.environ.pop('DOCKER_CONTEXT', None)
    try:
        require(len(sys.argv) == 2 or (len(sys.argv) == 3 and sys.argv[1] in ('--private-origin', '--recover-snapshot')),
                'Usage: upgrade-app.py --check-storage | --backup-only | [--private-origin | --recover-snapshot] <verified-image-id>')
        if sys.argv[1] in ('--check-storage', '--backup-only'):
            backup_only = sys.argv[1] == '--backup-only'
            app, pg, image, db, settings = current_workspace(for_backup=backup_only)
            storage_preflight(pg, db, deploy=not backup_only)
            if backup_only:
                print(f'Reviewed PostgreSQL 17.12 image {image} (linux/amd64).', flush=True)
                folder = backup(pg, db, settings)
                schema = json.loads((folder / 'recovery.json').read_text())['schema_version']
                try:
                    docker('exec', app, 'python', '-c', READY, str(schema))
                except subprocess.CalledProcessError:
                    raise SystemExit('Backup verified. The running app did not pass the private readiness check.') from None
                print(f'Running app passed private readiness on schema {schema}.', flush=True)
            else:
                print('UAT database storage preflight passed.')
        elif sys.argv[1] == '--recover-snapshot':
            recover_snapshot(sys.argv[-1])
        else:
            upgrade(sys.argv[-1], with_origin=sys.argv[1] == '--private-origin')
    except PreflightError as error:
        raise SystemExit(str(error)) from None
    except subprocess.CalledProcessError as error:
        args = error.cmd
        command = 'docker ' + args[3] if tuple(args[:3]) == DOCKER else args[0]
        raise SystemExit(f'UAT preflight failed during {command}: {failure_reason(error)}.') from None
    except (OSError, KeyError, ValueError) as error:
        raise SystemExit(f'UAT preflight failed: {failure_reason(error)}.') from None
