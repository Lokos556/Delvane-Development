from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import runpy
import shutil
from subprocess import CalledProcessError
import sys
from types import ModuleType

from fastapi.testclient import TestClient
import pytest

import app
import uat_access
from test_flutter_reservation_reception import body, client, login


API = 'https://' + uat_access.HOST
OWNER_LOGIN = {'email': 'owner@demo.rosa', 'password': 'rosa-owner'}


def test_native_ingress_account_role_csrf_and_tenant_boundaries(client, monkeypatch):
    remote = TestClient(app.app, base_url=API)
    assert remote.get('/api/client/environment').status_code == 404
    monkeypatch.setattr(app.app.state, 'uat_accounts', {('org_casa_rosa', 'usr_owner')})
    assert remote.get('/api/reservations').status_code == 401
    assert remote.get('/api/%72eservations').status_code == 404
    assert remote.get('http://api.delvane.app/api/reservations').status_code == 404
    for path in ('/docs', '/health/workers', '/api/integrations/fictional/technical-config',
                 '/api/public/checkin/fictional', '/api/government/ntak/properties/p/jobs/j/replay'):
        assert remote.get(path).status_code == 404
        assert remote.post(path).status_code == 404
    denied = {'email': 'owner@isolation.demo', 'password': 'rosa-isolation'}
    for _ in range(5):
        assert remote.post('/api/login', json=denied).status_code == 401
    assert remote.post('/api/login', json=denied).status_code == 429

    response = remote.post('/api/login', json=OWNER_LOGIN)
    assert response.status_code == 200
    assert remote.get('/api/reservations').status_code == 200
    assert remote.post('/api/reservations', json=body()).status_code == 403
    remote.headers['X-Rosa-CSRF'] = response.json()['csrf_token']
    assert remote.post('/api/reservations', json=body()).status_code == 200
    assert remote.get('/api/properties/prop_other/overview').status_code == 404
    monkeypatch.setattr(app.app.state, 'uat_accounts', {('org_casa_rosa', 'usr_cleaner')})
    assert remote.get('/api/reservations').status_code == 401
    login(remote, 'cleaner')
    assert remote.get('/api/worker/dashboard').status_code == 200
    assert remote.post('/api/reservations', json=body()).status_code == 403


def test_native_configuration_parser_and_method_allowlist():
    assert uat_access.approved_accounts(None) == frozenset()
    assert uat_access.approved_accounts('[ ["org_one", "user_2"] ]') == {('org_one', 'user_2')}
    for raw in ('[]', '{"org":"user"}', '[["org", "bad\'sql"]]', '[["org", true]]'):
        with pytest.raises(RuntimeError, match='Invalid native UAT account allowlist'):
            uat_access.approved_accounts(raw)
    assert uat_access.route_allowed('POST', '/api/login', b'/api/login')
    assert not uat_access.route_allowed('GET', '/api/login', b'/api/login')
    assert uat_access.route_allowed('PUT', '/api/registration/records/id/workspace',
                                    b'/api/registration/records/id/workspace')
    assert not uat_access.route_allowed('PUT', '/api/registration/records/id/workspace', None)


def test_native_booking_edit_and_initial_guest_draft(client, monkeypatch):
    monkeypatch.setattr(app.app.state, 'uat_accounts', {('org_casa_rosa','usr_owner')})
    android = TestClient(app.app, base_url=API)
    windows = TestClient(app.app, base_url=API)
    login(android)
    login(windows)
    booking = body()
    created = android.post('/api/reservations', json=booking)
    assert created.status_code == 200
    rid = created.json()['id']
    base = f'/api/reservations/{rid}'
    assert windows.get(base + '/reporting-details').status_code == 200
    assert windows.get(base + '/allocations').status_code == 200
    departure = str(app.date.fromisoformat(booking['departure_date']) + app.timedelta(days=1))
    assert windows.patch(base, json={'departure_date': departure}).status_code == 200
    assert android.get(base + '/detail').json()['reservation']['departure_date'] == departure
    guests = android.get(base + '/guest-checkin-status').json()['guests']
    guest = f"/api/registration/records/{guests[1]['id']}/workspace"
    version = android.get(guest).json()['revision']
    saved = android.put(guest, json={'revision':version, 'identity':{'manual':{'csaladnev':'Fictional','utonev':'Guest Two'}}})
    assert saved.status_code == 200, saved.text
    restored = windows.get(guest).json()
    assert restored['identity']['utonev'] == 'Guest Two'
    assert not restored['can_verify'] and restored['verification']['status'] == 'needs_review'
    assert restored['readiness']['transmission_enabled'] is False


