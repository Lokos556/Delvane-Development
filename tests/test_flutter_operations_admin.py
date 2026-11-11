"""Native port contracts against disposable SQLite with network/file guards active."""
import pytest
from fastapi.testclient import TestClient
import app


@pytest.fixture
def client(request):
    assert app.DB_PATH.resolve().is_relative_to(request.config._delvane_safety.root)
    assert not app.CHANNEX_API_KEY and not app.OPENAI_API_KEY
    app.init_db()
    with TestClient(app.app) as client:
        yield client


def login(client, role='owner'):
    email, password = {'owner': ('owner@demo.rosa', 'rosa-owner'),
                       'cleaner': ('cleaner@demo.rosa', 'rosa-cleaner'),
                       'maintenance': ('maintenance@demo.rosa', 'rosa-maintenance')}[role]
    response = client.post('/api/login', json={'email': email, 'password': password})
    assert response.status_code == 200
    client.headers['X-Rosa-CSRF'] = response.json()['csrf_token']


def test_property_overview_and_room_type_creation(client):
    login(client)
    overview = client.get('/api/properties/prop_flora/overview')
    assert overview.status_code == 200
    assert {'property', 'room_types', 'cleaning', 'same_day_turnover'} <= overview.json().keys()
    payload = {'name': 'Synthetic twin', 'code': 'native-twin', 'inventory_count': 3, 'max_guests': 2}
    made = client.post('/api/properties/prop_flora/room-types', json=payload)
    assert made.status_code == 200
    rooms = client.get('/api/properties/prop_flora/room-types').json()['room_types']
    room = next(x for x in rooms if x['id'] == made.json()['room_type_id'])
    assert room['inventory_count'] == 3 and room['max_guests'] == 2
    assert 'rate_plans' in room and 'channex_mappings' in room
    assert client.post('/api/properties/prop_flora/room-types', json=payload).status_code == 409
    assert client.post('/api/properties/prop_flora/room-types', json={**payload, 'inventory_count': 0}).status_code == 400
    assert client.post('/api/properties/prop_other/room-types', json=payload).status_code == 404


def test_cleaner_finishes_own_checklist_with_optional_note(client):
    login(client, 'cleaner')
    tasks = client.get('/api/worker/dashboard').json()['tasks']
    assert tasks
    task = next(t for t in tasks if t['status'] != 'complete')
    tid = task['id']
    assert client.post(f'/api/work-tasks/{tid}/start').status_code == 200
    checklist = client.get(f'/api/work-tasks/{tid}/checklist').json()
    for item in checklist:
        assert client.patch(f"/api/work-tasks/{tid}/checklist/{item['id']}", json={'completed': True}).status_code == 200
    assert client.post(f'/api/work-tasks/{tid}/finish', json={'note': ''}).status_code == 200
    result = next(t for t in client.get('/api/worker/dashboard').json()['tasks'] if t['id'] == tid)
    assert result['status'] == 'complete' and result['worker_note'] == ''
    assert client.post('/api/work-tasks/not-assigned/start').status_code == 404
    assert client.post('/api/work-tasks/not-assigned/finish', json={'note': 'Denied'}).status_code == 404


def test_maintenance_reporting_assignment_resolution_and_verification(client):
    login(client, 'cleaner')
    assert client.get('/api/operations/properties').status_code == 200
    assert client.get('/api/properties').status_code == 403
    made = client.post('/api/maintenance', json={'property_id': 'prop_flora', 'title': 'Synthetic tap', 'detail': 'Test only', 'severity': 'high'})
    assert made.status_code == 200
    mid = made.json()['id']
    assert client.patch(f'/api/maintenance/{mid}/status', json={'status': 'in_progress'}).status_code == 403
    login(client, 'maintenance')
    case = next(m for m in client.get('/api/maintenance').json() if m['id'] == mid)
    assert case['assigned_to'] == 'usr_maint' and case['status'] == 'assigned'
    assert client.post('/api/maintenance', json={'property_id': 'prop_flora', 'title': 'Denied'}).status_code == 403
    for status in ['in_progress', 'resolved']:
        assert client.patch(f'/api/maintenance/{mid}/status', json={'status': status}).status_code == 200
    assert client.patch(f'/api/maintenance/{mid}/status', json={'status': 'verified'}).status_code == 403
    login(client)
    assert client.patch(f'/api/maintenance/{mid}/status', json={'status': 'verified'}).status_code == 200
    case = next(m for m in client.get('/api/maintenance').json() if m['id'] == mid)
    assert case['verified_at'] and case['resolved_at']
    assert client.patch('/api/maintenance/not-in-tenant/status', json={'status': 'resolved'}).status_code == 404


