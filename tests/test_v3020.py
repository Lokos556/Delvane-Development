import json
import sqlite3
import sys
from datetime import date, timedelta
from pathlib import Path
from fastapi.testclient import TestClient
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import app as rosa

def fresh(tmp_path,monkeypatch):
    db_file=tmp_path/'v3030.db'; monkeypatch.setattr(rosa,'DB_PATH',db_file); monkeypatch.setattr(rosa,'CHANNEX_API_KEY','shared-test-key'); rosa.init_db(reset=True)
    client=TestClient(rosa.app); login=client.post('/api/login',json={'email':'owner@demo.rosa','password':'rosa-owner'}); assert login.status_code==200
    client.headers.update({'X-Rosa-CSRF':login.json()['csrf_token']})
    with sqlite3.connect(db_file) as con:
        con.row_factory=sqlite3.Row
        row=con.execute("SELECT i.id,i.property_id FROM integrations i JOIN properties p ON p.id=i.property_id WHERE p.name='Aqua' AND i.provider='Booking.com'").fetchone()
        cfg={'adapter':'channex_channel_manager','provider_property_id':'bridge-casa','channex_room_type_id':'room-aqua','channex_rate_plan_id':'rate-standard','commercial':True,'customer_handles_api_keys':False,'connector_core_version':'2.10.2'}
        con.execute("UPDATE integrations SET public_config_json=?,status='staging_ready' WHERE id=?",(json.dumps(cfg),row['id']))
        plan=con.execute("SELECT id FROM rate_plans WHERE property_id=? ORDER BY id LIMIT 1",(row['property_id'],)).fetchone()['id']
        con.execute("INSERT OR REPLACE INTO channex_rate_mappings(id,organization_id,integration_id,rate_plan_id,channex_room_type_id,channex_rate_plan_id,active,created_at,updated_at) VALUES (?,?,?,?,?,?,1,?,?)",('map2','org_casa_rosa',row['id'],plan,'room-aqua','rate-standard',rosa.now_iso(),rosa.now_iso()))
        return client,db_file,row['id'],plan

def test_batch_multi_rate_is_one_restrictions_call(tmp_path,monkeypatch):
    client,db_file,iid,plan=fresh(tmp_path,monkeypatch)
    calls=[]; monkeypatch.setattr(rosa,'_channex_request',lambda path,method='GET',payload=None: calls.append((path,method,payload)) or {'data':[{'id':'task-1'}]})
    d=str(date.today()+timedelta(days=20))
    out=client.put(f'/api/integrations/{iid}/channex/ari/batch',json={'updates':[{'rate_plan_id':plan,'date_from':d,'date_to':d,'rate_huf':33300},{'rate_plan_id':plan,'date_from':str(date.today()+timedelta(days=22)),'date_to':str(date.today()+timedelta(days=22)),'min_stay':3}]})
    assert out.status_code==200,out.text
    assert len(calls)==1 and calls[0][0]=='/api/v1/restrictions'
    assert len(calls[0][2]['values'])==2

def test_full_sync_uses_per_rate_plan_values(tmp_path,monkeypatch):
    client,db_file,iid,plan=fresh(tmp_path,monkeypatch)
    with sqlite3.connect(db_file) as con:
        con.execute("INSERT INTO channex_rate_plan_values(id,organization_id,integration_id,rate_plan_id,stay_date,nightly_rate_huf,min_stay,stop_sell,closed_to_arrival,closed_to_departure,updated_at) VALUES (?,?,?,?,?,?,?,?,?,?,?)",('x','org_casa_rosa',iid,plan,str(date.today()+timedelta(days=1)),55500,4,1,0,1,rosa.now_iso()))
        con.execute("INSERT INTO channel_rate_defaults(integration_id,organization_id,base_nightly_rate_huf,horizon_days,published_through,updated_at) VALUES (?,?,?,?,?,?)",(iid,'org_casa_rosa',42000,500,None,rosa.now_iso()))
    calls=[]; monkeypatch.setattr(rosa,'_channex_request',lambda path,method='GET',payload=None: calls.append((path,method,payload)) or {'data':[{'id':'task'}]})
    out=client.post(f'/api/integrations/{iid}/channex/full-sync'); assert out.status_code==200,out.text
    restrictions=next(c[2] for c in calls if c[0]=='/api/v1/restrictions')['values']
    first=restrictions[0]
    assert first['rate']==55500*100
    assert first['min_stay_arrival']==4 and first['stop_sell']==1 and first['closed_to_departure']==1
