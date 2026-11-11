import json, sqlite3, sys
from datetime import date, timedelta
from pathlib import Path
from fastapi.testclient import TestClient
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import app as rosa

def test_certification_bulk_accepts_decimal_usd_and_sends_minor_units(tmp_path,monkeypatch):
    db_file=tmp_path/'cert.db'; monkeypatch.setattr(rosa,'DB_PATH',db_file); monkeypatch.setattr(rosa,'CHANNEX_API_KEY','shared-test-key'); rosa.init_db(reset=True)
    client=TestClient(rosa.app); login=client.post('/api/login',json={'email':'owner@demo.rosa','password':'rosa-owner'}); assert login.status_code==200
    client.headers.update({'X-Rosa-CSRF':login.json()['csrf_token']})
    with sqlite3.connect(db_file) as con:
        con.row_factory=sqlite3.Row
        row=con.execute("SELECT i.id,i.property_id FROM integrations i JOIN properties p ON p.id=i.property_id WHERE p.name='Aqua' AND i.provider='Booking.com'").fetchone()
        cfg={'adapter':'channex_channel_manager','provider_property_id':'bridge-cert','channex_room_type_id':'room-cert','channex_rate_plan_id':'rate-cert','commercial':False,'customer_handles_api_keys':False,'connector_core_version':'2.10.24','certification_workspace':True,'channex_currency':'USD','channex_rate_multiplier':100}
        con.execute("UPDATE integrations SET public_config_json=?,status='connected' WHERE id=?",(json.dumps(cfg),row['id']))
        plan=con.execute("SELECT id FROM rate_plans WHERE property_id=? ORDER BY id LIMIT 1",(row['property_id'],)).fetchone()['id']
        con.execute("INSERT OR REPLACE INTO channex_rate_mappings(id,organization_id,integration_id,rate_plan_id,channex_room_type_id,channex_rate_plan_id,active,created_at,updated_at) VALUES (?,?,?,?,?,?,1,?,?)",('mapcert','org_casa_rosa',row['id'],plan,'room-cert','rate-cert',rosa.now_iso(),rosa.now_iso()))
    calls=[]; monkeypatch.setattr(rosa,'_channex_request',lambda path,method='GET',payload=None: calls.append((path,method,payload)) or {'data':[{'id':'task-cert'}]})
    d=str(date.today()+timedelta(days=20))
    out=client.put(f'/api/integrations/{row["id"]}/channex/ari/batch',json={'updates':[{'rate_plan_id':plan,'date_from':d,'date_to':d,'rate_huf':456.23}]})
    assert out.status_code==200,out.text
    assert calls[0][2]['values'][0]['rate']==45623
