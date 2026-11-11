import sqlite3
import json
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import app as rosa
from test_v21027 import cert_fixture


def test_reservation_move_merges_old_and_new_availability_in_one_request(tmp_path, monkeypatch):
    client, db_file, iid, rooms, plans = cert_fixture(tmp_path, monkeypatch)
    calls=[]
    monkeypatch.setattr(rosa, '_channex_request', lambda path, method='POST', payload=None: calls.append((path,payload)) or {'data':[{'id':f'task-{len(calls)}'}]})
    room_id=rooms[1][0]
    with sqlite3.connect(db_file) as con:
        prop_id=con.execute('SELECT property_id FROM room_types WHERE id=?',(room_id,)).fetchone()[0]
    body={
        'property_id':prop_id,'room_type_id':room_id,'source':'Direct','guest_name':'Move Test',
        'arrival_date':'2026-11-25','departure_date':'2026-11-26','guest_count':1,
        'total_huf':100,'payment_status':'unknown','registration_status':'incomplete',
        'arrival_time':None,'special_requests':[]
    }
    r=client.post('/api/reservations',json=body)
    assert r.status_code==200,r.text
    rid=r.json()['id']
    calls.clear()

    r=client.patch(f'/api/reservations/{rid}',json={'arrival_date':'2026-11-27','departure_date':'2026-11-28'})
    assert r.status_code==200,r.text
    availability=[payload for path,payload in calls if path=='/api/v1/availability']
    assert len(availability)==1
    values=availability[0]['values']
    assert {v['date_from'] for v in values}=={'2026-11-25','2026-11-27'}
    by_date={v['date_from']:v['availability'] for v in values}
    assert by_date['2026-11-25']==4
    assert by_date['2026-11-27']==3


def test_stale_queued_availability_cannot_overwrite_newer_reservation_state(tmp_path, monkeypatch):
    client, db_file, iid, rooms, plans = cert_fixture(tmp_path, monkeypatch)
    calls=[]
    monkeypatch.setattr(rosa, '_channex_request', lambda path, method='POST', payload=None: calls.append((path,payload)) or {'data':[{'id':'task-coalesced'}]})
    room_id=rooms[1][0]
    with sqlite3.connect(db_file) as con:
        now=rosa.now_iso()
        con.execute("INSERT INTO channel_ari_outbox(id,organization_id,integration_id,endpoint,payload_json,status,attempts,available_at,task_ids_json,last_error,created_at,sent_at) VALUES (?,?,?,?,?,'queued',0,?,'[]',NULL,?,NULL)",
                     ('old-job','org_casa_rosa',iid,'/api/v1/availability',json.dumps({'values':[{'property_id':'remote-cert','room_type_id':'remote-double','date_from':'2026-11-25','date_to':'2026-11-25','availability':0}]}),now,now))
        con.execute("INSERT INTO channel_ari_outbox(id,organization_id,integration_id,endpoint,payload_json,status,attempts,available_at,task_ids_json,last_error,created_at,sent_at) VALUES (?,?,?,?,?,'queued',0,?,'[]',NULL,?,NULL)",
                     ('new-job','org_casa_rosa',iid,'/api/v1/availability',json.dumps({'values':[{'property_id':'remote-cert','room_type_id':'remote-double','date_from':'2026-11-25','date_to':'2026-11-25','availability':1}]}),now,now))
    result=rosa._drain_channex_ari_outbox(organization_id='org_casa_rosa',integration_id=iid,limit=2,ignore_throttle=True)
    assert not result['failed']
    assert len(calls)==1
    values=calls[0][1]['values']
    assert values == [{'property_id':'remote-cert','room_type_id':'remote-double','date_from':'2026-11-25','date_to':'2026-11-25','availability':1}]