def test_native_cleaning_workspace_preserves_assignment_and_checklist(client, monkeypatch):
    monkeypatch.setattr(app.app.state, 'uat_accounts', {
        ('org_casa_rosa', 'usr_owner'), ('org_casa_rosa', 'usr_cleaner'), ('org_casa_rosa', 'usr_cleaner2'),
    })
    owner = TestClient(app.app, base_url=API)
    login(owner)
    task = owner.post('/api/work-tasks', json={
        'property_id': 'prop_flora', 'title': 'Synthetic cleaning',
        'scheduled_date': str(app.date.today()), 'assigned_to': 'usr_cleaner',
    })
    assert task.status_code == 200
    path = '/api/work-tasks/' + task.json()['id']
    assert owner.get(path).json()['can_work'] is False
    cleaner = TestClient(app.app, base_url=API)
    login(cleaner, 'cleaner')
    assert cleaner.post(path + '/start', json={}).status_code == 200
    items = cleaner.get(path).json()['checklist']
    assert items
    for item in items:
        assert cleaner.patch(f"{path}/checklist/{item['id']}", json={'completed': True}).status_code == 200
    assert cleaner.post(path + '/finish', json={'note': ''}).status_code == 200
    result = owner.get(path).json()
    assert result['status'] == 'complete' and all(item['completed'] for item in result['checklist'])
    intruder = TestClient(app.app, base_url=API)
    response = intruder.post('/api/login', json={'email': 'erika@demo.rosa', 'password': 'rosa-erika'})
    assert response.status_code == 200
    assert intruder.get(path).status_code == 404


def test_scheduler_reuses_existing_operations_and_is_restart_safe(client):
    login(client)
    booking = body()
    booking['arrival_date'] = str(app.date.today())
    booking['departure_date'] = str(app.date.today() + app.timedelta(days=1))
    result = client.post('/api/reservations', json=booking)
    assert result.status_code == 200, result.text
    rid = result.json()['id']
    with app.db() as con:
        con.execute("UPDATE automation_rules SET enabled=1,authority_mode='ask' WHERE rule_key='booking_confirmation'")
    with ThreadPoolExecutor(max_workers=2) as pool:
        list(pool.map(lambda _: app.run_scheduled_operations(), range(2)))
    app.run_scheduled_operations()
    with app.db() as con:
        rule_rows = con.execute('SELECT id FROM communication_outbox WHERE reservation_id=? AND rule_id IS NOT NULL', (rid,)).fetchall()
        work = con.execute('SELECT id FROM work_tasks WHERE previous_reservation_id=? AND status=?', (rid, 'open')).fetchall()
        assert rule_rows and len({row['id'] for row in work}) == len(work) == 1
    app.run_scheduled_operations()
    with app.db() as con:
        assert con.execute('SELECT id FROM communication_outbox WHERE reservation_id=? AND rule_id IS NOT NULL', (rid,)).fetchall() == rule_rows
        assert not con.execute('SELECT 1 FROM guest_invitation_delivery d JOIN communication_outbox o ON o.id=d.outbox_id '
                               'WHERE o.reservation_id=?', (rid,)).fetchone()


@pytest.mark.parametrize('present', (False, True))
def test_supervisor_firewall_restore_is_scoped_and_fails_closed(monkeypatch, tmp_path, present):
    deploy = Path(__file__).parents[1] / 'deploy'
    shutil.copyfile(deploy / 'permanent-uat' / 'permanent.py', tmp_path / 'permanent.py')
    for helper in ('upgrade-app.py', 'resend-trial.py', 'resend-connect.py'):
        shutil.copyfile(deploy / 'guest-uat' / helper, tmp_path / helper)
    if sys.platform == 'win32':
        monkeypatch.setitem(sys.modules, 'pwd', ModuleType('pwd'))
    supervisor = runpy.run_path(str(tmp_path / 'permanent.py'))
    ensure = supervisor['ensure_policy']
    calls = []
    policy = b'table inet delvane_test { }'

    def command(*args, **kwargs):
        calls.append((args, kwargs))
        if args[:5] == ('nft', '-s', '-y', '-n', 'list'):
            if len(calls) == 1 and not present:
                raise CalledProcessError(1, args, stderr=b'No such file or directory')
            return policy + (b' changed' if present else b'\n')

    monkeypatch.setitem(ensure.__globals__, 'command', command)
    if present:
        with pytest.raises(supervisor['shared']['PreflightError'], match='differs'):
            ensure('delvane_test', policy)
        assert len(calls) == 1
    else:
        ensure('delvane_test', policy)
        assert [args for args, _ in calls[1:3]] == [('nft', '-c', '-f', '-'), ('nft', '-f', '-')]
        assert all(kwargs['input'] == policy for _, kwargs in calls[1:3])
