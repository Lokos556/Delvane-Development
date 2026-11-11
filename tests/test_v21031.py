import sqlite3
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import app as rosa
from test_v21027 import cert_fixture


def test_immediate_create_update_cancel_delivers_all_availability_transitions(tmp_path, monkeypatch):
    client, db_file, iid, rooms, plans = cert_fixture(tmp_path, monkeypatch)
    calls=[]
    def fake_request(path, method='POST', payload=None):
        if method == 'POST':
            calls.append(payload)
            return {'data':[{'id':f'task-{len(calls)}'}]}
        return {'data': {}}
    monkeypatch.setattr(rosa, '_channex_request', fake_request)
    room_id=rooms[1][0]
    with sqlite3.connect(db_file) as con:
        prop_id=con.execute('SELECT property_id FROM room_types WHERE id=?',(room_id,)).fetchone()[0]
    with sqlite3.connect(db_file) as con:
        con.execute("UPDATE room_types SET inventory_count=1 WHERE id=?", (room_id,))
        con.execute("UPDATE channex_room_type_values SET availability=1, manual_availability=1, reservation_availability=1 WHERE integration_id=? AND room_type_id=? AND stay_date IN ('2026-11-25')", (iid, room_id))
    body={
        'property_id':prop_id,'room_type_id':room_id,'source':'Direct','guest_name':'Rapid Cycle',
        'arrival_date':'2026-11-25','departure_date':'2026-11-26','guest_count':1,
        'total_huf':100,'payment_status':'unknown','registration_status':'incomplete',
        'arrival_time':None,'special_requests':[]
    }
    r=client.post('/api/reservations',json=body)
    assert r.status_code==200,r.text
    rid=r.json()['id']
    assert calls[-1]['values'][0]['availability']==0
    r=client.patch(f'/api/reservations/{rid}',json={'guest_name':'Rapid Cycle 2'})
    assert r.status_code==200,r.text
    r=client.delete(f'/api/reservations/{rid}')
    assert r.status_code==200,r.text
    vals=[p['values'][0]['availability'] for p in calls if isinstance(p,dict) and 'values' in p]
    assert 0 in vals and 1 in vals
