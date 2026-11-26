"""Execute the UAT V2 cutover and roll back on failed private verification."""

import getpass
import hashlib
from http.client import HTTPConnection
from http.cookies import SimpleCookie
import json
import os
from pathlib import Path
import re
import runpy
import shutil
import socket
import subprocess
import sys


STAGE = Path('/home/delvane-uat/delvane-uat-v2')
ROOT = Path('/root/delvane-uat-v2')
ARCHIVE = 'delvane-permanent-v2-3091-local.tar.gz'
RELEASE = 'replace-release.py'
EXPECTED = {
    ARCHIVE: '73d7754b939a657931ef560cd970163a20b6cb10993f91af1808fd1cd785e7d8',
    RELEASE: 'b71593cd3a9614f0ea5e59c52bd3936572c474e874f2010057bc94fe27b32d71',
}
USER = 'owner-windows@uat.invalid'


class Origin(HTTPConnection):
    def connect(self):
        self.sock = socket.socket(socket.AF_UNIX)
        self.sock.settimeout(8)
        self.sock.connect('/run/delvane-guest-uat/origin.sock')


def request(method, path, expected, *, body=None, cookie=None, csrf=None):
    headers = {'CF-Connecting-IP': '192.0.2.54', 'X-Forwarded-Proto': 'https',
               'Content-Type': 'application/json'}
    if cookie:
        headers['Cookie'] = cookie
    if csrf:
        headers['X-Rosa-CSRF'] = csrf
    connection = Origin('api.delvane.app')
    try:
        connection.request(method, path, json.dumps(body) if body else None, headers)
        result = connection.getresponse()
        if result.status != expected:
            raise RuntimeError(f'Private API check returned HTTP {result.status}; expected {expected}.')
        return json.load(result), result.getheader('Set-Cookie')
    finally:
        connection.close()


def main():
    if os.geteuid() or socket.gethostname().split('.')[0] != 'delvane-test-01':
        raise RuntimeError('Run this on delvane-test-01 as root.')
    os.umask(0o077)
    ROOT.mkdir(mode=0o700, exist_ok=True)
    op = runpy.run_path('/opt/delvane-permanent-uat/permanent.py')
    op['private_path'](ROOT, directory=True)
    for name, expected in EXPECTED.items():
        target = ROOT / name
        if not target.exists():
            with (STAGE / name).open('rb') as source, target.open('xb') as destination:
                shutil.copyfileobj(source, destination)
        op['private_path'](target)
        with target.open('rb') as source:
            if hashlib.file_digest(source, 'sha256').hexdigest() != expected:
                raise RuntimeError(f'Checksum mismatch for {name}.')
    print('Both deployment artifacts match the reviewed checksums.', flush=True)
    op['status']()
    latest = op['shared']['sql'](op['PG'], op['shared']['RECOVERY_DB'], 'SELECT MAX(version) FROM schema_migrations')
    if latest != '3091':
        raise RuntimeError('Expected PostgreSQL schema 3091 before activation.')
    foreign = op['shared']['sql'](op['PG'], op['shared']['RECOVERY_DB'],
        "SELECT count(*) FROM properties WHERE id='prop_uat_b' AND organization_id='org_uat_b'")
    if foreign != '1':
        raise RuntimeError('The foreign synthetic property required for the tenant check is unavailable.')

    login, session = request('POST', '/api/login', 200, body={
        'email': USER, 'password': getpass.getpass('Permanent UAT owner password: '),
    })
    cookie = 'rosa_session=' + SimpleCookie(session)['rosa_session'].value
    records, _ = request('GET', '/api/reservations', 200, cookie=cookie)
    booking = next((row['id'] for row in records if re.fullmatch(r'[A-Za-z0-9_-]{1,128}', row['id'])), None)
    if booking is None:
        raise RuntimeError('An existing authorized UAT reservation is needed for the reporting-details check.')
    request('GET', '/api/properties/prop_uat_b/overview', 404, cookie=cookie)
    request('GET', f'/api/reservations/{booking}/detail', 200, cookie=cookie)
    print('Existing owner access, reservation detail and tenant denial passed.', flush=True)

    command = (sys.executable, '-I', str(ROOT / RELEASE))
    subprocess.run((*command, 'apply', str(ROOT / ARCHIVE), EXPECTED[ARCHIVE]), check=True)
    try:
        expected_ids = runpy.run_path(str(ROOT / RELEASE))['archive_ids'](ROOT / ARCHIVE)
        if op['inspect']('container', 'inspect', op['APP'])['Image'] not in expected_ids:
            raise RuntimeError('The running image is not the verified V2 image.')
        op['status']()
        latest = op['shared']['sql'](op['PG'], op['shared']['RECOVERY_DB'], 'SELECT MAX(version) FROM schema_migrations')
        if latest != '3091':
            raise RuntimeError('Expected PostgreSQL schema 3091 after activation.')
        path = f'/api/reservations/{booking}/reporting-details'
        request('GET', path, 401)
        reporting, _ = request('GET', path, 200, cookie=cookie)
        if not isinstance(reporting.get('values'), dict):
            raise RuntimeError('The reporting-details response did not match its contract.')
        request('GET', '/api/properties/prop_uat_b/overview', 404, cookie=cookie)
        logs = subprocess.run((*op['shared']['DOCKER'], 'logs', op['APP']), capture_output=True, check=True)
        if re.search(rb'(?m)^\s*(?:ERROR\b|CRITICAL\b|Traceback \(most recent call last\):)', logs.stdout + logs.stderr):
            raise RuntimeError('The V2 backend logged an error. Review root-only Docker logs.')
    except Exception as error:
        print(f'Post-cutover check failed ({type(error).__name__}). Restoring the previous release.', flush=True)
        subprocess.run((*command, 'rollback'), check=True)
        raise
    print('PASS: V2 image, readiness, PostgreSQL schema 3091, authenticated reporting details, tenant denial and startup logs.')
    try:
        request('POST', '/api/logout', 200, cookie=cookie, csrf=login['csrf_token'])
    except (RuntimeError, OSError, KeyError):
        print('The temporary verification session could not be revoked. UAT V2 passed the deployment checks.')


if __name__ == '__main__':
    try:
        main()
    except (RuntimeError, OSError, subprocess.CalledProcessError) as error:
        sys.exit(str(error))
