import json, sqlite3, sys
from pathlib import Path
from fastapi.testclient import TestClient
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import app as rosa

def fresh(tmp_path, monkeypatch):
    db_file=tmp_path/'v3021.db'
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
        row=con.execute("SELECT i.id,i.property_id FROM integrations i JOIN properties p ON p.id=i.property_id WHERE p.name='Aqua' AND i.provider='Booking.com'").fetchone()
        con.execute("UPDATE integrations SET public_config_json=?,status='staging_ready' WHERE id=?",(json.dumps({'adapter':'channex_channel_manager','commercial':True}),row['id']))
    return client, db_file, row['id']

def test_staging_link_imports_and_maps_second_rate_plan(tmp_path, monkeypatch):
    client, db_file, iid=fresh(tmp_path,monkeypatch)
    remote_calls=[]
    def fake(path, method='GET', payload=None):
        remote_calls.append((path,method,payload))
        if path.startswith('/api/v1/properties?'): return {'data':[{'id':'prop-staging','attributes':{'title':'Casa Rosa - Staging'}}]}
        if path.startswith('/api/v1/room_types?'): return {'data':[]}
        if path=='/api/v1/room_types': return {'data':{'id':'room-aqua'}}
        if path.startswith('/api/v1/rate_plans/options?'): return {'data':[{'id':'rate-standard','attributes':{'title':'Standard Rate','room_type_id':'room-aqua'}}]}
        if path=='/api/v1/rate_plans':
            return {'data':{'id':'rate-nonref'}}
        raise AssertionError(path)
    monkeypatch.setattr(rosa,'_channex_request',fake)
    out=client.post(f'/api/integrations/{iid}/channex/link',json={'channex_property_id':'prop-staging','create_inventory':True})
    assert out.status_code==200,out.text
    with sqlite3.connect(db_file) as con:
        con.row_factory=sqlite3.Row
        maps=con.execute('SELECT channex_rate_plan_id,rate_plan_id FROM channex_rate_mappings WHERE integration_id=? ORDER BY channex_rate_plan_id',(iid,)).fetchall()
        plans=con.execute('SELECT name FROM rate_plans WHERE property_id=(SELECT property_id FROM integrations WHERE id=?) ORDER BY name',(iid,)).fetchall()
    assert {m['channex_rate_plan_id'] for m in maps}=={'rate-standard','rate-nonref'}
    assert {p['name'] for p in plans} >= {'Standard Rate','Non-refundable Rate'}
