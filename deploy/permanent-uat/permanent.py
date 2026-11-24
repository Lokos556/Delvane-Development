"""Root supervisor and reversible activation for the existing synthetic Hetzner UAT."""

import json
import os
from pathlib import Path
import re
import runpy
import shutil
import socket
import subprocess
import sys
import tempfile
import time
from urllib.parse import urlsplit


HERE = Path(__file__).resolve().parent
ETC = Path('/etc/delvane-permanent-uat')
STATE = ETC / 'deployment.json'
GUEST_ETC = Path('/etc/delvane-guest-uat')
APP = 'delvane-uat-ed88fcdce45e-restored'
PG = 'delvane-uat-ed88fcdce45e-pg-durable'
LEGACY_PG = APP.removesuffix('-restored') + '-pg'
PREVIOUS = APP + '-before-permanent'
SERVICE = 'delvane-permanent-uat.service'
TIMER = 'delvane-permanent-uat-backup.timer'
shared = runpy.run_path(str(HERE / 'upgrade-app.py'))
resend = runpy.run_path(str(HERE / 'resend-trial.py'))
docker, inspect, require, private_path = (shared[name] for name in ('docker', 'inspect', 'require', 'private_path'))
command = resend['command']
CONNECTOR = resend['CONNECTOR']
ORIGIN = shared['ORIGIN_UNIT']
ORIGIN_SOCKET = Path(shared['ORIGIN_SOCKET'])
SCHEMA = 3091


def is_active(unit):
    return subprocess.run(['systemctl', 'is-active', '--quiet', unit], check=False).returncode == 0


def running(name):
    return inspect('container', 'inspect', name)['State']['Running']


def nft_policy(table):
    return command('nft', '-s', '-y', '-n', 'list', 'table', 'inet', table)


def ensure_policy(table, expected):
    try:
        current = nft_policy(table)
    except subprocess.CalledProcessError as error:
        require(b'No such file or directory' in error.stderr, f'Could not verify the {table} firewall.')
        command('nft', '-c', '-f', '-', input=expected)
        command('nft', '-f', '-', input=expected)
        current = nft_policy(table)
    require(current.split() == expected.split(), f'The {table} firewall differs from the reviewed policy.')


def container(name, *, active=False):
    details = inspect('container', 'inspect', name)
    shared['require_private_container'](details, running=active)
    require(details['HostConfig']['RestartPolicy']['Name'] in ('', 'no'), 'Unexpected Docker restart policy.')
    return details


def validate_data_store():
    pg = container(PG)
    shared['reviewed_postgres_image'](pg['Image'])
    mount = next((m for m in pg['Mounts'] if m['Destination'] == shared['PGDATA']), None)
    require(mount and mount['Type'] == 'volume' and mount['RW'], 'The reviewed PostgreSQL data volume is required.')
    volume = inspect('volume', 'inspect', mount['Name'])
    filesystem = command('stat', '-f', '-c', '%T', volume['Mountpoint']).strip()
    require(volume['Driver'] == 'local' and not volume['Options'] and filesystem not in {b'tmpfs', b'ramfs'},
            'PostgreSQL must use a local disk-backed volume.')
    return pg


def validate_connector():
    import pwd

    details = inspect('container', 'inspect', CONNECTOR)
    config, host = details['Config'], details['HostConfig']
    account = pwd.getpwnam('delvane-guest-tunnel')
    require(host['NetworkMode'] == 'host' and host['UsernsMode'] == 'host' and host['ReadonlyRootfs']
            and not (host['Privileged'] or host['PortBindings'] or host['PublishAllPorts'])
            and host['RestartPolicy']['Name'] in ('', 'no')
            and config['User'] == f'{account.pw_uid}:{account.pw_gid}'
            and config['Labels'].get('com.delvane.tunnel.id') == '94dab672-b04b-4fcb-83d6-ee8e1c3bdca7'
            and any(m['Source'] == str(ORIGIN_SOCKET) and m['Destination'] == str(ORIGIN_SOCKET) and not m['RW']
                    for m in details['Mounts']), 'The existing locked-down Cloudflare connector is required.')
    return details


