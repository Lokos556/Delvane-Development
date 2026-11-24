"""Configure the existing guest UAT app without changing the database or tunnel."""

import base64
import getpass
import hmac
import http.client
import json
import os
from pathlib import Path
import pwd
import re
import runpy
import secrets
import socket
import subprocess
import sys
import tempfile
import time
from urllib.parse import urlsplit
from urllib.request import ProxyHandler, build_opener
import warnings


HERE = Path(__file__).resolve().parent
shared = runpy.run_path(str(HERE / 'upgrade-app.py'))
docker, inspect, require = (shared[name] for name in ('docker', 'inspect', 'require'))
proxy = runpy.run_path(str(HERE / 'resend-connect.py'))
HOST, PORT = proxy['HOST'], proxy['PORT']
TABLE = 'delvane_resend_egress'
PROXY_UNIT = 'delvane-resend-egress.service'
PROXY_USER = 'delvane-resend-egress'
CONNECTOR = 'delvane-guest-tunnel'
ORIGIN_UNIT = shared['ORIGIN_UNIT']
ORIGIN_SOCKET = shared['ORIGIN_SOCKET']
WEBHOOK = '/api/public/guest-delivery/resend-webhook'
ETC = Path('/etc/delvane-guest-uat')
NGINX = ETC / 'nginx.conf'
SETTINGS = ETC / 'resend-trial.json'
POLICY = ETC / 'resend-egress.policy'


def command(*args, **kwargs):
    return subprocess.check_output(args, stderr=subprocess.PIPE, **kwargs)


def private_write(path, content):
    with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as file:
        temp = Path(file.name)
        try:
            file.write(content)
            file.flush()
            temp.replace(path)
        finally:
            temp.unlink(missing_ok=True)


def masked(prompt):
    require(sys.stdin.isatty(), 'Use an interactive SSH terminal for the masked secret prompts.')
    with warnings.catch_warnings():
        warnings.simplefilter('error', getpass.GetPassWarning)
        return getpass.getpass(prompt).strip()


def trial_values():
    secret = masked('Resend webhook signing secret: ')
    mailbox = masked('Owner-controlled test email address: ')
    require(re.fullmatch(r'whsec_[A-Za-z0-9+/]+={0,2}', secret), 'The signing secret format is invalid.')
    require(len(base64.b64decode(secret[6:] + '=' * (-len(secret[6:]) % 4), validate=True)) >= 24,
            'The webhook signing secret is too short.')
    require(len(mailbox) <= 254 and re.fullmatch(r'[^\s@<>(),;:\\=]+@[a-zA-Z0-9-]+(?:\.[a-zA-Z0-9-]+)+', mailbox),
            'Enter one valid mailbox.')
    return {'RESEND_WEBHOOK_SECRET': secret, 'RESEND_TEST_RECIPIENT': mailbox}


def active_policy():
    return command('nft', '-s', '-y', '-n', 'list', 'table', 'inet', TABLE)


def install_policy():
    require(not POLICY.exists(), 'A Resend policy record already exists.')
    try:
        active_policy()
    except subprocess.CalledProcessError as error:
        require(b'No such file or directory' in (error.stderr or b''), 'Unable to verify absence of the Resend firewall table.')
    else:
        raise shared['PreflightError']('A Resend firewall table already exists.')
    try:
        user = pwd.getpwnam(PROXY_USER)
    except KeyError:
        command('useradd', '--system', '--user-group', '--no-create-home', '--shell', '/usr/sbin/nologin', PROXY_USER)
        user = pwd.getpwnam(PROXY_USER)
    require(user.pw_uid > 0 and user.pw_gid > 0 and user.pw_shell == '/usr/sbin/nologin', 'Invalid Resend proxy user.')
    addresses = sorted({proxy['public_ipv4'](item[4][0]) for item in socket.getaddrinfo(HOST, 443, socket.AF_INET,
                                                                                       socket.SOCK_STREAM)})
    require(1 <= len(addresses) <= 8, 'Unexpected DNS result for the Resend API.')
    nft = f'''table inet {TABLE} {{
        chain output {{
            type filter hook output priority -155; policy accept;
            meta skuid {user.pw_uid} ip daddr {{ {', '.join(addresses)} }} tcp dport 443 accept
            meta skuid {user.pw_uid} counter reject
        }}
    }}
    '''.encode()
    command('nft', '-c', '-f', '-', input=nft)
    command('nft', '-f', '-', input=nft)
    try:
        private_write(POLICY, json.dumps({'addresses': addresses, 'uid': user.pw_uid, 'gid': user.pw_gid,
                                         'rules': active_policy().decode()}).encode())
    except Exception:
        command('nft', 'delete', 'table', 'inet', TABLE)
        raise


