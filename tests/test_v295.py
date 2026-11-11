import json
import sqlite3
import sys
from datetime import date, timedelta
from pathlib import Path

from fastapi import HTTPException
from fastapi.testclient import TestClient

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import app as rosa


def fresh(tmp_path, monkeypatch):
    db_file=tmp_path/'v295.db'
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
        cfg={'adapter':'channex_channel_manager','provider_property_id':'bridge-casa','channex_room_type_id':'room-aqua','channex_rate_plan_id':'rate-aqua','commercial':True,'customer_handles_api_keys':False,'connector_core_version':'2.9.7'}
        con.execute("UPDATE integrations SET public_config_json=?,status='staging_ready',connection_type='Channex staging API' WHERE id=?",(json.dumps(cfg),row['id']))
        return client,db_file,row['id']


def test_owner_range_change_batches_and_sends_two_ari_calls(tmp_path,monkeypatch):
    client,db_file,integration_id=fresh(tmp_path,monkeypatch)
    calls=[]
    def fake_request(path,method='GET',payload=None):
        calls.append((path,method,payload))
        return {'data':[{'id':f'task-{len(calls)}','type':'task'}],'meta':{'message':'Success','warnings':[]}}
    monkeypatch.setattr(rosa,'_channex_request',fake_request)
    start=date.today()+timedelta(days=7); end=start+timedelta(days=2)
    response=client.put(f'/api/integrations/{integration_id}/channex/ari',json={
        'date_from':str(start),'date_to':str(end),'rate_huf':42000,'availability':1,
        'min_stay':2,'stop_sell':False,'closed_to_arrival':True
    })
    assert response.status_code==200,response.text
    body=response.json(); assert body['ok'] is True and body['days']==3 and body['queued']==2
    assert {x[0] for x in calls}=={'/api/v1/restrictions','/api/v1/availability'}
    by_endpoint={item[0]:item for item in calls}
    restrictions=by_endpoint['/api/v1/restrictions'][2]['values'][0]
    assert restrictions=={'property_id':'bridge-casa','date_from':str(start),'date_to':str(end),'rate_plan_id':'rate-aqua','rate':4200000,'min_stay_arrival':2,'stop_sell':False,'closed_to_arrival':True}
    availability=by_endpoint['/api/v1/availability'][2]['values'][0]
    assert availability=={'property_id':'bridge-casa','date_from':str(start),'date_to':str(end),'room_type_id':'room-aqua','availability':1}
    with sqlite3.connect(db_file) as con:
        assert con.execute("SELECT COUNT(*) FROM channel_ari_values WHERE integration_id=?",(integration_id,)).fetchone()[0]==3
        assert con.execute("SELECT COUNT(*) FROM channel_ari_outbox WHERE integration_id=? AND status='sent'",(integration_id,)).fetchone()[0]==2
    loaded=client.get(f'/api/integrations/{integration_id}/channex/ari?date_from={start}&date_to={end}')
    assert loaded.status_code==200 and len(loaded.json()['values'])==3


def test_v296_repairs_pending_virtual_min_stay_payload(tmp_path,monkeypatch):
    client,db_file,integration_id=fresh(tmp_path,monkeypatch)
    old_payload={'values':[{'property_id':'bridge-casa','rate_plan_id':'rate-aqua','date_from':'2026-09-25','date_to':'2026-09-27','rate':42000,'min_stay':2}]}
    with sqlite3.connect(db_file) as con:
        con.row_factory=sqlite3.Row
        con.execute("DELETE FROM schema_migrations WHERE version=2960")
        con.execute("""INSERT INTO channel_ari_outbox
            (id,organization_id,integration_id,endpoint,payload_json,status,attempts,available_at,task_ids_json,last_error,created_at,sent_at)
            VALUES ('legacy-min-stay','org_casa_rosa',?,'/api/v1/restrictions',?,'retry',3,'2099-01-01T00:00:00','[]','rejected','2026-09-10T12:00:00',NULL)""",
            (integration_id,json.dumps(old_payload)))
        rosa.ensure_v296_schema(con)
        row=con.execute("SELECT payload_json,status,attempts,last_error FROM channel_ari_outbox WHERE id='legacy-min-stay'").fetchone()
        migration=con.execute("SELECT name FROM schema_migrations WHERE version=2960").fetchone()
    repaired=json.loads(row[0])['values'][0]
    assert 'min_stay' not in repaired
    assert repaired['min_stay_arrival']==2
    assert row[1:]==('queued',0,None)
    assert migration[0]=='explicit_minimum_stay_arrival'


def test_ari_failure_is_durable_and_retries(tmp_path,monkeypatch):
    client,db_file,integration_id=fresh(tmp_path,monkeypatch)
    state={'fail':True}
    def fake_request(path,method='GET',payload=None):
        if state['fail']: raise HTTPException(503,'temporary outage')
        return {'data':[{'id':'task-retry','type':'task'}],'meta':{'warnings':[]}}
    monkeypatch.setattr(rosa,'_channex_request',fake_request)
    target=date.today()+timedelta(days=10)
    response=client.put(f'/api/integrations/{integration_id}/channex/ari',json={'date_from':str(target),'date_to':str(target),'rate_huf':51000})
    assert response.status_code==200 and response.json()['saved'] is True and response.json()['ok'] is False
    with sqlite3.connect(db_file) as con:
        assert con.execute("SELECT nightly_rate_huf FROM channel_ari_values WHERE integration_id=?",(integration_id,)).fetchone()[0]==51000
        row=con.execute("SELECT status,attempts FROM channel_ari_outbox WHERE integration_id=?",(integration_id,)).fetchone()
        assert row==('retry',1)
        con.execute("UPDATE channel_ari_outbox SET available_at='2000-01-01T00:00:00' WHERE integration_id=?",(integration_id,))
    state['fail']=False
    delivered=rosa._drain_channex_ari_outbox(integration_id=integration_id,limit=1)
    assert delivered['delivered'][0]['task_ids']==['task-retry']
    with sqlite3.connect(db_file) as con:
        row=con.execute("SELECT status,attempts,task_ids_json FROM channel_ari_outbox WHERE integration_id=?",(integration_id,)).fetchone()
        assert row==('sent',2,'["task-retry"]')


def test_ari_rejects_past_dates_and_unmapped_properties(tmp_path,monkeypatch):
    client,db_file,integration_id=fresh(tmp_path,monkeypatch)
    yesterday=date.today()-timedelta(days=1)
    response=client.put(f'/api/integrations/{integration_id}/channex/ari',json={'date_from':str(yesterday),'date_to':str(yesterday),'rate_huf':10000})
    assert response.status_code==400
    with sqlite3.connect(db_file) as con:
        con.execute("UPDATE integrations SET public_config_json='{}' WHERE id=?",(integration_id,))
    tomorrow=date.today()+timedelta(days=1)
    response=client.put(f'/api/integrations/{integration_id}/channex/ari',json={'date_from':str(tomorrow),'date_to':str(tomorrow),'availability':0})
    assert response.status_code==409
