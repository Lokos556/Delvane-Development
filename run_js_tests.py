"""Run reviewed JS checks in a disposable, read-only Node permission sandbox.

Usage: python -B run_js_tests.py --node <absolute path to Node 20+ executable>
No application imports, operational data, network, package installs, or repo writes.
"""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parent


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--node', default=shutil.which('node'))
    args = parser.parse_args()
    if not args.node or not Path(args.node).is_file():
        parser.error('An existing Node 20+ executable is required; nothing is downloaded')
    node = str(Path(args.node).resolve())
    # This explicit source allowlist prevents copying databases, secrets, configs,
    # or arbitrary new test programs into a runnable child environment.
    names = ['test_mrz_parser.js', 'test_guest_scanner_parser.js',
             'test_v21089_hungarian_id_ocr.js', 'test_v21090_name_doc_field_extraction.js',
             'test_v21091_noisy_name_dob.js', 'test_v21092_nationality_name_fallback.js',
             'test_v21093_noise_resistance.js', 'test_v21094_name_retry.js',
             'localization_coverage.js', 'test_guest_registration_ui.js']
    failures = []
    with tempfile.TemporaryDirectory(prefix='delvane-js-tests-') as directory:
        snapshot = Path(directory)
        for relative in ['static/app.js', 'static/guest-checkin.js', 'static/guest-checkin-i18n.js',
                         'tests/js_test_guard.cjs'] + ['tests/' + name for name in names]:
            target = snapshot / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes((ROOT / relative).read_bytes())
        env = {key: value for key, value in os.environ.items()
               if key.upper() in {'SYSTEMROOT', 'WINDIR'}}
        env.update({key: directory for key in ('TEMP', 'TMP', 'HOME', 'USERPROFILE',
                                               'LOCALAPPDATA', 'APPDATA')})
        env['TZ'] = 'UTC'
        version = subprocess.run([node, '--version'], env=env, capture_output=True,
                                 text=True, check=True, timeout=10).stdout.strip()
        major = int(version.lstrip('v').split('.')[0])
        permission = '--permission' if major >= 23 else '--experimental-permission'
        for name in names:
            result = subprocess.run([
                node, permission, '--no-addons',
                '--allow-fs-read=' + directory,
                '--require', str(snapshot / 'tests/js_test_guard.cjs'),
                str(snapshot / 'tests' / name),
            ], cwd=snapshot, env=env, capture_output=True, text=True, timeout=30)
            print(('PASS' if result.returncode == 0 else 'FAIL') + ': ' + name)
            if result.returncode:
                failures.append(name)
                print(result.stdout + result.stderr)
        print(f'JavaScript files: {len(names)} executed, '
              f'{len(names) - len(failures)} passed, {len(failures)} failed, 0 skipped')
    return bool(failures)


if __name__ == '__main__':
    raise SystemExit(main())
