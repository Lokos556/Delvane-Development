import json
import sqlite3
import sys
from datetime import date, timedelta
from pathlib import Path

from fastapi.testclient import TestClient

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import app as rosa


def fresh(tmp_path, monkeypatch):
    db_file=tmp_path/'v2991.db'
    monkeypatch.setattr(rosa,'DB_PATH',db_file)
    monkeypatch.setattr(rosa,'CHANNEX_API_KEY','shared-test-key')
    rosa.init_db(reset=True)
    client=TestClient(rosa.app)
    login=client.post('/api/login',json={'email':'owner@demo.rosa','password':'rosa-owner'})
    assert login.status_code==200,login.text
    client.headers.update({'X-Rosa-CSRF':login.json()['csrf_token']})
    with sqlite3.connect(db_file) as con:
        con.row_factory=sqlite3.Row
        row=con.execute("""SELECT i.id FROM integrations i JOIN properties p ON p.id=i.property_id
                           WHERE p.name='Aqua' AND i.provider='Booking.com'""").fetchone()
        cfg={'adapter':'channex_channel_manager','provider_property_id':'bridge-casa',
             'channex_room_type_id':'room-aqua','channex_rate_plan_id':'rate-aqua',
             'commercial':True,'customer_handles_api_keys':False,'connector_core_version':'2.10.2'}
        con.execute("UPDATE integrations SET public_config_json=?,status='staging_ready' WHERE id=?",(json.dumps(cfg),row['id']))
        return client,db_file,row['id']


def test_base_rate_publishes_price_and_availability_for_365_days(tmp_path,monkeypatch):
    client,db_file,integration_id=fresh(tmp_path,monkeypatch)
    calls=[]
    monkeypatch.setattr(rosa,'_channex_request',lambda path,method='GET',payload=None:(calls.append((path,payload)) or {'data':[{'id':'task'}]}))
    response=client.put(f'/api/integrations/{integration_id}/channex/base-rate',json={'base_rate_huf':42000,'horizon_days':365})
    assert response.status_code==200,response.text
    assert response.json()['days']==365
    rate_payload=next(payload for path,payload in calls if path=='/api/v1/restrictions')
    assert rate_payload['values'][0]['rate']==4200000
    assert rate_payload['values'][0]['date_from']==str(date.today())
    assert rate_payload['values'][0]['date_to']==str(date.today()+timedelta(days=364))
    assert any(path=='/api/v1/availability' for path,_payload in calls)
    with sqlite3.connect(db_file) as con:
        assert con.execute("SELECT COUNT(*) FROM channel_ari_values WHERE integration_id=? AND nightly_rate_huf=42000",(integration_id,)).fetchone()[0]==365
        saved=con.execute("SELECT base_nightly_rate_huf,horizon_days,published_through FROM channel_rate_defaults WHERE integration_id=?",(integration_id,)).fetchone()
    assert saved==(42000,365,str(date.today()+timedelta(days=364)))


def test_existing_date_override_survives_base_rate_change(tmp_path,monkeypatch):
    client,db_file,integration_id=fresh(tmp_path,monkeypatch)
    monkeypatch.setattr(rosa,'_channex_request',lambda *args,**kwargs:{'data':[{'id':'task'}]})
    override_date=date.today()+timedelta(days=20)
    changed=client.put(f'/api/integrations/{integration_id}/channex/ari',json={
        'date_from':str(override_date),'date_to':str(override_date),'rate_huf':60000,
    })
    assert changed.status_code==200,changed.text
    published=client.put(f'/api/integrations/{integration_id}/channex/base-rate',json={'base_rate_huf':42000,'horizon_days':365})
    assert published.status_code==200,published.text
    with sqlite3.connect(db_file) as con:
        row=con.execute("SELECT nightly_rate_huf,base_rate_huf,rate_override_huf FROM channel_ari_values WHERE integration_id=? AND stay_date=?",(integration_id,str(override_date))).fetchone()
        ordinary=con.execute("SELECT nightly_rate_huf,base_rate_huf,rate_override_huf FROM channel_ari_values WHERE integration_id=? AND stay_date=?",(integration_id,str(override_date+timedelta(days=1)))).fetchone()
    assert row==(60000,42000,60000)
    assert ordinary==(42000,42000,None)


def test_upgrade_preserves_old_manual_prices_as_overrides(tmp_path,monkeypatch):
    _client,db_file,integration_id=fresh(tmp_path,monkeypatch)
    target=str(date.today()+timedelta(days=10))
    with rosa.db() as con:
        org=con.execute("SELECT organization_id FROM integrations WHERE id=?",(integration_id,)).fetchone()["organization_id"]
        con.execute("""INSERT INTO channel_ari_values
            (id,organization_id,integration_id,stay_date,nightly_rate_huf,updated_at)
            VALUES ('old-price',?,?,?,?,?)""",(org,integration_id,target,51000,rosa.now_iso()))
        con.execute("DELETE FROM schema_migrations WHERE version=2991")
        rosa.ensure_v2991_schema(con)
    with sqlite3.connect(db_file) as con:
        row=con.execute("SELECT nightly_rate_huf,rate_override_huf FROM channel_ari_values WHERE integration_id=? AND stay_date=?",(integration_id,target)).fetchone()
    assert row==(51000,51000)