@pytest.mark.parametrize('role', ['cleaner', 'maintenance'])
def test_worker_cannot_manage_accounts_stock_or_property_inventory(client, role):
    login(client, role)
    assert client.get('/api/team/overview').status_code == 403
    assert client.get('/api/security').status_code == 403
    assert client.get('/api/inventory').status_code == 403
    assert client.patch('/api/inventory/anything', json={'quantity': 4}).status_code == 403
    assert client.post('/api/team/members', json={'full_name': 'Synthetic Denied', 'email': 'denied@native.invalid', 'role': 'owner'}).status_code == 403
    assert client.post('/api/properties/prop_flora/room-types', json={'name': 'Denied'}).status_code == 403


def test_stock_knowledge_preferences_and_mode_contracts(client):
    login(client)
    item = client.get('/api/inventory').json()['items'][0]
    assert client.patch(f"/api/inventory/{item['id']}", json={'quantity': 12.5}).status_code == 200
    after = next(i for i in client.get('/api/inventory').json()['items'] if i['id'] == item['id'])
    assert after['quantity'] == 12.5 and 'estimated_need' in after
    knowledge = client.get('/api/knowledge').json()
    key = knowledge['fields'][0]['key']
    assert client.put('/api/knowledge/prop_flora', json={'entries': {key: 'Synthetic instructions'}}).status_code == 200
    assert client.get('/api/knowledge').json()['scopes']['prop_flora'][key] == 'Synthetic instructions'
    assert client.put('/api/knowledge/prop_other', json={'entries': {key: 'Denied'}}).status_code == 404
    assert client.put('/api/notifications/preferences', json={'preferences': {'maintenance_risk': False}}).status_code == 200
    assert client.get('/api/notifications/preferences').json()['maintenance_risk'] is False
    assert client.patch('/api/organization/mode', json={'mode': 'assist'}).status_code == 200
    assert client.get('/api/organization').json()['operating_mode'] == 'assist'


def test_manager_admin_permissions_and_owner_session_revoke(client):
    login(client)
    made = client.post('/api/team/members', json={'full_name': 'Native Manager', 'email': 'manager@native.invalid', 'role': 'manager'}).json()
    uid, password = made['member_id'], made['setup_password']
    result = client.post('/api/login', json={'email': 'manager@native.invalid', 'password': password})
    assert result.status_code == 200
    client.headers['X-Rosa-CSRF'] = result.json()['csrf_token']
    assert client.get('/api/team/overview').json()['can_manage'] is False
    assert client.patch(f'/api/team/members/{uid}', json={'role': 'owner'}).status_code == 403
    assert client.post(f'/api/team/members/{uid}/reset-access').status_code == 403
    assert client.post(f'/api/team/members/{uid}/revoke-sessions').status_code == 403
    assert client.patch('/api/organization/mode', json={'mode': 'autonomous'}).status_code == 403
    assert client.delete('/api/security/sessions/not-a-session').status_code == 403
    assert client.put('/api/knowledge/shared', json={'entries': {'parking': 'Synthetic manager update'}}).status_code == 200
    assert client.patch('/api/authority/send_guest_message', json={'mode': 'ask'}).status_code == 200
    stock_id = client.get('/api/inventory').json()['items'][0]['id']
    assert client.patch(f'/api/inventory/{stock_id}', json={'quantity': 1}).status_code == 200
    # Revoking the manager session invalidates its cookie, rather than hiding a button only.
    session = next(s for s in client.get('/api/security').json()['sessions'] if s['role'] == 'manager')
    manager_cookie = client.cookies.get('rosa_session')
    login(client)
    assert client.delete(f"/api/security/sessions/{session['id']}").status_code == 200
    with TestClient(app.app) as manager:
        manager.cookies.set('rosa_session', manager_cookie)
        assert manager.get('/api/me').status_code == 401