def app_settings():
    details = container(APP)
    require(details['HostConfig']['ReadonlyRootfs'], 'The application root must be read-only.')
    env = dict(entry.split('=', 1) for entry in details['Config']['Env'])
    url = urlsplit(env['ROSA_DATABASE_URL'])
    require((url.scheme, url.hostname, url.port, url.username, url.path)
            == ('postgresql', 'guest-pg', 5432, 'delvane_uat', '/' + shared['RECOVERY_DB'])
            and env.get('ROSA_DEPLOYMENT_ID') == 'delvane-uat-ed88fcdce45e'
            and env.get('ROSA_DEPLOYMENT_ENVIRONMENT') == 'staging'
            and env.get('ROSA_APP_ENV') == 'production' and env.get('ROSA_SECURE_COOKIES') == '1'
            and env.get('ROSA_DEMO_MODE') == '0', 'Unexpected UAT application binding.')
    configured = env.get('DELVANE_GUEST_EMAIL_PROVIDER') == 'resend'
    enabled = env.get('DELVANE_GUEST_EMAIL_ENABLED', '0') == '1'
    require(not enabled or (configured and env.get('RESEND_TEST_RECIPIENT') and env.get('RESEND_API_KEY')),
            'Enabled Resend requires the established test-recipient restriction.')
    return details, env, configured


def restore_firewalls(configured):
    ensure_policy('delvane_uat_preflight', shared['EGRESS_POLICY'].read_bytes())
    shared['isolated_network']()
    ensure_policy('delvane_guest_connector', (ETC / 'connector.nft').read_bytes())
    if configured:
        private_path(resend['POLICY'])
        rules = json.loads(resend['POLICY'].read_text())['rules'].encode()
        ensure_policy('delvane_resend_egress', rules)


def capture_connector_policy():
    table = 'delvane_guest_connector'
    rules = (HERE / 'connector-egress.nft').read_bytes() + (
        b'\ninsert rule inet delvane_guest_connector connector_only oifname "lo" ip daddr 127.0.0.1 '
        b'tcp sport 19764 ct state established accept\n')
    expected = command('unshare', '--net', '/bin/sh', '-ec',
                       'nft -f -; exec nft -s -y -n list table inet delvane_guest_connector', input=rules)
    require(nft_policy(table).split() == expected.split(), 'The connector firewall differs from the reviewed policy.')
    resend['private_write'](ETC / 'connector.nft', expected)


def validate_running_network():
    peers = {peer['Name'] for peer in shared['isolated_network']()['Containers'].values()}
    require(peers in ({APP, PG}, {APP, PG, LEGACY_PG}), 'Unexpected peers on the isolated UAT network.')


def stop_origin():
    if running(CONNECTOR):
        docker('stop', '-t', '10', CONNECTOR)
    if is_active(ORIGIN):
        command('systemctl', 'stop', ORIGIN)


def origin_status(host, method, path, expected, *, https=True):
    protocol = 'https' if https else 'http'
    status = command('curl', '--silent', '--show-error', '--max-time', '5', '--noproxy', '*', '--unix-socket',
                     str(ORIGIN_SOCKET), '--output', '/dev/null', '--write-out', '%{http_code}', '-X', method,
                     '-H', f'X-Forwarded-Proto: {protocol}', '-H', 'CF-Connecting-IP: 192.0.2.40', f'http://{host}{path}')
    require(status == str(expected).encode(), f'Private origin check failed for {host} {method} {path}.')


def start_origin(image, configured, *, permanent):
    require(not ORIGIN_SOCKET.exists(), 'The previous Unix origin has not stopped.')
    config = ETC / 'nginx.conf' if permanent else GUEST_ETC / 'nginx.conf'
    script = HERE / 'run-origin.sh'
    command('systemd-run', '--unit', ORIGIN, '--collect', '--property=MemoryMax=48M', '--property=TasksMax=12',
            '/usr/bin/bash', str(script), image, 'resend-trial' if configured else 'isolated', str(config))
    for _ in range(40):
        if ORIGIN_SOCKET.is_socket() and ORIGIN_SOCKET.stat().st_mode & 0o777 == 0o660:
            break
        time.sleep(.25)
    else:
        raise shared['PreflightError']('The Unix origin did not open. Check the guest-origin service journal.')
    for method, path, status in (('GET', '/static/guest-checkin.css', 200), ('GET', '/api/reservations', 404),
                                 ('POST', '/api/public/guest-delivery/resend-webhook', 401)):
        origin_status('guest.delvane.app', method, path, status)
    for path, status in (('/api/client/environment', 200 if permanent else 404),
                         ('/api/reservations', 401 if permanent else 404), ('/health/ready', 404),
                         ('/api/public/checkin/test', 404)):
        origin_status('api.delvane.app', 'GET', path, status)
    origin_status('api.delvane.app', 'GET', '/api/client/environment', 404, https=False)


