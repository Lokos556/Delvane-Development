"""Apply or roll back a verified image on the already activated UAT supervisor."""

import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import runpy
import shutil
import socket
import subprocess
import sys
import tarfile
import tempfile


TAG = 'delvane-uat:permanent-v2-3091-local'
SAVED = Path('/etc/delvane-permanent-uat/release-rollback.json')
PREVIOUS = 'delvane-uat-ed88fcdce45e-restored-before-v2'
V3_TAG = 'delvane-uat:permanent-v3-3091-local'
V3_SAVED = SAVED.with_name('release-v3-rollback.json')
V3_PREVIOUS = 'delvane-uat-ed88fcdce45e-restored-before-v3'
V3_VERSION = '2.10.60'
ROOMS_TAG = 'delvane-uat:permanent-v3-rooms-3091-local'
ROOMS_SAVED = SAVED.with_name('release-v3-rooms-rollback.json')
ROOMS_PREVIOUS = 'delvane-uat-ed88fcdce45e-restored-before-v3-rooms'
RELEASES = {
    'v2': (TAG, SAVED, PREVIOUS, None, None),
    'v3': (V3_TAG, V3_SAVED, V3_PREVIOUS, V3_VERSION,
           '/api/reservations/v3-probe/booking-contact'),
    'v3-rooms': (ROOMS_TAG, ROOMS_SAVED, ROOMS_PREVIOUS, '2.10.61',
                 '/api/properties/v3-probe/physical-units/assignment-options'),
}


def archive_ids(archive, tag=TAG):
    with tarfile.open(archive) as data:
        def read(name):
            with data.extractfile(name) as item:
                return item.read()

        [entry] = json.loads(read('manifest.json'))
        if entry['RepoTags'] != [tag]:
            raise ValueError('Unexpected release tag.')
        [descriptor] = json.loads(read('index.json'))['manifests']
        manifest_id = descriptor['digest']
        if not re.fullmatch(r'sha256:[a-f0-9]{64}', manifest_id):
            raise ValueError('Invalid image manifest identifier.')
        blob = read('blobs/' + manifest_id.replace(':','/'))
        config = read(entry['Config'])
        config_id = 'sha256:' + hashlib.sha256(config).hexdigest()
        if ('sha256:' + hashlib.sha256(blob).hexdigest() != manifest_id
                or json.loads(blob)['config']['digest'] != config_id):
            raise ValueError('Image descriptor does not match the archive.')
        facts = json.loads(config)
        if (facts['os'], facts['architecture'], facts['config']['User']) != ('linux','amd64','10001:10001'):
            raise ValueError('Unexpected release platform or runtime user.')
        return config_id, manifest_id


def operations():
    # The already installed original controls supply the host and isolation checks.
    return runpy.run_path('/opt/delvane-permanent-uat/permanent.py')


def switch(op, config):
    env, _ = op['recover'](config)
    op['check_workers'](env)
    op['resend']['wait_for_connector']()
    op['command']('systemctl','start',op['SERVICE'],op['TIMER'])


def stop(op):
    op['command']('systemctl','stop',op['TIMER'],op['SERVICE'])
    op['stop_origin']()
    op['resend']['stop_proxy']()


def rollback(op, *, release='v2'):
    _, saved, previous, _, _ = RELEASES[release]
    op['private_path'](saved)
    record = json.loads(saved.read_text())
    app = op['APP']
    old, active = op['optional_container'](previous), op['optional_container'](app)
    docker, require = op['docker'], op['require']
    if old:
        require(old['Image'] == record['old']['image'] and not old['State']['Running'], 'Rollback image does not match.')
        if active:
            require(active['Image'] == record['new'], 'Unknown active image; stopping rollback.')
    else:
        require(active and active['Image'] == record['old']['image'], 'Previous application could not be identified.')
    stop(op)
    if old:
        if active:
            docker('rm','-f',app)
        docker('rename',previous,app)
    op['resend']['private_write'](op['STATE'],json.dumps(record['old']).encode())
    switch(op,record['old'])
    saved.unlink()
    print('Previous permanent UAT release restored on the existing database.')


def require_latest(op, release):
    names = list(RELEASES)
    for later in names[names.index(release) + 1:]:
        op['require'](not RELEASES[later][1].exists(), 'Restore the newer release before operating on this one.')


