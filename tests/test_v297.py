import json
import sqlite3
import sys
from datetime import date, timedelta
from pathlib import Path
import pytest

from fastapi.testclient import TestClient

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import app as rosa


def fresh(tmp_path, monkeypatch):
    db_file=tmp_path/'v297.db'
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
             'commercial':True,'customer_handles_api_keys':False,'connector_core_version':'2.9.7'}
        con.execute("UPDATE integrations SET public_config_json=?,status='staging_ready' WHERE id=?",(json.dumps(cfg),row['id']))
        return client,db_file,row['id']


def test_whole_forint_price_is_sent_in_channex_minor_units(tmp_path,monkeypatch):
    client,db_file,integration_id=fresh(tmp_path,monkeypatch)
    calls=[]
    def fake_request(path,method='GET',payload=None):
        calls.append((path,method,payload))
        return {'data':[{'id':'task-rate'}],'meta':{'warnings':[]}}
    monkeypatch.setattr(rosa,'_channex_request',fake_request)
    target=date.today()+timedelta(days=5)
    response=client.put(f'/api/integrations/{integration_id}/channex/ari',json={
        'date_from':str(target),'date_to':str(target),'rate_huf':42000,
    })
    assert response.status_code==200,response.text
    sent=next(payload for path,method,payload in calls if path=='/api/v1/restrictions')
    assert sent['values'][0]['rate']==4200000
    with sqlite3.connect(db_file) as con:
        # Rosa continues to store and show normal whole-forint amounts.
        assert con.execute("SELECT nightly_rate_huf FROM channel_ari_values WHERE integration_id=?",(integration_id,)).fetchone()[0]==42000


@pytest.mark.parametrize("amount,stored,minor", [
    ("42000", 42000, 4200000),
    ("42000.49", 42000, 4200049),
    ("42000.50", 42000, 4200050),
    ("42001.50", 42002, 4200150),
    ("42000.51", 42001, 4200051),
    ("9007199254740993", 9007199254740993, 900719925474099300),
])
def test_legacy_decimal_rate_uses_exact_integer_storage_and_minor_units(
        tmp_path, monkeypatch, amount, stored, minor):
    client, db_file, integration_id = fresh(tmp_path, monkeypatch)
    calls = []
    monkeypatch.setattr(rosa, "_channex_request",
                        lambda path, method="POST", payload=None:
                        (calls.append((path, payload)) or {"data": [{"id": "exact-rate"}]}))
    day = str(date.today() + timedelta(days=5))
    response = client.put(f"/api/integrations/{integration_id}/channex/ari", json={
        "date_from": day, "date_to": day, "rate_huf": amount,
    })
    assert response.status_code == 200, response.text
    with sqlite3.connect(db_file) as con:
        row = con.execute("""SELECT nightly_rate_huf,rate_override_huf,
            typeof(nightly_rate_huf),typeof(rate_override_huf),availability
            FROM channel_ari_values WHERE integration_id=? AND stay_date=?""",
            (integration_id, day)).fetchone()
    # Legacy HUF storage already rounds whole forints using Decimal's half-even
    # rule. The override must use exactly that same integer, never a float.
    assert row == (stored, stored, "integer", "integer", None)
    assert [path for path, _ in calls] == ["/api/v1/restrictions"]
    assert calls[0][1]["values"][0]["rate"] == minor


def test_upgrade_repairs_pending_and_already_sent_wrong_rates(tmp_path,monkeypatch):
    client,db_file,integration_id=fresh(tmp_path,monkeypatch)
    target=str(date.today()+timedelta(days=8))
    wrong={'values':[{'property_id':'bridge-casa','rate_plan_id':'rate-aqua','date':target,'rate':42000}]}
    with sqlite3.connect(db_file) as con:
        con.row_factory=sqlite3.Row
        con.execute("DELETE FROM schema_migrations WHERE version=2970")
        con.execute("""INSERT INTO channel_ari_values
            (id,organization_id,integration_id,stay_date,nightly_rate_huf,availability,min_stay,
             stop_sell,closed_to_arrival,closed_to_departure,updated_at)
            VALUES ('saved-rate','org_casa_rosa',?,?,42000,NULL,NULL,NULL,NULL,NULL,?)""",
            (integration_id,target,rosa.now_iso()))
        con.execute("""INSERT INTO channel_ari_outbox
            (id,organization_id,integration_id,endpoint,payload_json,status,attempts,
             available_at,task_ids_json,last_error,created_at,sent_at)
            VALUES ('pending-wrong','org_casa_rosa',?,'/api/v1/restrictions',?,'retry',2,
                    '2099-01-01T00:00:00','[]','old warning',?,NULL)""",
            (integration_id,json.dumps(wrong),rosa.now_iso()))
        rosa.ensure_v297_schema(con)
        rows=con.execute("SELECT id,payload_json,status,attempts,last_error FROM channel_ari_outbox WHERE integration_id=? ORDER BY id",(integration_id,)).fetchall()
        migration=con.execute("SELECT name FROM schema_migrations WHERE version=2970").fetchone()[0]
    pending=next(row for row in rows if row[0]=='pending-wrong')
    assert json.loads(pending[1])['values'][0]['rate']==4200000
    assert pending[2:]==('queued',0,None)
    corrective=next(row for row in rows if row[0]!='pending-wrong')
    assert json.loads(corrective[1])['values'][0]['rate']==4200000
    assert migration=='channex_huf_minor_unit_repair'
