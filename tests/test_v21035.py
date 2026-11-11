import json
import sqlite3
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import app as rosa
from test_v21027 import cert_fixture


def test_v3065_repairs_legacy_manual_zero_on_cert_property(tmp_path, monkeypatch):
    client, db_file, iid, rooms, plans = cert_fixture(tmp_path, monkeypatch)
    room_id=rooms[1][0]
    with sqlite3.connect(db_file) as con:
        con.row_factory=sqlite3.Row
        con.execute("DELETE FROM schema_migrations WHERE version=3065")
        con.execute("INSERT INTO channex_room_type_values(id,organization_id,integration_id,room_type_id,stay_date,availability,manual_availability,reservation_availability,updated_at) VALUES (?,?,?,?,?,?,?,?,?) ON CONFLICT(integration_id,room_type_id,stay_date) DO UPDATE SET availability=0,manual_availability=0,reservation_availability=4,updated_at=excluded.updated_at",(rosa.new_id('rtv'),'org_casa_rosa',iid,room_id,'2026-11-25',0,0,4,rosa.now_iso()))
        rosa.ensure_v3065_schema(con)
        row=con.execute("SELECT availability,manual_availability,reservation_availability FROM channex_room_type_values WHERE integration_id=? AND room_type_id=? AND stay_date='2026-11-25'",(iid,room_id)).fetchone()
        assert tuple(row)==(4,None,4)
        out=con.execute("SELECT payload_json FROM channel_ari_outbox WHERE integration_id=? AND endpoint='/api/v1/availability' ORDER BY created_at DESC LIMIT 1",(iid,)).fetchone()
        payload=json.loads(out['payload_json'])
        assert any(v['date_from']=='2026-11-25' and v['availability']==4 for v in payload['values'])


def test_reservation_move_reopens_old_date_after_repair(tmp_path, monkeypatch):
    client, db_file, iid, rooms, plans = cert_fixture(tmp_path, monkeypatch)
    calls=[]
    def fake_request(path, method='POST', payload=None):
        if method == 'POST':
            calls.append(payload)
            return {'data':[{'id':f'task-{len(calls)}'}]}
        return {'data': {}}
    monkeypatch.setattr(rosa,'_channex_request',fake_request)
    room_id=rooms[1][0]
    with sqlite3.connect(db_file) as con:
        con.row_factory=sqlite3.Row
        prop_id=con.execute('SELECT property_id FROM room_types WHERE id=?',(room_id,)).fetchone()['property_id']
        con.execute("INSERT INTO channex_room_type_values(id,organization_id,integration_id,room_type_id,stay_date,availability,manual_availability,reservation_availability,updated_at) VALUES (?,?,?,?,?,?,?,?,?) ON CONFLICT(integration_id,room_type_id,stay_date) DO UPDATE SET availability=0,manual_availability=0,reservation_availability=4,updated_at=excluded.updated_at",(rosa.new_id('rtv'),'org_casa_rosa',iid,room_id,'2026-11-25',0,0,4,rosa.now_iso()))
        con.execute("DELETE FROM schema_migrations WHERE version=3065")
        rosa.ensure_v3065_schema(con)
    body={'property_id':prop_id,'room_type_id':room_id,'source':'Direct','guest_name':'Move Test','arrival_date':'2026-11-25','departure_date':'2026-11-26','guest_count':1,'total_huf':100,'payment_status':'unknown','registration_status':'incomplete','arrival_time':None,'special_requests':[]}
    r=client.post('/api/reservations',json=body); assert r.status_code==200,r.text
    rid=r.json()['id']
    r=client.patch(f'/api/reservations/{rid}',json={'arrival_date':'2026-11-27','departure_date':'2026-11-28'})
    assert r.status_code==200,r.text
    vals=[v for p in calls if isinstance(p,dict) for v in p.get('values',[])]
    assert any(v['date_from']=='2026-11-25' and v['date_to']=='2026-11-25' and v['availability']==4 for v in vals)
    assert any(v['date_from']=='2026-11-27' and v['date_to']=='2026-11-27' and v['availability']==3 for v in vals)


def test_manual_availability_is_consumed_by_reservation_when_capacity_is_higher(tmp_path, monkeypatch):
    """A manual availability of 1 must become 0 after one booking even when the room has 4 units."""
    client, db_file, iid, rooms, plans = cert_fixture(tmp_path, monkeypatch)
    calls=[]
    monkeypatch.setattr(rosa, '_channex_request', lambda path, method='POST', payload=None: calls.append((path,payload)) or {'data':[{'id':f'task-{len(calls)}'}]})
    room_id=rooms[1][0]  # Double Room: capacity 4 in the current certification workspace.
    with sqlite3.connect(db_file) as con:
        con.row_factory=sqlite3.Row
        prop_id=con.execute('SELECT property_id FROM room_types WHERE id=?',(room_id,)).fetchone()['property_id']
    # Test 9 explicitly sets the Double Room to 1 available unit before booking.
    response=client.put(f'/api/integrations/{iid}/channex/ari',json={
        'date_from':'2026-11-25','date_to':'2026-11-25','room_type_id':room_id,
        'rate_plan_id':plans[2][0],'availability':1,
    })
    assert response.status_code==200,response.text
    calls.clear()
    created=client.post('/api/reservations',json={
        'property_id':prop_id,'room_type_id':room_id,'source':'Direct','guest_name':'Test 9 Double',
        'arrival_date':'2026-11-25','departure_date':'2026-11-26','guest_count':1,
        'total_huf':100,'payment_status':'unknown','registration_status':'incomplete',
        'arrival_time':None,'special_requests':[]
    })
    assert created.status_code==200,created.text
    availability=[p for path,p in calls if path=='/api/v1/availability']
    assert availability
    values=availability[-1]['values']
    assert any(v['date_from']=='2026-11-25' and v['date_to']=='2026-11-25' and v['availability']==0 for v in values)
    with sqlite3.connect(db_file) as con:
        row=con.execute('SELECT availability,manual_availability,reservation_availability FROM channex_room_type_values WHERE integration_id=? AND room_type_id=? AND stay_date=?',(iid,room_id,'2026-11-25')).fetchone()
    assert row==(0,1,3)
