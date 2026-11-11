import json
import sqlite3
import sys
from datetime import date, timedelta
from pathlib import Path
from unittest.mock import patch

from fastapi.testclient import TestClient
from fastapi import HTTPException

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import app as rosa


def fresh(tmp_path, monkeypatch):
    db_file=tmp_path/'v2912.db'
    monkeypatch.setattr(rosa,'DB_PATH',db_file)
    monkeypatch.setattr(rosa,'CHANNEX_API_KEY','shared-test-key')
    rosa.init_db(reset=True)
    client=TestClient(rosa.app)
    login=client.post('/api/login',json={'email':'owner@demo.rosa','password':'rosa-owner'})
    assert login.status_code==200,login.text
    client.headers.update({'X-Rosa-CSRF':login.json()['csrf_token']})
    with sqlite3.connect(db_file) as con:
        con.row_factory=sqlite3.Row
        row=con.execute("""SELECT i.id,i.property_id FROM integrations i JOIN properties p ON p.id=i.property_id
                           WHERE p.name='Aqua' AND i.provider='Booking.com'""").fetchone()
        cfg={'adapter':'channex_channel_manager','provider_property_id':'bridge-casa',
             'channex_room_type_id':'room-aqua','channex_rate_plan_id':'rate-aqua',
             'commercial':True,'customer_handles_api_keys':False,'connector_core_version':'2.10.2'}
        con.execute("UPDATE integrations SET public_config_json=?,status='staging_ready' WHERE id=?",(json.dumps(cfg),row['id']))
        return client,db_file,row['id'],row['property_id']


def set_base_rate(db_file, integration_id, rate=42000):
    with sqlite3.connect(db_file) as con:
        con.execute("INSERT INTO channel_rate_defaults(integration_id,organization_id,base_nightly_rate_huf,horizon_days,published_through,updated_at) VALUES (?,?,?,?,?,?)",
                    (integration_id,'org_casa_rosa',rate,500,None,rosa.now_iso()))


def test_full_sync_is_two_500_day_batches(tmp_path,monkeypatch):
    client,db_file,integration_id,_=fresh(tmp_path,monkeypatch)
    set_base_rate(db_file,integration_id)
    calls=[]
    def fake_request(path,method='GET',payload=None):
        calls.append((path,method,payload))
        return {'data':[{'id':f"task-{len(calls)}"}]}
    monkeypatch.setattr(rosa,'_channex_request',fake_request)
    response=client.post(f'/api/integrations/{integration_id}/channex/full-sync')
    assert response.status_code==200,response.text
    assert response.json()['ok'] is True
    assert {call[0] for call in calls}=={'/api/v1/availability','/api/v1/restrictions'}
    assert all(len(call[2]['values'])==500 for call in calls)
    assert all(call[2]['values'][0]['date']==str(date.today()+timedelta(days=1)) for call in calls)
    assert all(call[2]['values'][-1]['date']==str(date.today()+timedelta(days=500)) for call in calls)
    with sqlite3.connect(db_file) as con:
        rows=con.execute("SELECT endpoint,status,task_ids_json FROM channel_ari_outbox WHERE integration_id=? ORDER BY endpoint",(integration_id,)).fetchall()
    assert len(rows)==2
    assert all(row[1]=='sent' for row in rows)
    assert all(json.loads(row[2]) for row in rows)


def test_full_sync_requires_a_base_rate(tmp_path,monkeypatch):
    client,db_file,integration_id,_=fresh(tmp_path,monkeypatch)
    response=client.post(f'/api/integrations/{integration_id}/channex/full-sync')
    assert response.status_code==409
    assert 'base nightly price' in response.json()['detail'].lower()


def test_channex_429_sets_minimum_60_second_pause(tmp_path,monkeypatch):
    client,db_file,integration_id,_=fresh(tmp_path,monkeypatch)
    set_base_rate(db_file,integration_id)
    with sqlite3.connect(db_file) as con:
        con.execute("INSERT INTO channel_ari_outbox(id,organization_id,integration_id,endpoint,payload_json,status,attempts,available_at,task_ids_json,last_error,created_at,sent_at) VALUES (?,?,?,?,?,'queued',0,?,'[]',NULL,?,NULL)",
                    ('rate-limit-job','org_casa_rosa',integration_id,'/api/v1/availability',json.dumps({'values':[{'property_id':'bridge-casa','room_type_id':'room-aqua','date':str(date.today()),'availability':1}]}),rosa.now_iso(),rosa.now_iso()))
    def rate_limited(*args,**kwargs):
        raise HTTPException(429,'Channex rate limit reached',headers={'Retry-After':'10'})
    monkeypatch.setattr(rosa,'_channex_request',rate_limited)
    out=rosa._drain_channex_ari_outbox(organization_id='org_casa_rosa',integration_id=integration_id,limit=1)
    assert out['failed']
    with sqlite3.connect(db_file) as con:
        con.row_factory=sqlite3.Row
        row=con.execute("SELECT status,available_at FROM channel_ari_outbox WHERE id='rate-limit-job'").fetchone()
        integration=con.execute("SELECT channex_rate_limit_until FROM integrations WHERE id=?",(integration_id,)).fetchone()
    assert row['status']=='retry'
    assert integration['channex_rate_limit_until'] is not None
    pause=(rosa.datetime.fromisoformat(integration['channex_rate_limit_until'])-rosa.datetime.now()).total_seconds()
    assert pause>=59
