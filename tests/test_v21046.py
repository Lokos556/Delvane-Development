import sqlite3
from datetime import date, timedelta

from test_v21027 import cert_fixture


def test_cert_full_sync_bypasses_local_ari_throttle_and_delivers_both_calls(tmp_path, monkeypatch):
    client, db_file, iid, rooms, plans = cert_fixture(tmp_path, monkeypatch)
    calls = []
    rosa = __import__('app')
    monkeypatch.setattr(rosa, '_ari_endpoint_throttled', lambda *args, **kwargs: True)
    monkeypatch.setattr(
        rosa,
        '_channex_request',
        lambda path, method='GET', payload=None: calls.append((path, payload)) or {'data': [{'id': f'task-{len(calls)}'}]},
    )

    response = client.post(f'/api/integrations/{iid}/channex/full-sync')
    assert response.status_code == 200, response.text
    assert {path for path, _ in calls} == {'/api/v1/availability', '/api/v1/restrictions'}
    assert len(response.json()['delivery']['delivered']) == 2
    availability_payload=next(payload for path,payload in calls if path == '/api/v1/availability')
    assert {x['room_type_id'] for x in availability_payload['values']} == {'remote-twin', 'remote-double'}


def test_cert_restriction_batch_bypasses_local_ari_throttle_and_keeps_delta_only(tmp_path, monkeypatch):
    client, db_file, iid, rooms, plans = cert_fixture(tmp_path, monkeypatch)
    rosa = __import__('app')
    monkeypatch.setattr(rosa, '_ari_endpoint_throttled', lambda *args, **kwargs: True)
    calls = []
    monkeypatch.setattr(
        rosa,
        '_channex_request',
        lambda path, method='GET', payload=None: calls.append((path, payload)) or {'data': [{'id': 'task-min-stay'}]},
    )

    target = str(date.today() + timedelta(days=91))
    updates = [
        {'rate_plan_id': plans[0][0], 'date_from': target, 'date_to': target, 'min_stay_arrival': 3},
        {'rate_plan_id': plans[2][0], 'date_from': str(date.fromisoformat(target) + timedelta(days=2)), 'date_to': str(date.fromisoformat(target) + timedelta(days=2)), 'stop_sell': True},
        {'rate_plan_id': plans[3][0], 'date_from': str(date.fromisoformat(target) + timedelta(days=4)), 'date_to': str(date.fromisoformat(target) + timedelta(days=4)), 'min_stay_arrival': 5},
    ]
    response = client.put(f'/api/integrations/{iid}/channex/ari/batch', json={'updates': updates})
    assert response.status_code == 200, response.text
    assert len(calls) == 1
    values = calls[0][1]['values']
    assert len(values) == 3
    assert response.json()['delivery']['delivered'][0]['task_ids'] == ['task-min-stay']
    by_plan={v['rate_plan_id']:v for v in values}
    assert by_plan[plans[0][1]]['min_stay_arrival'] == 3 and 'rate' not in by_plan[plans[0][1]]
    assert by_plan[plans[2][1]]['stop_sell'] == 1 and 'rate' not in by_plan[plans[2][1]]
    assert by_plan[plans[3][1]]['min_stay_arrival'] == 5 and 'rate' not in by_plan[plans[3][1]]