def check_workers(env):
    code = ('import urllib.request; '
            'print(urllib.request.urlopen("http://127.0.0.1:8080/health/workers", timeout=2).read().decode())')
    flags = json.loads(docker('exec', APP, 'python', '-I', '-c', code))
    require(flags['operations_running'] and (env.get('DELVANE_GUEST_EMAIL_ENABLED') != '1' or flags['delivery_running']),
            'An expected background worker has no recent successful heartbeat.')


def restart_app():
    stop_origin()
    resend['stop_proxy']()
    if running(APP):
        docker('stop', '-t', '25', APP)
    docker('start', APP)


def recover(config, *, restart_unhealthy=False):
    details, env, configured = app_settings()
    require(details['Image'] == config['image'], 'The active application differs from the approved permanent image.')
    validate_data_store()
    validate_connector()
    try:
        restore_firewalls(configured)
    except (shared['PreflightError'], subprocess.CalledProcessError):
        stop_origin()
        resend['stop_proxy']()
        raise
    if not running(PG):
        docker('start', PG)
    shared['wait_for_postgres'](PG)
    if not running(APP):
        restart_app()
    try:
        shared['wait_for_application'](APP, SCHEMA)
        if restart_unhealthy:
            check_workers(env)
    except shared['PreflightError']:
        require(restart_unhealthy and shared['sql'](PG, shared['RECOVERY_DB'],
                'SELECT MAX(version) FROM schema_migrations') == str(SCHEMA), 'Application readiness or worker verification failed.')
        restart_app()
        shared['wait_for_application'](APP, SCHEMA)
    validate_running_network()
    if configured and not is_active(resend['PROXY_UNIT']):
        resend['start_proxy'](APP)
    if not is_active(ORIGIN) or not ORIGIN_SOCKET.is_socket():
        stop_origin()
        start_origin(config['image'], configured, permanent=True)
    if not running(CONNECTOR):
        docker('start', CONNECTOR)
    return env, configured


def backup(*, scheduled):
    _, env, _ = app_settings()
    validate_data_store()
    require(shutil.disk_usage('/var/lib').free >= 4 * shared['GIB'], 'Less than 4 GiB of backup disk space remains.')
    schema = shared['sql'](PG, shared['RECOVERY_DB'], 'SELECT MAX(version) FROM schema_migrations')
    require(schema == str(SCHEMA), 'Unexpected schema for the permanent UAT backup.')
    roots = {}
    if scheduled:
        for key, parent in (('backups', shared['BACKUPS']), ('recovery_keys', shared['RECOVERY_KEYS'])):
            private_path(parent, directory=True)
            roots[key] = parent / 'permanent'
    folder = shared['backup'](PG, shared['RECOVERY_DB'], env, **roots)
    if scheduled:
        previous = sorted((path for path in roots['backups'].iterdir() if not path.is_symlink()
                           and path.is_dir() and re.fullmatch(shared['RECOVERY_DB'] + r'-\d{8}T\d{6}Z-[a-f0-9]{8}', path.name)
                           and (path / 'SHA256SUMS').is_file()), reverse=True)
        for expired in previous[7:]:
            shutil.rmtree(expired)
            (roots['recovery_keys'] / (expired.name + '.key')).unlink(missing_ok=True)
    print(f'Backup verified on disk: {folder}.', flush=True)


