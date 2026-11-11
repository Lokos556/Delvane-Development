import json
import sys
from pathlib import Path
import sqlite3

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import app as rosa
from test_v21027 import cert_fixture


def test_certification_can_resend_unchanged_availability_when_forced(tmp_path, monkeypatch):
    client, db_file, iid, rooms, plans = cert_fixture(tmp_path, monkeypatch)
    calls = []
    monkeypatch.setattr(
        rosa,
        "_channex_request",
        lambda path, method="POST", payload=None: calls.append((path, method, payload))
        or {"data": [{"id": "task-forced"}]},
    )
    twin_id = rooms[0][0]
    response = client.put(
        f"/api/integrations/{iid}/channex/ari",
        json={
            "date_from": "2026-11-17",
            "date_to": "2026-11-17",
            "room_type_id": twin_id,
            "availability": 8,
            "force_availability": True,
        },
    )
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["queued"] == 1
    availability_calls = [x for x in calls if x[0] == "/api/v1/availability"]
    assert len(availability_calls) == 1
    assert availability_calls[0][2]["values"][0]["availability"] == 8


def test_certification_availability_delivery_returns_the_new_action_task_not_an_older_queued_job(tmp_path, monkeypatch):
    client, db_file, iid, rooms, plans = cert_fixture(tmp_path, monkeypatch)
    twin_id = rooms[0][0]
    now = rosa.now_iso()
    with sqlite3.connect(db_file) as con:
        con.execute(
            """INSERT INTO channel_ari_outbox
               (id,organization_id,integration_id,endpoint,payload_json,status,attempts,available_at,task_ids_json,last_error,created_at,sent_at)
               VALUES (?,?,?,?,?,'queued',0,?,'[]',NULL,?,NULL)""",
            ('old-cert-job','org_casa_rosa',iid,'/api/v1/availability',json.dumps({'values':[{
                'property_id':'remote-cert','room_type_id':'remote-double','date_from':'2026-11-01','date_to':'2026-11-01','availability':1
            }]}),now,now),
        )
        con.commit()

    calls=[]
    def fake_request(path, method='POST', payload=None):
        calls.append((path, payload))
        return {'data':[{'id':'task-new-twin'}]}
    monkeypatch.setattr(rosa, '_channex_request', fake_request)

    response = client.put(f'/api/integrations/{iid}/channex/ari', json={
        'date_from':'2026-11-10','date_to':'2026-11-16',
        'room_type_id':twin_id,'availability':3,'force_availability':True,
    })
    assert response.status_code == 200, response.text
    body=response.json()
    assert body['delivery']['delivered'][0]['task_ids']==['task-new-twin']
    payload=calls[0][1]
    assert payload['values'][0]['room_type_id']=='remote-twin'
    assert payload['values'][0]['date_from']=='2026-11-10'
    assert payload['values'][0]['date_to']=='2026-11-16'
    assert payload['values'][0]['availability']==3
    with sqlite3.connect(db_file) as con:
        old=con.execute("SELECT status FROM channel_ari_outbox WHERE id='old-cert-job'").fetchone()[0]
    assert old=='queued'
