import json
import sqlite3
from datetime import date, timedelta

from test_v21027 import cert_fixture


def test_rate_only_batch_delta_does_not_carry_stored_restrictions(tmp_path, monkeypatch):
    client, db_file, iid, rooms, plans = cert_fixture(tmp_path, monkeypatch)
    target = str(date.today() + timedelta(days=90))
    local, remote, _, _ = plans[2]
    calls = []
    monkeypatch.setattr(
        __import__('app'),
        '_channex_request',
        lambda path, method='GET', payload=None: calls.append((path, method, payload)) or {'data': [{'id': 'task-rate-only'}]},
    )
    rosa = __import__('app')
    with sqlite3.connect(db_file) as con:
        con.execute(
            """INSERT INTO channex_rate_plan_values
               (id,organization_id,integration_id,rate_plan_id,stay_date,nightly_rate_huf,
                min_stay,min_stay_arrival,min_stay_through,max_stay,stop_sell,
                closed_to_arrival,closed_to_departure,updated_at)
               VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",
            (rosa.new_id('rpv'), 'org_casa_rosa', iid, local, target,
             10000, 2, 2, 2, 14, 1, 1, 0, rosa.now_iso()),
        )

    response = client.put(
        f'/api/integrations/{iid}/channex/ari/batch',
        json={'updates': [{
            'rate_plan_id': local,
            'date_from': target,
            'date_to': target,
            'rate_huf': 312.66,
        }]},
    )
    assert response.status_code == 200, response.text
    payload = next(p for path, _, p in calls if path == '/api/v1/restrictions')
    item = payload['values'][0]
    assert item['rate_plan_id'] == remote
    assert item['rate'] == 31266
    assert item['date_from'] == target and item['date_to'] == target
    assert set(item) == {'property_id', 'rate_plan_id', 'date_from', 'date_to', 'rate'}


def test_batch_min_stay_delta_does_not_carry_rate(tmp_path, monkeypatch):
    client, db_file, iid, rooms, plans = cert_fixture(tmp_path, monkeypatch)
    target = str(date.today() + timedelta(days=91))
    local, remote, _, _ = plans[2]
    calls = []
    rosa = __import__('app')
    monkeypatch.setattr(
        rosa,
        '_channex_request',
        lambda path, method='GET', payload=None: calls.append((path, method, payload)) or {'data': [{'id': 'task-min-stay'}]},
    )
    with sqlite3.connect(db_file) as con:
        con.execute(
            """INSERT INTO channex_rate_plan_values
               (id,organization_id,integration_id,rate_plan_id,stay_date,nightly_rate_huf,
                min_stay,min_stay_arrival,min_stay_through,max_stay,stop_sell,
                closed_to_arrival,closed_to_departure,updated_at)
               VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",
            (rosa.new_id('rpv'), 'org_casa_rosa', iid, local, target,
             12345, 1, 1, 1, 0, 0, 0, 0, rosa.now_iso()),
        )

    response = client.put(
        f'/api/integrations/{iid}/channex/ari/batch',
        json={'updates': [{
            'rate_plan_id': local,
            'date_from': target,
            'date_to': target,
            'min_stay_arrival': 3,
        }]},
    )
    assert response.status_code == 200, response.text
    payload = next(p for path, _, p in calls if path == '/api/v1/restrictions')
    item = payload['values'][0]
    assert item['rate_plan_id'] == remote
    assert item['min_stay_arrival'] == 3
    assert 'rate' not in item
    assert 'min_stay_through' not in item
    assert set(item) == {'property_id', 'rate_plan_id', 'date_from', 'date_to', 'min_stay_arrival'}