def prepare_nginx():
    original = GUEST_ETC / 'nginx.conf'
    private_path(original)
    require(original.read_text() == (HERE / 'nginx.conf').read_text(), 'The live guest proxy differs from the reviewed configuration.')
    text = original.read_text().rstrip()
    require(text.endswith('}'), 'The existing guest Nginx configuration is incomplete.')
    resend['private_write'](ETC / 'nginx.conf', (text[:-1] + '    include /etc/delvane-permanent-uat/native-api.conf;\n}\n').encode())


def activate(allowlist):
    require(not STATE.exists() and not is_active(SERVICE), 'An activation or previous rollback is already recorded.')
    private_path(allowlist)
    # Reuse the deployed application parser without importing the full app on the host.
    policy = runpy.run_path(str(HERE / 'uat_access.py'))
    raw = allowlist.read_text().strip()
    approved = policy['approved_accounts'](raw)
    require(approved, 'A nonempty root-owned approved UAT account list is required.')
    details, env, configured = app_settings()
    require(details['Image'] in shared['GUEST_IMAGES'], 'The previous guest release is not an approved rollback image.')
    validate_data_store()
    validate_connector()
    validate_running_network()
    shared['wait_for_application'](APP, SCHEMA)
    for org, user in approved:
        count = shared['sql'](PG, shared['RECOVERY_DB'],
                              f"SELECT count(*) FROM users WHERE active=1 AND id='{user}' AND organization_id='{org}'")
        require(count == '1', 'Each approved UAT account must already exist and be active in its stated organization.')
    require(not subprocess.run([*shared['DOCKER'], 'container', 'inspect', PREVIOUS], stdout=subprocess.DEVNULL,
                               stderr=subprocess.DEVNULL).returncode == 0, 'A rollback application container already exists.')
    image = (HERE / 'image.id').read_text().strip()
    require(re.fullmatch(r'sha256:[a-f0-9]{64}', image), 'Invalid staged application image ID.')
    accepted_ids = {image, (HERE / 'image-manifest.id').read_text().strip()}
    new = inspect('image', 'inspect', 'delvane-uat:permanent-3091-local')
    require(new['Id'] in accepted_ids and new['Os'] == 'linux' and new['Architecture'] == 'amd64'
            and new['Config']['User'] == '10001:10001', 'The loaded application image differs from the reviewed archive.')
    prepare_nginx()
    capture_connector_policy()
    shared['require_memory'](256)
    restore_firewalls(configured)
    backup(scheduled=False)
    # Preserve the running application's secret configuration through a root-only
    # env file. Image defaults are kept by Docker itself.
    defaults = {item.split('=', 1)[0] for item in inspect('image', 'inspect', details['Image'])['Config']['Env']}
    updates = {key: val for key, val in env.items() if key not in defaults or key.startswith(('ROSA_', 'DELVANE_', 'RESEND_'))}
    updates.update(DELVANE_UAT_APPROVED_ACCOUNTS=json.dumps(sorted(approved), separators=(',', ':')),
                   DELVANE_BACKGROUND_OPERATIONS='1')
    require(all(not any(c in value for c in '\r\n\0') for value in updates.values()), 'A runtime setting is malformed.')
    record = {'image': new['Id'], 'previous_image': details['Image']}
    resend['private_write'](STATE, json.dumps(record).encode())
    try:
        stop_origin()
        resend['stop_proxy']()
        docker('stop', '-t', '25', APP)
        docker('rename', APP, PREVIOUS)
        # A stopped rollback container retains its exact configuration and its
        # endpoint is inactive; the new app is the only running application.
        with tempfile.TemporaryDirectory(prefix='delvane-permanent-env-', dir='/run') as directory:
            path = Path(directory) / 'app.env'
            resend['private_write'](path, ''.join(f'{key}={value}\n' for key, value in updates.items()).encode())
            shared['create_app'](APP, new['Id'], path)
        env, configured = recover(record)
        if configured:
            resend['verify_transport'](APP)
        check_workers(env)
        resend['wait_for_connector']()
        command('systemctl', 'enable', '--now', SERVICE, TIMER)
        print('Permanent UAT services are active. The native API was checked on the private socket.', flush=True)
    except Exception:
        rollback()
        raise