def start_proxy(app):
    shared['private_path'](POLICY)
    policy = json.loads(POLICY.read_text())
    require(active_policy().split() == policy['rules'].encode().split(), 'The installed Resend firewall policy changed.')
    container = inspect('container', 'inspect', app)
    shared['require_private_container'](container)
    pid = container['State']['Pid']
    require(pid > 0, 'The app has no running process for the Resend relay.')
    source = Path(f'/proc/{pid}/ns/net')
    identity = source.stat()
    require(not os.path.samestat(identity, Path('/proc/self/ns/net').stat()), 'The app is in the host network namespace.')
    with tempfile.TemporaryDirectory(prefix='delvane-resend-netns-', dir='/run') as directory:
        pinned = Path(directory) / 'net'
        pinned.touch(mode=0o600)
        command('mount', '--bind', str(source), str(pinned))
        try:
            now = inspect('container', 'inspect', app)
            require(now['Id'] == container['Id'] and now['State']['Pid'] == pid
                    and os.path.samestat(identity, pinned.stat()) and os.path.samestat(identity, source.stat()),
                    'The app changed while pinning its network namespace.')
            command('systemd-run', '--unit', PROXY_UNIT, '--collect', '--property=Type=exec', '--property=MemoryMax=48M',
                    '--property=TasksMax=16', '--property=NoNewPrivileges=yes',
                    '--property=CapabilityBoundingSet=CAP_SYS_ADMIN CAP_SETUID CAP_SETGID', '/usr/bin/python3', '-I',
                    str(HERE / 'resend-connect.py'), str(pinned), str(policy['uid']), str(policy['gid']), *policy['addresses'])
            probe = f'import socket; socket.create_connection(("127.0.0.1", {PORT}), timeout=.5).close()'
            for _ in range(30):
                try:
                    docker('exec', app, 'python', '-I', '-c', probe)
                    break
                except subprocess.CalledProcessError:
                    time.sleep(.2)
            else:
                log = command('journalctl', '--unit', PROXY_UNIT, '-n', '15', '--no-pager', '-o', 'cat').decode(errors='replace')
                detail = next((line for line in reversed(log.splitlines()) if line.startswith(
                    ('PermissionError:', 'OSError:', 'FileNotFoundError:', 'AttributeError:', 'The Resend relay '))), '')
                raise shared['PreflightError']('The pinned relay did not open its app loopback listener.'
                                               + (f' {detail}' if detail else ''))
        finally:
            command('umount', '--', str(pinned))


def stop_proxy():
    try:
        command('systemctl', 'stop', PROXY_UNIT)
    except subprocess.CalledProcessError as error:
        if b'not loaded' not in (error.stderr or b''):
            raise


def verify_transport(app):
    deny = f'''import socket
with socket.create_connection(('127.0.0.1', {PORT}), timeout=4) as client:
    client.sendall(b'CONNECT forbidden.invalid:443 HTTP/1.1\\r\\nHost: forbidden.invalid:443\\r\\n\\r\\n')
    assert client.makefile('rb').readline() == b'HTTP/1.1 403 Forbidden\\r\\n'
'''
    tls = f'''import http.client, ssl
from contextlib import closing
with closing(http.client.HTTPSConnection('127.0.0.1', {PORT}, context=ssl.create_default_context(), timeout=8)) as verified:
    verified.set_tunnel('{HOST}', 443)
    verified.connect()
'''
    for name, check in (('forbidden CONNECT deny', deny), ('hostname-verified TLS to api.resend.com:443', tls)):
        try:
            docker('exec', app, 'python', '-I', '-c', check)
        except subprocess.CalledProcessError as error:
            raise shared['PreflightError'](f'Resend {name} check failed: {shared["failure_reason"](error)}.') from None
    print('Verified TLS to api.resend.com and rejected a forbidden CONNECT target. No email API call was made.', flush=True)


class OriginConnection(http.client.HTTPConnection):
    def connect(self):
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.settimeout(4)
        self.sock.connect(ORIGIN_SOCKET)


def verify_webhook(secret):
    key = base64.b64decode(secret[6:] + '=' * (-len(secret[6:]) % 4))
    body = b'{ "type": "delvane.setup_probe" }\n'
    event = 'msg_' + secrets.token_hex(12)
    timestamp = str(int(time.time()))
    signature = base64.b64encode(hmac.digest(key, f'{event}.{timestamp}.'.encode() + body, 'sha256')).decode()
    for data, expected in ((body, 200), (body + b' ', 401)):
        connection = OriginConnection('guest.delvane.app', timeout=4)
        try:
            connection.request('POST', WEBHOOK, data, {'X-Forwarded-Proto': 'https', 'Content-Type': 'application/json',
                               'Svix-Id': event, 'Svix-Timestamp': timestamp, 'Svix-Signature': 'v1,' + signature})
            with connection.getresponse() as response:
                require(response.status == expected, f'Synthetic webhook returned HTTP {response.status}; expected {expected}.')
        finally:
            connection.close()
    print('Signed synthetic receipt accepted; the same signature on changed bytes was rejected.', flush=True)


