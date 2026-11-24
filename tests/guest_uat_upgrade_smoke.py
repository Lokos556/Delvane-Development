"""Exercise the prepared upgrade and rollback on a fresh local Linux Docker lab."""

import base64
import importlib.util
import json
from pathlib import Path
import secrets
import subprocess
import sys
import tempfile
import time
from unittest.mock import patch
from urllib.parse import urlsplit


ROOT = Path(__file__).resolve().parents[1]
DOCKER = ('docker', '--host', 'unix:///var/run/docker.sock')
NETWORK = 'delvane-ntak-preflight'
POLICY = ROOT / 'tests' / 'uat_preflight_egress.nft'
OLD = 'sha256:08b340b1e459d2a8ecedbaa06c1317ef22c9cb2f87412dee0bfe7db07182fe35'
PG = 'sha256:39d36505873241b90584a61078c0a3af0a226a363854fcc2d722a72ce7a00500'


def run(*args, **kwargs):
    return subprocess.check_output(args, stderr=subprocess.DEVNULL, **kwargs).decode().strip()


def docker(*args, **kwargs):
    return run(*DOCKER, *args, **kwargs)


def exists(*command):
    return subprocess.run(command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0


def wait_for(*command):
    for _ in range(40):
        if exists(*command):
            return
        time.sleep(1)
    raise RuntimeError('Synthetic lab did not start.')


def main(image):
    assert not exists(*DOCKER, 'network', 'inspect', NETWORK)
    assert not exists('nft', 'list', 'table', 'inet', 'delvane_uat_preflight')
    assert not exists('ip', 'link', 'show', 'dev', 'br-delvane-uat')
    suffix = secrets.token_hex(6)
    name = 'delvane-uat-' + suffix
    pg, app = name + '-pg', name + '-restored'
    durable = pg + '-durable'
    db = 'delvane_uat_' + suffix + '_restored'
    docker('image', 'inspect', image, OLD, PG)
    role_password, pg_password = secrets.token_hex(20), secrets.token_hex(20)
    active_nft = active_network = False
    scratch = tempfile.TemporaryDirectory(prefix='guest-uat-storage-')
    work = Path(scratch.name)
    try:
        run('nft', '-f', str(POLICY))
        active_nft = True
        docker('network', 'create', '--internal', '--driver', 'bridge',
               '--opt', 'com.docker.network.bridge.gateway_mode_ipv4=isolated',
               '--opt', 'com.docker.network.bridge.name=br-delvane-uat', NETWORK)
        active_network = True
        docker('run', '-d', '--pull=never', '--name', pg, '--network', NETWORK, '--network-alias', 'isolated-pg',
               '--memory', '768m', '--tmpfs', '/var/lib/postgresql/data:rw,noexec,nosuid,size=512m',
               '-e', 'POSTGRES_PASSWORD=' + pg_password, PG)
        wait_for(*DOCKER, 'exec', pg, 'pg_isready', '-h', '127.0.0.1', '-U', 'postgres', '-q')
        docker('exec', '-i', pg, 'psql', '-q', '-U', 'postgres', '-v', 'ON_ERROR_STOP=1',
               input=(f"CREATE ROLE delvane_uat LOGIN PASSWORD '{role_password}';\n"
                      f'CREATE DATABASE {db} OWNER delvane_uat;\n').encode())
        env = {
            'ROSA_APP_ENV': 'production', 'ROSA_DEPLOYMENT_ENVIRONMENT': 'staging', 'ROSA_DEPLOYMENT_ID': name,
            'ROSA_DEMO_MODE': '0', 'ROSA_SECURE_COOKIES': '1', 'ROSA_AI_PROVIDER': 'local',
            'ROSA_DATABASE_URL': f'postgresql://delvane_uat:{role_password}@isolated-pg:5432/{db}',
            'ROSA_ENCRYPTION_KEY': base64.urlsafe_b64encode(secrets.token_bytes(32)).decode(),
        }
        env_args = [part for key, value in env.items() for part in ('-e', f'{key}={value}')]
        docker('run', '-d', '--pull=never', '--name', app, '--network', NETWORK, '--read-only', '--cap-drop', 'ALL',
               '--memory', '320m', '--tmpfs', '/tmp', '--tmpfs', '/var/lib/delvane:uid=10001,gid=10001',
               *env_args, '--entrypoint', 'uvicorn', OLD, 'app:app', '--host', '127.0.0.1', '--port', '8080', '--no-access-log')
        health = "from urllib.request import urlopen; urlopen('http://127.0.0.1:8080/health/ready', timeout=2)"
        wait_for(*DOCKER, 'exec', app, 'python', '-c', health)
        marker = "SET ROLE delvane_uat; CREATE TABLE pilot_marker (name text); INSERT INTO pilot_marker VALUES ('fictional');"
        docker('exec', pg, 'psql', '-q', '-U', 'postgres', '-d', db, '-v', 'ON_ERROR_STOP=1', '-c', marker)
        encrypted_marker = """import app
with app.db() as con:
    con.execute('CREATE TABLE pilot_encrypted(protected TEXT NOT NULL)')
    con.execute('INSERT INTO pilot_encrypted VALUES (?)', (app.encrypt_json({'guest': 'fictional'}),))
"""
        docker('exec', app, 'python', '-c', encrypted_marker)

        spec = importlib.util.spec_from_file_location('guest_upgrade', ROOT / 'deploy' / 'guest-uat' / 'upgrade-app.py')
        upgrade = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(upgrade)
        original_pg = docker('inspect', '-f', '{{.Id}}|{{.State.StartedAt}}', pg)
        original_app = docker('inspect', '-f', '{{.Id}}|{{.State.StartedAt}}', app)
        backups = work / 'backups'
        keys = work / 'keys'
        with (
            patch.object(upgrade.socket, 'gethostname', return_value='delvane-test-01'),
            patch.object(upgrade, 'EGRESS_POLICY', POLICY),
            patch.object(upgrade, 'BACKUPS', backups),
            patch.object(upgrade, 'RECOVERY_KEYS', keys),
        ):
            for limited, pattern in (
                (patch.object(upgrade, 'disk_free', return_value=2 * upgrade.GIB), 'Docker and backup'),
                (patch.object(upgrade, 'pg_storage', return_value=('tmpfs', 32 * upgrade.MIB)), 'Source PostgreSQL'),
            ):
                with limited:
                    try:
                        upgrade.upgrade(image)
                    except upgrade.PreflightError as error:
                        assert pattern in str(error)
                    else:
                        raise AssertionError('Insufficient storage was accepted')
                assert original_app == docker('inspect', '-f', '{{.Id}}|{{.State.StartedAt}}', app)
                assert not exists(*DOCKER, 'inspect', durable) and not backups.exists()
            _, source_pg, _, source_db, source_settings = upgrade.current_workspace()
            upgrade.storage_preflight(source_pg, source_db, deploy=False)
            live_backup = upgrade.backup(source_pg, source_db, source_settings)
            assert original_app == docker('inspect', '-f', '{{.Id}}|{{.State.StartedAt}}', app)
            assert run('sha256sum', '-c', str(live_backup / 'SHA256SUMS'), cwd=live_backup)
            upgrade.upgrade(image)
        assert docker('inspect', '-f', '{{.State.Running}}', app + '-previous') == 'false'
        assert original_pg == docker('inspect', '-f', '{{.Id}}|{{.State.StartedAt}}', pg)
        new = json.loads(docker('inspect', app))[0]
        variables = dict(item.split('=', 1) for item in new['Config']['Env'])
        assert variables['DELVANE_GUEST_EMAIL_ENABLED'] == '0' and 'RESEND_API_KEY' not in variables
        assert not new['HostConfig']['PortBindings'] and new['HostConfig']['ReadonlyRootfs']
        url = urlsplit(variables['ROSA_DATABASE_URL'])
        assert url.hostname == 'guest-pg' and url.path == '/' + db
        target = json.loads(docker('inspect', durable))[0]
        mounted, = [entry for entry in target['Mounts'] if entry['Destination'] == '/var/lib/postgresql/data']
        assert mounted['Type'] == 'volume' and mounted['Name'].startswith(durable + '-')
        assert list(target['NetworkSettings']['Networks']) == [NETWORK] and not target['HostConfig']['PortBindings']
        for container, version in ((pg, '3090'), (durable, '3091')):
            assert upgrade.sql(container, db, 'SELECT MAX(version) FROM schema_migrations') == version
            assert upgrade.sql(container, db, 'SELECT name FROM pilot_marker') == 'fictional'
        encrypted_check = """import app
with app.db() as con:
    row = con.execute('SELECT protected FROM pilot_encrypted').fetchone()
    assert app.decrypt_json(row['protected']) == {'guest': 'fictional'}
"""
        docker('exec', app, 'python', '-c', encrypted_check)
        final_backup, = [folder for folder in backups.iterdir() if folder != live_backup]
        metadata = json.loads((final_backup / 'recovery.json').read_text())
        assert metadata['counts']['schema_version'] == 3090
        key_file = keys / metadata['key_file']
        assert key_file.stat().st_mode & 0o777 == 0o600
        assert key_file.read_text().strip() == env['ROSA_ENCRYPTION_KEY']
        with (
            patch.object(upgrade.socket, 'gethostname', return_value='delvane-test-01'),
            patch.object(upgrade, 'EGRESS_POLICY', POLICY),
            patch.object(upgrade, 'BACKUPS', backups),
            patch.object(upgrade, 'RECOVERY_KEYS', keys),
        ):
            _, active_pg, _, active_db, active_settings = upgrade.current_workspace(for_backup=True)
            assert active_pg == durable and active_db == db
            upgraded_backup = upgrade.backup(active_pg, active_db, active_settings)
            assert json.loads((upgraded_backup / 'recovery.json').read_text())['schema_version'] == 3091
        docker('restart', durable)
        wait_for(*DOCKER, 'exec', durable, 'pg_isready', '-h', '127.0.0.1', '-U', 'postgres', '-q')
        assert upgrade.sql(durable, db, 'SELECT name FROM pilot_marker') == 'fictional'
        docker('exec', app, 'python', '-c', encrypted_check)

        recovered = db + '_recovery'
        docker('exec', durable, 'createdb', '-U', 'postgres', '-O', 'delvane_uat', recovered)
        with (final_backup / 'synthetic.dump').open('rb') as snapshot:
            docker('exec', '-i', durable, 'pg_restore', '-U', 'postgres', '--exit-on-error',
                   '--no-owner', '--role=delvane_uat', '-d', recovered, stdin=snapshot)
        assert upgrade.sql(durable, recovered, 'SELECT MAX(version) FROM schema_migrations') == '3090'
        assert upgrade.sql(durable, recovered, 'SELECT name FROM pilot_marker') == 'fictional'
        denied = """from urllib.error import HTTPError
from urllib.request import Request, urlopen
try:
    urlopen(Request('http://127.0.0.1:8080/health/ready', headers={'Host': 'guest.delvane.app'}), timeout=2)
except HTTPError as e:
    assert e.code == 404
else:
    raise SystemExit(1)
"""
        docker('exec', app, 'python', '-c', denied)
        docker('stop', app)
        docker('stop', durable)
        docker('rename', app, app + '-guest')
        docker('rename', app + '-previous', app)
        docker('start', app)
        wait_for(*DOCKER, 'exec', app, 'python', '-c', health)
        assert docker('inspect', '-f', '{{.Image}}', app) == OLD
        assert original_pg == docker('inspect', '-f', '{{.Id}}|{{.State.StartedAt}}', pg)
        print('Low-space gates, online snapshots on 3090 and 3091, encrypted data, volume restart, restore and rollback passed.')
    finally:
        subprocess.run((*DOCKER, 'rm', '-f', app, app + '-previous', app + '-guest', durable, pg),
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        for volume in docker('volume', 'ls', '--format', '{{.Name}}').splitlines():
            if volume.startswith(durable + '-'):
                docker('volume', 'rm', volume)
        if active_network:
            docker('network', 'rm', NETWORK)
        if active_nft:
            run('nft', 'delete', 'table', 'inet', 'delvane_uat_preflight')
        scratch.cleanup()


if __name__ == '__main__':
    main(sys.argv[1])
