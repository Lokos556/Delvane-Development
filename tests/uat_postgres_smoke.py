"""Run inside the candidate container on the dedicated internal-network lab only."""

from datetime import date, timedelta
from hashlib import sha256
from http.client import HTTPConnection
from http.cookies import SimpleCookie
import json
import os
from pathlib import Path
import secrets
import sys
from urllib.parse import urlsplit
from uuid import uuid4


def verify_isolation():
    if not __debug__:
        raise SystemExit('Smoke verification requires Python assertions')
    assert Path('/.dockerenv').is_file(), 'Run inside the isolated candidate container'
    url = urlsplit(os.environ['ROSA_DATABASE_URL'])
    assert (url.hostname, url.port, url.username) == ('isolated-pg', 5432, 'delvane_uat')
    assert url.path.startswith('/delvane_uat_') and '/' not in url.path[1:]
    assert os.environ['ROSA_DEPLOYMENT_ID'].startswith('delvane-uat-')
    assert os.environ['ROSA_APP_ENV'] == 'production'
    assert os.environ['ROSA_DEPLOYMENT_ENVIRONMENT'] == 'staging'
    assert os.environ['ROSA_DEMO_MODE'] == '0'
    assert os.environ['ROSA_SECURE_COOKIES'] == '1'
    assert not any(row.split()[1] == '00000000'
                   for row in Path('/proc/net/route').read_text().splitlines()[1:])
    expected_root = Path('/var/lib/delvane/empty-credentials')
    assert os.environ['DELVANE_NTAK_CREDENTIAL_ROOT'] == str(expected_root)
    assert not expected_root.exists(), 'Credential root must be absent in this lab'
    return url.path[1:]


class LocalAPI:
    def __init__(self):
        self.csrf = None
        self.session = None

    def request(self, method, path, document=None, *, status=200, csrf=True):
        connection = HTTPConnection('127.0.0.1', 8080, timeout=5)
        headers = {}
        if document is not None:
            headers['Content-Type'] = 'application/json'
        if self.session:
            headers['Cookie'] = f'rosa_session={self.session}'
        if self.csrf and csrf:
            headers['X-Rosa-CSRF'] = self.csrf
        try:
            connection.request(method, path, body=None if document is None else json.dumps(document), headers=headers)
            response = connection.getresponse()
            data = response.read()
            assert response.status == status, (method, path, response.status, status)
            result = json.loads(data)
            if path == '/api/login':
                cookie = SimpleCookie(response.getheader('Set-Cookie'))['rosa_session']
                assert cookie['secure'] and cookie['httponly']
                # The internal loopback lab has no TLS ingress. Carry only its
                # synthetic Secure cookie explicitly to exercise the real APIs.
                self.session = cookie.value
                self.csrf = result['csrf_token']
            return result, response.headers, data
        finally:
            connection.close()


def seed(app, con, password):
    assert not con.execute('SELECT 1 FROM organizations LIMIT 1').fetchone(), 'Expected a fresh lab database'
    for suffix in ('a', 'b'):
        org = f'org_uat_{suffix}'
        con.execute('INSERT INTO organizations(id,name,slug) VALUES (?,?,?)', (org, f'Synthetic UAT {suffix}', org))
        con.execute('INSERT INTO organization_settings(organization_id,created_at) VALUES (?,?)', (org, app.now_iso()))
        con.execute('''INSERT INTO users(id,organization_id,full_name,email,password_hash,role)
                       VALUES (?,?,?,?,?,'owner')''',
                    (f'owner_uat_{suffix}', org, 'Fictional operator', f'owner-{suffix}@uat.invalid', app.hash_password(password)))
    for prop, org in (('prop_uat_a', 'org_uat_a'), ('prop_uat_sibling', 'org_uat_a'), ('prop_uat_b', 'org_uat_b')):
        con.execute('INSERT INTO properties(id,organization_id,name,slug,max_guests) VALUES (?,?,?,?,?)',
                    (prop, org, prop, prop, 3))
    con.execute('''INSERT INTO room_types(id,organization_id,property_id,name,code,inventory_count,max_guests,
                   active,created_at,updated_at) VALUES ('room_uat','org_uat_a','prop_uat_a','Standard','standard',1,3,1,?,?)''',
                (app.now_iso(), app.now_iso()))