def apply(op, archive, expected, *, release='v2'):
    tag, saved, previous, version, probe = RELEASES[release]
    docker, require = op['docker'], op['require']
    require(re.fullmatch(r'[a-f0-9]{64}',expected), 'Supply the verified archive SHA-256.')
    require(not saved.exists() and not op['optional_container'](previous), 'A rollback for this release is still retained.')
    require_latest(op, release)
    require(op['is_active'](op['SERVICE']), 'Activate permanent UAT before applying this release.')
    op['private_path'](op['STATE'])
    old = json.loads(op['STATE'].read_text())
    details, env, configured = op['app_settings']()
    require(details['Image'] == old['image'], 'Active image differs from the managed release.')
    op['validate_data_store']()
    op['validate_connector']()
    op['validate_running_network']()
    op['shared']['wait_for_application'](op['APP'], op['SCHEMA'])
    op['check_workers'](env)
    op['restore_firewalls'](configured)
    op['shared']['require_memory'](256)
    with tempfile.TemporaryDirectory(dir='/root',prefix='delvane-release-') as directory:
        temp = Path(directory)
        copy = temp / 'release.tar.gz'
        shutil.copyfile(archive,copy)
        with copy.open('rb') as source:
            require(hashlib.file_digest(source,'sha256').hexdigest() == expected, 'Archive checksum differs.')
        ids = archive_ids(copy, tag)
        docker('load','-i',str(copy))
        image = op['inspect']('image','inspect',tag)['Id']
        require(image in ids and image != old['image'], 'Loaded release differs from the reviewed manifest.')
        config = {**old,'image':image}
        op['backup'](scheduled=False)
        settings = temp / 'app.env'
        defaults = {item.split('=',1)[0] for item in op['inspect']('image','inspect',old['image'])['Config']['Env']}
        updates = {key: value for key,value in env.items() if key not in defaults or key.startswith(('ROSA_','DELVANE_','RESEND_'))}
        require(all(not any(character in value for character in '\r\n\0') for value in updates.values()),
                'Existing application settings cannot be copied safely.')
        op['resend']['private_write'](settings,''.join(f'{key}={value}\n' for key,value in updates.items()).encode())
        op['resend']['private_write'](saved,json.dumps({'old':old,'new':image}).encode())
        try:
            stop(op)
            docker('stop','-t','25',op['APP'])
            docker('rename',op['APP'],previous)
            op['shared']['create_app'](op['APP'],image,settings)
            op['resend']['private_write'](op['STATE'],json.dumps(config).encode())
            switch(op,config)
            if version:
                code = ('import urllib.request; '
                        'print(urllib.request.urlopen("http://127.0.0.1:8080/health/live", timeout=3).read().decode())')
                health = json.loads(docker('exec',op['APP'],'python','-I','-c',code))
                require(health.get('version') == version, 'The active backend version does not match the release.')
                op['origin_status']('api.delvane.app','GET',probe,401)
        except Exception:
            rollback(op, release=release)
            raise
    print(f'Verified UAT {release} is active. Previous application retained for rollback.')


def main(argv):
    action, _, release = argv[0].partition('-') if argv else ('', '', '')
    release = release or 'v2'
    if release not in RELEASES:
        raise ValueError('Unknown UAT release.')
    if action == 'inspect' and len(argv) == 2:
        print(*archive_ids(argv[1], RELEASES[release][0]),sep='\n')
        return
    if os.geteuid() != 0 or socket.gethostname().split('.')[0] != 'delvane-test-01':
        raise ValueError('Run as root on the reviewed UAT host.')
    os.umask(0o077)
    op = operations()
    op['private_path'](op['ETC'], directory=True)
    with (op['ETC'] / 'maintenance.lock').open('a') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX | fcntl.LOCK_NB)
        if action == 'apply' and len(argv) == 3:
            apply(op,Path(argv[1]),argv[2],release=release)
        elif action == 'rollback' and len(argv) == 1:
            require_latest(op, release)
            rollback(op,release=release)
        else:
            raise ValueError('Use inspect-v3-rooms ARCHIVE, apply-v3-rooms ARCHIVE SHA256, or rollback-v3-rooms.')


if __name__ == '__main__':
    try:
        main(sys.argv[1:])
    except subprocess.CalledProcessError as error:
        sys.exit(f'Release operation failed in {error.cmd[0]} (status {error.returncode}).')
    except (RuntimeError, ValueError, OSError) as error:
        sys.exit(str(error))