def optional_container(name):
    try:
        return inspect('container', 'inspect', name)
    except subprocess.CalledProcessError as error:
        require(b'No such container' in error.stderr or b'No such object' in error.stderr, 'Could not inspect rollback container.')
        return None


def rollback():
    private_path(STATE)
    record = json.loads(STATE.read_text())
    command('systemctl', 'disable', '--now', TIMER, SERVICE)
    stop_origin()
    resend['stop_proxy']()
    saved, active = optional_container(PREVIOUS), optional_container(APP)
    if saved:
        require(saved['Image'] == record['previous_image'] and not saved['State']['Running'], 'Rollback container changed.')
        if active:
            require(active['Image'] == record['image'], 'Unknown application. Rollback stopped before removal.')
            docker('rm', '-f', APP)
        docker('rename', PREVIOUS, APP)
    else:
        require(active and active['Image'] == record['previous_image'], 'The previous application cannot be identified.')
    if not running(APP):
        docker('start', APP)
    _, _, configured = app_settings()
    shared['wait_for_application'](APP, SCHEMA)
    if configured:
        resend['start_proxy'](APP)
    start_origin(record['previous_image'], configured, permanent=False)
    docker('start', CONNECTOR)
    resend['wait_for_connector']()
    STATE.unlink()
    print('Previous guest application and connector recovered on the existing database.', flush=True)


def supervise():
    private_path(STATE)
    config = json.loads(STATE.read_text())
    while True:
        memory, disk = resources()
        if memory < 128 or disk < 4:
            print(f'UAT host headroom warning: {memory} MiB RAM and {disk} GiB disk available.', flush=True)
        recover(config, restart_unhealthy=True)
        try:
            resend['wait_for_connector']()
        except shared['PreflightError']:
            if running(CONNECTOR):
                docker('stop', '-t', '10', CONNECTOR)
            raise
        for _ in range(6):
            time.sleep(10)
            if not all(running(name) for name in (APP, PG, CONNECTOR)) or not ORIGIN_SOCKET.is_socket():
                break


def resources():
    memory = next(line.split()[1] for line in Path('/proc/meminfo').read_text().splitlines()
                  if line.startswith('MemAvailable:'))
    return int(memory) // 1024, shutil.disk_usage('/var/lib').free // shared['GIB']


def status():
    details, env, _ = app_settings()
    validate_data_store()
    available_mib, disk_gib = resources()
    print(f'Host available RAM: {available_mib} MiB. Backup disk free: {disk_gib} GiB.')
    print('Application running:', details['State']['Running'])
    print('PostgreSQL running:', running(PG), 'Cloudflare running:', running(CONNECTOR))
    print('Supervisor active:', is_active(SERVICE), 'Daily backups active:', is_active(TIMER))
    if details['State']['Running']:
        shared['wait_for_application'](APP, SCHEMA)
        check_workers(env)
        print(f'Readiness, schema {SCHEMA} and expected background workers passed.')


def main(args):
    import fcntl

    os.umask(0o077)
    require(os.geteuid() == 0 and socket.gethostname().split('.')[0] == 'delvane-test-01', 'Expected the isolated UAT host as root.')
    private_path(ETC, directory=True)
    if args == ['supervise']:
        supervise()
        return
    if args == ['status']:
        status()
        return
    with (ETC / 'maintenance.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        if args == ['rollback']:
            rollback()
        elif args == ['backup']:
            backup(scheduled=True)
        elif len(args) == 2 and args[0] == 'approved-cutover':
            activate(Path(args[1]))
        else:
            raise shared['PreflightError']('Use status, supervise, backup, rollback or approved-cutover ACCOUNT_FILE.')


if __name__ == '__main__':
    try:
        main(sys.argv[1:])
    except shared['PreflightError'] as error:
        sys.exit(str(error))
    except (ValueError, OSError, KeyError, subprocess.CalledProcessError) as error:
        # A child process may include secrets in stderr. Print only the operation
        # family and return code, leaving protected service status for diagnosis.
        detail = f' ({error.cmd[0]} exit {error.returncode})' if isinstance(error, subprocess.CalledProcessError) else ''
        sys.exit(f'Permanent UAT operation failed: {type(error).__name__}{detail}.')
