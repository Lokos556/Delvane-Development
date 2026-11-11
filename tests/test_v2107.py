import json, sqlite3, sys
from pathlib import Path
from fastapi.testclient import TestClient
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import app as rosa


def test_existing_channex_inventory_mapping_never_creates_remote_inventory(tmp_path, monkeypatch):
    db_file=tmp_path/'v2107.db'
    monkeypatch.setattr(rosa,'DB_PATH',db_file)
    monkeypatch.setattr(rosa,'CHANNEX_API_KEY','shared-test-key')
    monkeypatch.setattr(rosa,'CHANNEX_BASE_URL','https://staging.channex.io')
    rosa.init_db(reset=True)
    client=TestClient(rosa.app)
    login=client.post('/api/login',json={'email':'owner@demo.rosa','password':'rosa-owner'})
    assert login.status_code==200
    client.headers.update({'X-Rosa-CSRF':login.json()['csrf_token']})
    with sqlite3.connect(db_file) as con:
        con.row_factory=sqlite3.Row
        integration=con.execute("SELECT * FROM integrations WHERE property_id='prop_aqua' AND provider='Booking.com' LIMIT 1").fetchone()
        now=rosa.now_iso(); org=integration['organization_id']; prop=integration['property_id']
        rooms=[]
        for name,code in [('Twin Room','twin-room'),('Double Room','double-room')]:
            rid=rosa.new_id('roomtype'); rooms.append((rid,name))
            con.execute("INSERT INTO room_types(id,organization_id,property_id,name,code,inventory_count,max_guests,active,created_at,updated_at) VALUES (?,?,?,?,?,?,?,1,?,?)",(rid,org,prop,name,code,1,2,now,now))
        rates=[]
        for rid,name in [(rooms[0][0],'Best Available Rate'),(rooms[0][0],'Bed & Breakfast Rate'),(rooms[1][0],'Best Available Rate'),(rooms[1][0],'Bed & Breakfast Rate')]:
            pid=rosa.new_id('rateplan'); rates.append(pid)
            code=rosa.new_id('code')
            con.execute("INSERT INTO rate_plans(id,organization_id,property_id,room_type_id,name,code,meal_type,cancellation_policy,base_rate_huf,active,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?,?,1,?,?)",(pid,org,prop,rid,name,code,'breakfast' if 'Breakfast' in name else 'none','flexible',120 if 'Breakfast' in name else 100,now,now))
        iid=integration['id']

    def fake(path,method='GET',payload=None):
        assert method=='GET', f'Unexpected Channex mutation: {method} {path}'
        if path.startswith('/api/v1/properties?'):
            return {'data':[{'id':'test-property','attributes':{'title':'Test Property - Rosa AI'}}]}
        if path.startswith('/api/v1/room_types?'):
            return {'data':[
                {'id':'remote-twin','attributes':{'title':'Twin Room','count_of_rooms':1,'occ_adults':2}},
                {'id':'remote-double','attributes':{'title':'Double Room','count_of_rooms':1,'occ_adults':2}},
            ]}
        if path.startswith('/api/v1/rate_plans/options?'):
            return {'data':[
                {'id':'remote-twin-bar','attributes':{'title':'Best Available Rate','room_type_id':'remote-twin','meal_type':'none'}},
                {'id':'remote-twin-bb','attributes':{'title':'Bed & Breakfast Rate','room_type_id':'remote-twin','meal_type':'breakfast'}},
                {'id':'remote-double-bar','attributes':{'title':'Best Available Rate','room_type_id':'remote-double','meal_type':'none'}},
                {'id':'remote-double-bb','attributes':{'title':'Bed & Breakfast Rate','room_type_id':'remote-double','meal_type':'breakfast'}},
            ]}
        raise AssertionError(path)
    monkeypatch.setattr(rosa,'_channex_request',fake)

    options=client.get(f'/api/integrations/{iid}/channex/inventory-mapping?channex_property_id=test-property')
    assert options.status_code==200, options.text
    assert {x['title'] for x in options.json()['remote_room_types']}=={'Twin Room','Double Room'}
    assert len(options.json()['remote_rate_plans'])==4

    local_rooms=options.json()['local_room_types']
    local_rates=options.json()['local_rate_plans']
    by_name={x['name']:x for x in local_rooms}
    rates_by_room={}
    for rate in local_rates: rates_by_room.setdefault(rate['room_type_id'],[]).append(rate)
    twin=by_name['Twin Room']['id']; double=by_name['Double Room']['id']
    payload={
        'channex_property_id':'test-property',
        'room_mappings':[
            {'room_type_id':twin,'channex_room_type_id':'remote-twin'},
            {'room_type_id':double,'channex_room_type_id':'remote-double'},
        ],
        'rate_mappings':[]
    }
    for local in [x for x in local_rates if x['name'] in {'Best Available Rate','Bed & Breakfast Rate'}]:
        remote_room='remote-twin' if local['room_type_id']==twin else 'remote-double'
        suffix='bb' if 'Breakfast' in local['name'] else 'bar'
        payload['rate_mappings'].append({'rate_plan_id':local['id'],'channex_room_type_id':remote_room,'channex_rate_plan_id':f'remote-{remote_room.split("-")[1]}-{suffix}'})
    saved=client.put(f'/api/integrations/{iid}/channex/inventory-mapping',json=payload)
    assert saved.status_code==200, saved.text
    assert 'No remote rooms or rate plans were created' in saved.json()['message']
    with sqlite3.connect(db_file) as con:
        con.row_factory=sqlite3.Row
        assert con.execute('SELECT COUNT(*) c FROM channex_room_type_mappings WHERE integration_id=? AND active=1',(iid,)).fetchone()['c']==2
        assert con.execute('SELECT COUNT(*) c FROM channex_rate_mappings WHERE integration_id=? AND active=1',(iid,)).fetchone()['c']==4
        cfg=json.loads(con.execute('SELECT public_config_json FROM integrations WHERE id=?',(iid,)).fetchone()['public_config_json'])
        assert cfg['provider_property_id']=='test-property'
