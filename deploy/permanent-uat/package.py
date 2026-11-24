"""Build the staged control bundle from an already-built application archive."""

import gzip
import hashlib
import io
import json
from pathlib import Path
import tarfile


HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
BUILD = ROOT / 'build' / 'permanent-uat'
ARCHIVE = BUILD / 'delvane-permanent-3091-local.tar.gz'
CONTROL = BUILD / 'delvane-permanent-controls.tar.gz'
INSTALL = BUILD / 'install-delvane-permanent.sh'
LEGACY = HERE.parent / 'guest-uat'
TAG = 'delvane-uat:permanent-3091-local'


def digest(data):
    return 'sha256:' + hashlib.sha256(data).hexdigest()


def read_ids():
    with tarfile.open(ARCHIVE) as archive:
        def read(name):
            with archive.extractfile(name) as file:
                return file.read()

        def oci_blob(image_id):
            data = read('blobs/' + image_id.replace(':', '/', 1))
            if digest(data) != image_id:
                raise ValueError(f'Invalid archive member digest for {image_id}.')
            return json.loads(data)

        images = json.loads(read('manifest.json'))
        image, = (image for image in images if TAG in image.get('RepoTags', []))
        config_sha = digest(read(image['Config']))
        index = json.loads(read('index.json'))
        descriptor, = (item for item in index['manifests']
                       if item.get('annotations', {}).get('io.containerd.image.name') == TAG
                       or item.get('annotations', {}).get('org.opencontainers.image.ref.name') == 'permanent-3091-local')
        manifest_id = descriptor['digest']
        manifest = oci_blob(manifest_id)
        if manifest['config']['digest'] != config_sha:
            raise ValueError('OCI and Docker manifests refer to different image configurations.')
        config = oci_blob(config_sha)
        if (config['os'], config['architecture'], config['config']['User']) != ('linux', 'amd64', '10001:10001'):
            raise ValueError('Unexpected image platform or execution user.')
        return config_sha, manifest_id


def lf(path):
    return path.read_bytes().replace(b'\r\n', b'\n')


def package():
    image_id, manifest_id = read_ids()
    controls = {name: lf(HERE / name) for name in (
        'permanent.py', 'native-api.conf', 'native-upstream.conf', 'delvane-permanent-uat.service',
        'delvane-permanent-uat-backup.service', 'delvane-permanent-uat-backup.timer',
    )}
    controls.update({name: lf(LEGACY / name) for name in ('upgrade-app.py', 'resend-trial.py', 'resend-connect.py',
                                                        'run-origin.sh', 'nginx.conf', 'connector-egress.nft')})
    controls.update({'uat_access.py': lf(ROOT / 'uat_access.py'), 'image.id': (image_id + '\n').encode(),
                     'image-manifest.id': (manifest_id + '\n').encode()})
    with (CONTROL.open('wb') as output, gzip.GzipFile(fileobj=output, mode='wb', filename='', mtime=0) as compressed,
          tarfile.open(fileobj=compressed, mode='w') as archive):
        for name, data in sorted(controls.items()):
            member = tarfile.TarInfo(name)
            member.size = len(data)
            member.mode = 0o600
            archive.addfile(member, io.BytesIO(data))
    INSTALL.write_bytes(lf(HERE / 'install.sh'))
    manifest = BUILD / 'PERMANENT-STAGE-SHA256SUMS'
    with manifest.open('w', encoding='ascii', newline='\n') as file:
        for path in (ARCHIVE, CONTROL, INSTALL):
            with path.open('rb') as payload:
                file.write(f'{hashlib.file_digest(payload, "sha256").hexdigest()}  {path.name}\n')
    print(f'Staged image config {image_id}\nStaged OCI manifest {manifest_id}')
    print(f'Stage manifest {digest(manifest.read_bytes())}')


if __name__ == '__main__':
    package()