def wait_for_connector():
    opener = build_opener(ProxyHandler({}))
    for _ in range(30):
        try:
            with opener.open('http://127.0.0.1:19764/ready', timeout=2) as response:
                if response.status == 200:
                    return
        except OSError:
            time.sleep(1)
    raise shared['PreflightError']('The existing Cloudflare connector did not regain readiness.')


def workspace():
    app = 'delvane-uat-ed88fcdce45e-restored'
    pg = 'delvane-uat-ed88fcdce45e-pg'
    durable = pg + '-durable'
    names = {peer['Name'] for peer in shared['isolated_network']()['Containers'].values()}
    require(names in ({app, durable}, {app, durable, pg}), 'Unexpected peers on the isolated UAT network.')
    for name in names:
        shared['require_private_container'](inspect('container', 'inspect', name))
    current = inspect('container', 'inspect', app)
    image = current['Image']
    require(image in shared['GUEST_IMAGES'] and current['HostConfig']['ReadonlyRootfs'], 'The existing app image is unexpected.')
    mounted = inspect('container', 'inspect', durable)['Mounts']
    require(any(item['Type'] == 'volume' and item['Destination'] == shared['PGDATA'] for item in mounted),
            'The existing PostgreSQL mount must be a named volume.')
    settings = dict(item.split('=', 1) for item in current['Config']['Env'])
    db = urlsplit(settings['ROSA_DATABASE_URL'])
    require((db.scheme, db.hostname, db.port, db.username, db.path)
            == ('postgresql', 'guest-pg', 5432, 'delvane_uat', '/' + shared['RECOVERY_DB'])
            and settings['ROSA_DEPLOYMENT_ID'] == 'delvane-uat-ed88fcdce45e'
            and settings['ROSA_DEPLOYMENT_ENVIRONMENT'] == 'staging', 'Unexpected UAT database or deployment binding.')
    connector = inspect('container', 'inspect', CONNECTOR)
    require(connector['State']['Running'] and connector['HostConfig']['NetworkMode'] == 'host'
            and connector['Config']['Labels'].get('com.delvane.tunnel.id') == '94dab672-b04b-4fcb-83d6-ee8e1c3bdca7'
            and any(m['Source'] == ORIGIN_SOCKET and m['Destination'] == ORIGIN_SOCKET and not m['RW']
                    for m in connector['Mounts']), 'Unexpected existing Cloudflare connector or socket binding.')
    shared['wait_for_application'](app, 3091)
    return app, image, settings