def verify_migrations(app, database, latest=3090):
    assert app.DB_BACKEND == 'postgresql'
    with app.db() as con:
        db = con.execute('''SELECT current_database() db, rolsuper, rolcreatedb, rolcreaterole,
            has_database_privilege(current_user, 'postgres', 'CONNECT') other_db FROM pg_roles
            WHERE rolname=current_user''').fetchone()
        assert db == {'db': database, 'rolsuper': False, 'rolcreatedb': False, 'rolcreaterole': False, 'other_db': False}
        versions = [row['version'] for row in con.execute('SELECT version FROM schema_migrations ORDER BY version')]
        assert versions[-1] == latest and set(range(3074, latest + 1)) <= set(versions)
        assert con.execute("SELECT ? LIKE 'Synt%' AS matches", ('Synthetic',)).fetchone()['matches']


def verify_historical_correction(api, app, reporting_base, reason, day):
    property_api = '/api/properties/prop_uat_a'
    day_url = f'{property_api}/business-days/{day}'
    api.request('PUT', f'{property_api}/business-calendar', {
        'start_date': str(day), 'automatic': False, **reason,
    })
    api.request('PUT', day_url, {'operating': False, **reason})
    api.request('POST', f'{day_url}/close', reason)
    stock = f'{property_api}/physical-units/historical-stock/room_uat'
    revision = api.request('PUT', stock, {'business_date': str(day), 'inventory_count': 1, **reason})[0]
    assert revision == {'ok': True, 'duplicate': False, 'revision': 1}
    api.request('PUT', f'{property_api}/ifa-rates', {
        'effective_from': str(day), 'tax_type': 'TETELES', 'rate': '400', **reason,
    })
    api.request('PUT', day_url, {'operating': True, **reason})
    api.request('POST', f'{day_url}/close', {'correction_reason': 'TECH_HIBA_ADATJAVITAS', **reason})
    with app.db() as con:
        snapshots = con.execute('''SELECT job_id, revision, encrypted_facts FROM daily_snapshots
                                   WHERE property_id='prop_uat_a' ORDER BY revision''').fetchall()
    first, revised = snapshots
    assert (first['revision'], revised['revision']) == (1, 2)
    assert app.decrypt_json(first['encrypted_facts'])['operating'] is False
    facts = app.decrypt_json(revised['encrypted_facts'])
    assert facts['operating'] is True
    [comparison] = facts['capacity']['aggregate_comparison']
    assert comparison['historical_stock']['revision'] == 1
    assert comparison['selling_inventory_count'] == 1
    evidence = api.request('POST', f"{reporting_base}/jobs/{revised['job_id']}/evidence-export", reason)[0]
    assert any(edge['parent_id'] == first['job_id'] and edge['child_id'] == revised['job_id']
               for edge in evidence['lineage'])
    assert evidence['attempts'] == [] and not evidence['official_acceptance_confirmed']


