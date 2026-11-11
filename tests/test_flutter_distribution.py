"""Flutter wire contracts under the root temporary-database/network guard."""
from datetime import timedelta
import pytest
import app
from test_v21027 import cert_fixture


def test_decimal_string_wire_value_has_exact_provider_minor_units(tmp_path, monkeypatch, request):
    client, db_file, iid, rooms, plans = cert_fixture(tmp_path, monkeypatch)
    assert db_file.resolve().is_relative_to(request.config._delvane_safety.root)
    calls = []
    monkeypatch.setattr(app, '_channex_request', lambda path, method='GET', payload=None:
                        calls.append((path, payload)) or {'data': [{'id': 'synthetic-task'}]})
    day = str(app.date.today() + timedelta(days=100))
    response = client.put(f'/api/integrations/{iid}/channex/ari', json={
        'date_from': day, 'date_to': day, 'rate_plan_id': plans[0][0],
        'rate_huf': '100.29', 'availability': None, 'stop_sell': False,
        'min_stay_arrival': None, 'closed_to_arrival': None, 'closed_to_departure': None,
    })
    assert response.status_code == 200
    restrictions = next(payload for path, payload in calls if path.endswith('restrictions'))
    assert restrictions['values'][0]['rate'] == 10029
    assert restrictions['values'][0]['stop_sell'] is False
    queue = client.get(f'/api/integrations/{iid}/channex/outbox').json()
    assert 'items' in queue
    assert all('payload_json' not in item for item in queue['items'])


def test_unconfigured_inventory_read_never_calls_a_provider(tmp_path, monkeypatch):
    client, _, iid, _, _ = cert_fixture(tmp_path, monkeypatch)
    monkeypatch.setattr(app, 'CHANNEX_API_KEY', '')
    calls = []
    monkeypatch.setattr(app, '_channex_request', lambda *args, **kwargs: calls.append(args))
    assert client.get(f'/api/integrations/{iid}/channex/inventory-mapping').status_code == 503
    assert not calls


@pytest.mark.parametrize('role', ['cleaner', 'maintenance'])
def test_worker_distribution_permissions_are_enforced_before_provider_access(tmp_path, monkeypatch, role):
    client, _, iid, _, _ = cert_fixture(tmp_path, monkeypatch)
    calls = []
    monkeypatch.setattr(app, '_channex_request', lambda *args, **kwargs: calls.append(args))
    result = client.post('/api/login', json={'email': f'{role}@demo.rosa', 'password': f'rosa-{role}'})
    assert result.status_code == 200
    client.headers['X-Rosa-CSRF'] = result.json()['csrf_token']
    for suffix in ['/channex/inventory-mapping', '/channex/outbox', '/channex/rate-mappings']:
        assert client.get(f'/api/integrations/{iid}{suffix}').status_code == 403
    assert client.post(f'/api/integrations/{iid}/channex/full-sync').status_code == 403
    assert client.post(f'/api/integrations/{iid}/channex/outbox/retry').status_code == 403
    day = str(app.date.today() + timedelta(days=100))
    assert client.put(f'/api/integrations/{iid}/channex/ari', json={'date_from': day, 'date_to': day, 'rate_huf': '100.29'}).status_code == 403
    assert not calls


def test_native_rate_plan_and_guest_preference_contracts(tmp_path, monkeypatch):
    client, _, iid, rooms, _ = cert_fixture(tmp_path, monkeypatch)
    with app.db() as con:
        pid = con.execute('SELECT property_id FROM integrations WHERE id=?', (iid,)).fetchone()['property_id']
        guest = con.execute("SELECT id FROM guests WHERE organization_id='org_casa_rosa' LIMIT 1").fetchone()['id']
    made = client.post(f'/api/properties/{pid}/rate-plans', json={
        'room_type_id': rooms[1][0], 'name': 'Synthetic native plan', 'code': 'native-plan',
        'meal_type': 'none', 'cancellation_policy': 'flexible', 'base_rate_huf': 9007199254740993,
    })
    assert made.status_code == 200
    plans = client.get(f'/api/properties/{pid}/rate-plans').json()['rate_plans']
    plan = next(p for p in plans if p['id'] == made.json()['rate_plan_id'])
    assert plan['room_type_id'] == rooms[1][0] and plan['base_rate_huf'] == 9007199254740993
    assert client.post(f'/api/guests/{guest}/preferences', json={'preference_key': 'Pillow preference', 'preference_value': 'Extra pillow'}).status_code == 200
    preferences = client.get(f'/api/guests/{guest}').json()['preferences']
    assert any(p['preference_key'] == 'pillow_preference' and p['preference_value'] == 'Extra pillow' for p in preferences)