def switch(action):
    app, image, env = workspace()
    current_trial = env.get('DELVANE_GUEST_EMAIL_PROVIDER') == 'resend'
    enabled = env.get('DELVANE_GUEST_EMAIL_ENABLED') == '1'
    require(not Path('/run/delvane-uat-access/https.sock').exists(), 'Close the Windows UAT relay before restarting the app.')
    shared['private_path'](NGINX)
    prior_nginx = NGINX.read_bytes()
    if action == 'configure':
        require(not (current_trial or enabled), 'Resend trial configuration is already active.')
    else:
        require(current_trial and enabled == (action == 'pause'), 'The current sending state does not match this action.')
    if action == 'arm':
        # The paused app cannot approve or lease a send while we check the queue.
        check = """import app
with app.db() as con:
    if con.execute("SELECT 1 FROM guest_invitation_delivery WHERE provider='resend' AND state IN ('queued','retry_scheduled','sending') LIMIT 1").fetchone():
        raise SystemExit(1)
"""
        try:
            docker('exec', app, 'python', '-c', check)
        except subprocess.CalledProcessError:
            raise shared['PreflightError']('The existing Resend queue could not be confirmed empty; leave sending paused.') from None

    config = {name: env[name] for name in ('ROSA_APP_ENV', 'ROSA_DEPLOYMENT_ENVIRONMENT', 'ROSA_DEPLOYMENT_ID',
              'ROSA_DATABASE_URL', 'ROSA_ENCRYPTION_KEY', 'ROSA_SECURE_COOKIES', 'ROSA_DEMO_MODE', 'ROSA_AI_PROVIDER',
              'DELVANE_NTAK_CREDENTIAL_ROOT', 'DELVANE_GUEST_PUBLIC_ORIGIN')}
    previous = app + '-before-resend-' + secrets.token_hex(4)
    stopped_connector = stopped_origin = stopped_old = renamed_old = created = new_origin = new_policy = False
    step = 'prepare the private Resend firewall'
    try:
        if action == 'configure':
            install_policy()
            new_policy = True
            step = 'verify the corrected relay on the running app without changing the website'
            try:
                start_proxy(app)
                verify_transport(app)
            finally:
                stop_proxy()
        step = 'load or save the private Resend trial settings'
        if SETTINGS.exists() or action != 'configure':
            shared['private_path'](SETTINGS)
            values = json.loads(SETTINGS.read_text())
        else:
            values = trial_values()
            private_write(SETTINGS, json.dumps(values).encode())
        required = {'RESEND_WEBHOOK_SECRET', 'RESEND_TEST_RECIPIENT'}
        require(isinstance(values, dict) and required <= values.keys() <= required | {'RESEND_API_KEY'}
                and all(isinstance(value, str) and value for value in values.values()), 'Unexpected Resend settings file.')
        if action == 'arm' and 'RESEND_API_KEY' not in values:
            key = masked('Resend API key: ')
            require(re.fullmatch(r're_[A-Za-z0-9_-]{8,200}', key), 'The API key format is invalid.')
            values['RESEND_API_KEY'] = key
            private_write(SETTINGS, json.dumps(values).encode())
        config.update(values, DELVANE_GUEST_EMAIL_PROVIDER='resend', DELVANE_GUEST_EMAIL_ENABLED='1' if action == 'arm' else '0',
                      RESEND_FROM_EMAIL='checkin@mail.delvane.app', RESEND_HTTPS_PROXY=f'http://127.0.0.1:{PORT}')
        if action != 'arm':
            config.pop('RESEND_API_KEY', None)
        step = 'pause the private origin and replace only the FastAPI container'
        docker('stop', CONNECTOR)
        stopped_connector = True
        command('systemctl', 'stop', ORIGIN_UNIT)
        stopped_origin = True
        if current_trial:
            stop_proxy()
        docker('stop', app)
        stopped_old = True
        docker('rename', app, previous)
        renamed_old = True
        with tempfile.TemporaryDirectory(dir='/run', prefix='delvane-resend-') as work:
            path = Path(work) / 'runtime.env'
            require(all('\n' not in value and '\r' not in value for value in config.values()), 'Unexpected runtime value.')
            private_write(path, ''.join(f'{name}={value}\n' for name, value in config.items()).encode())
            shared['create_app'](app, image, path)
            created = True
        docker('start', app)
        step = 'verify app readiness, private origin, and Resend transport'
        shared['wait_for_application'](app, 3091)
        start_proxy(app)
        if action != 'pause':
            verify_transport(app)
        private_write(NGINX, (HERE / 'nginx.conf').read_bytes())
        new_origin = True
        shared['verify_private_origin'](image, resend_trial=True)
        verify_webhook(values['RESEND_WEBHOOK_SECRET'])
        step = 'restart the existing Cloudflare connector against the new socket'
        docker('start', CONNECTOR)
        wait_for_connector()
    except (Exception, KeyboardInterrupt) as error:
        print(f'Resend setup failed while attempting to {step}: {shared["failure_reason"](error)}', file=sys.stderr, flush=True)
        if stopped_connector and inspect('container', 'inspect', CONNECTOR)['State']['Running']:
            docker('stop', CONNECTOR)
        if new_origin:
            subprocess.run(['systemctl', 'stop', ORIGIN_UNIT], stderr=subprocess.DEVNULL, check=False)
        if stopped_origin or new_policy:
            stop_proxy()
        if created:
            docker('rm', '-f', app)
        if renamed_old:
            docker('rename', previous, app)
        if stopped_old:
            docker('start', app)
            shared['wait_for_application'](app, 3091)
        if stopped_origin:
            private_write(NGINX, prior_nginx)
            if current_trial:
                start_proxy(app)
            shared['start_private_origin'](image, resend_trial=current_trial)
        if stopped_connector:
            docker('start', CONNECTOR)
            wait_for_connector()
        if new_policy:
            command('nft', 'delete', 'table', 'inet', TABLE)
            POLICY.unlink(missing_ok=True)
        raise SystemExit('The previous app and tunnel state were restored.') from None
    print(f'Private webhook verified and the existing connector is ready. Sending is {"armed for one mailbox" if action == "arm" else "disabled"}.')


if __name__ == '__main__':
    os.umask(0o077)
    os.environ.pop('DOCKER_CONTEXT', None)
    os.environ.pop('DOCKER_HOST', None)
    try:
        require(len(sys.argv) == 2 and sys.argv[1] in ('configure', 'arm', 'pause'), 'Use configure, arm or pause.')
        switch(sys.argv[1])
    except (Exception, KeyboardInterrupt) as error:
        raise SystemExit(f'Resend trial stopped: {shared["failure_reason"](error)}') from None