def main():
    database = verify_isolation()
    import app
    import ntak_reporting
    from ntak_contracts import OPERATIONS, contracts
    from viza_contracts import SCHEMA

    verify_migrations(app, database)
    assert str(SCHEMA) and contracts().keys() == OPERATIONS.keys()
    api = LocalAPI()
    assert api.request('GET', '/health/live')[0]['status'] == 'ok'
    assert api.request('GET', '/health/ready')[0] == {'status': 'ready', 'database': 'postgresql', 'schema_version': 3090}
    assert api.request('GET', '/api/client/environment')[0] == {
        'environment': 'staging', 'deployment_id': os.environ['ROSA_DEPLOYMENT_ID'], 'secure_cookies': True,
    }
    mode = sys.argv[1:]
    if mode in (['--verify-restart'], ['--verify-crash'], ['--verify-restore']):
        with app.db() as con:
            old = con.execute('''SELECT e.encrypted_snapshot,j.state,j.attempts FROM ntak_evidence_versions e
                                 JOIN ntak_jobs j ON j.id=e.job_id
                                 WHERE e.property_id='prop_uat_a' AND j.operation='reservation' ''').fetchone()
            assert old['state'] == 'blocked' and old['attempts'] == 0
            assert app.decrypt_json(old['encrypted_snapshot'])
            assert con.execute('SELECT COUNT(*) AS count FROM organizations').fetchone()['count'] == 2
            assert con.execute('SELECT COUNT(*) AS count FROM daily_snapshots').fetchone()['count'] == 2
        if mode == ['--verify-restore']:
            assert database.endswith('_restored')
            print('New database restored migration 3090, synthetic tenants and decryptable blocked evidence.')
        elif mode == ['--verify-crash']:
            print('Application crash recovery retained migration 3090 and decryptable blocked evidence.')
        else:
            print('Restart retained migration 3090, synthetic tenants and decryptable blocked evidence.')
        return
    assert not mode
    password = secrets.token_urlsafe(24)
    with app.db() as con:
        seed(app, con, password)
    api.request('POST', '/api/login', {'email': 'owner-a@uat.invalid', 'password': password})
    base = '/api/government/ntak/properties/prop_uat_a'
    config = {'enabled': True, 'environment': 'test', 'registration_id': 'MA99000001',
              'provider_vat': '12345678-1-12', 'software_id': 'FICTIONAL', 'software_version': '1.0'}
    api.request('PUT', base, config, status=403, csrf=False)
    assert api.request('PUT', base, config)[0]['transmission_enabled'] is False
    day = date.today() + timedelta(days=3)
    historical_day = date.today() - timedelta(days=2)
    unit = api.request('POST', '/api/properties/prop_uat_a/physical-units', {
        'effective_from': str(historical_day), 'room_type_id': 'room_uat', 'building': 'Synthetic building',
        'unit_number': '101', 'classification': 'STANDARD', 'single_beds': 1, 'double_beds': 1,
        'extra_beds': 0, 'reason': 'Fictional lab inventory',
    })[0]['id']
    booking = api.request('POST', '/api/reservations', {
        'guest_name': 'Synthetic UAT guest', 'property_id': 'prop_uat_a', 'room_type_id': 'room_uat',
        'source': 'Direct', 'arrival_date': str(day), 'departure_date': str(day + timedelta(days=1)),
        'total_huf': 20000, 'guest_count': 1,
        'allocations': [{'unit_id': unit, 'date_from': str(day), 'date_to': str(day + timedelta(days=1))}],
        'reporting': {
            'garantaltFoglalas': True, 'vendegKuldoOrszaga': 'HU',
            'ertekesitesiCsatorna': 'DIREKT_ONLINE', 'piaciSzegmens': 'UZLETI_EGYENI',
            'expected_guest_count': 1,
        },
    })[0]
    ntak_reporting.worker_once(app.db)
    status = api.request('GET', base)[0]
    assert not status['transmission_enabled'] and not status['officially_validated']
    assert status['certificate']['state'] == 'missing_certificate_or_key'
    [job] = status['jobs']
    assert (job['state'], job['error_code'], job['attempts']) == ('blocked', 'signature_profile_unresolved', 0)
    api.request('PUT', base, {**config, 'environment': 'production'}, status=409)
    export = f'/jobs/{job["id"]}/evidence-export'
    reason = {'reason': 'Fictional deployment smoke review'}
    replay = api.request('POST', base + f'/jobs/{job["id"]}/replay', {
        'request_id': str(uuid4()), **reason,
    }, status=409)[0]
    assert replay['detail']['code'] == 'replay_not_permitted'
    data, headers, raw = api.request('POST', base + export, reason)
    assert not data['official_acceptance_confirmed'] and not data['transmission_enabled'] and data['attempts'] == []
    assert b'Synthetic UAT guest' not in raw and b'wire_base64' not in raw
    assert headers['Cache-Control'] == 'no-store' and headers['X-Evidence-SHA256'] == sha256(raw).hexdigest()
    assert api.request('GET', f'{base}/jobs/{job["id"]}/diagnostics')[0]
    with app.db() as con:
        retained = con.execute('''SELECT e.encrypted_snapshot,j.payload_json FROM ntak_evidence_versions e
                                    JOIN ntak_jobs j ON j.id=e.job_id WHERE e.job_id=?''', (job['id'],)).fetchone()
        assert booking['id'] in retained['payload_json'] and booking['id'] not in retained['encrypted_snapshot']
    api.request('POST', base.replace('prop_uat_a', 'prop_uat_sibling') + export, reason, status=404)
    verify_historical_correction(api, app, base, reason, historical_day)
    viza = '/api/government/viza/properties/prop_uat_a'
    model = api.request('GET', viza)[0]
    assert not model['official_transmission_enabled'] and model['connection_state'] == 'not_verified'
    assert 'official_transmission_disabled' in model['security_blockers']
    foreign = LocalAPI()
    foreign.request('POST', '/api/login', {'email': 'owner-b@uat.invalid', 'password': password})
    foreign.request('POST', base + export, reason, status=404)
    foreign.request('GET', viza, status=404)
    print('PostgreSQL 3090, contract imports, fresh tenant bootstrap, scoped diagnostics and redacted evidence passed.')
    print('Secure session cookies, CSRF, scope, environment separation, missing credentials and disabled transports passed.')
    print('Historical stock correction, immutable daily snapshot lineage and denied blocked resend passed.')


if __name__ == '__main__':
    main()
