"""Persistent launch configuration, safe restart/reset and API durability."""
from contextlib import contextmanager
from datetime import timedelta
import json
import os
from pathlib import Path
import socket
import sqlite3

import pytest
from fastapi.testclient import TestClient
import app
from persistent_development import PersistentDevelopment, RESET_CONFIRMATION, store_lock
from run_development_workspace import prepare_workspace
from testing_safety import IsolatedEnvironment, TestSafetyError


PASSWORD = "synthetic-persistent-password"


@contextmanager
def workspace(parent, password=None):
    routes = list(app.app.router.routes)
    try:
        with PersistentDevelopment(_test_parent=parent) as storage:
            storage.protect_app(app)
            storage.prepare(app, password)
            with TestClient(app.app) as client:
                yield storage, client
    finally:
        app.app.router.routes[:] = routes


def login(client, password=PASSWORD):
    result = client.post('/api/login', json={'email':'owner@workspace.invalid','password':password})
    assert result.status_code == 200, result.text
    client.headers['X-Rosa-CSRF'] = result.json()['csrf_token']


def booking():
    arrival = app.date.today()+timedelta(days=800)
    return {'property_id':'prop_flora','guest_name':'Fictional Persistent Guest','source':'Direct',
            'arrival_date':str(arrival),'departure_date':str(arrival+timedelta(days=2)),
            'guest_count':1,'total_huf':123456,'arrival_time':'18:30','special_requests':['Synthetic cot']}


def test_reservation_guests_staff_assignments_and_keys_survive_restart(tmp_path):
    with workspace(tmp_path, PASSWORD) as (storage, client):
        assert storage.fresh
        login(client)
        marker = client.get('/api/development/workspace').json()
        assert marker['mode'] == 'persistent' and marker['isolated'] is True
        rid = client.post('/api/reservations', json=booking()).json()['id']
        assert client.post(f'/api/reservations/{rid}/notes',json={'body':'Fictional persistent note'}).status_code == 200
        link = client.get(f'/api/reservations/{rid}/guest-checkin-links').json()['links'][0]
        gid = link['guest_record_id']
        token = link['url'].rsplit('/',1)[-1]
        assert client.post(f'/api/public/checkin/{token}',json={'full_name':'Fictional Persistent Guest','date_of_birth':'2000-01-02','nationality':'HUN','document_type':'passport','document_number':'FICTIONAL-ONLY','guest_confirmed':True,'address':'Synthetic address'}).status_code == 200
        member = client.post('/api/team/members',json={'full_name':'Fictional Persistent Cleaner','email':'fictional-persistent@workspace.invalid','role':'cleaner'}).json()['member_id']
        task = client.post('/api/work-tasks',json={'property_id':'prop_flora','title':'Fictional persisted task','scheduled_date':str(app.date.today()),'assigned_to':member}).json()['id']
        assert client.patch('/api/organization/mode',json={'mode':'assist'}).status_code == 200
        # Ordinary restarts must not revive edited accounts or cancelled seed records.
        assert client.patch('/api/team/members/usr_cleaner',json={'active':False}).status_code == 200
        assert client.delete('/api/reservations/res_terra_next').status_code == 200
        cookie = client.cookies.get('rosa_session')
        encryption_key = os.environ['ROSA_ENCRYPTION_KEY']
        database = app.DB_PATH
        assert database == storage.root/'workspace.db' and app.DEMO_MODE is False
        assert client.post('/api/demo/reset').status_code == 404
    assert database.is_file()
    # New storage context plus full FastAPI lifespan: no reseeding/password changes.
    with workspace(tmp_path) as (storage, client):
        assert not storage.fresh and os.environ['ROSA_ENCRYPTION_KEY'] == encryption_key
        assert client.get('/api/development/workspace').json()['workspace_id'] == marker['workspace_id']
        client.cookies.set('rosa_session',cookie)
        assert client.get('/api/me').status_code == 200
        login(client)
        detail = client.get(f'/api/reservations/{rid}/detail').json()
        assert detail['reservation']['guest_name'] == booking()['guest_name']
        assert detail['reservation']['total_huf'] == 123456
        assert detail['reservation']['arrival_time'] == '18:30'
        assert detail['reservation']['registration_status'] == 'pending'
        assert any(x['body']=='Fictional persistent note' for x in detail['notes'])
        sensitive=client.get(f'/api/registration/{rid}/sensitive').json()
        assert next(x for x in sensitive if x['id']==gid)['sensitive']['address']=='Synthetic address'
        team=client.get('/api/team/overview').json()
        assert next(x for x in team['members'] if x['id']=='usr_cleaner')['active']==0
        assert next(x for x in team['workload'] if x['id']==task)['assigned_to']==member
        assert client.get('/api/reservations/res_terra_next/detail').json()['reservation']['status']=='cancelled'
        assert client.get('/api/organization').json()['operating_mode']=='assist'


def test_persistent_guard_blocks_external_databases_config_network_and_reset(tmp_path, monkeypatch):
    monkeypatch.setenv('ROSA_DATABASE_URL','postgresql://fake.invalid/never-open')
    monkeypatch.setenv('ROSA_APP_ENV','production')
    monkeypatch.setenv('ROSA_CHANNEX_API_KEY','fictional-poison-not-a-real-key')
    with workspace(tmp_path,PASSWORD) as (storage,client):
        assert app.DB_BACKEND=='sqlite' and app.APP_ENV=='test' and not app.CHANNEX_API_KEY
        assert os.environ['ROSA_DATABASE_URL']=='sqlite:///'+str(storage.root/'workspace.db')
        assert (storage.root/'.env.local').read_text()==''
        assert app._load_local_env(Path(__file__).resolve().parents[1]/'.env.local') is None
        for target in [tmp_path/'production.db', ':memory:', 'file:production.db?mode=rw']:
            with pytest.raises(TestSafetyError): sqlite3.connect(target)
        with pytest.raises(TestSafetyError): socket.create_connection(('example.invalid',443))
        with pytest.raises(TestSafetyError): app.init_db(reset=True)
        assert client.get('/api/client/environment').status_code==404


def test_no_reseed_deleted_seed_data_or_bootstrap_when_owner_is_suspended(tmp_path):
    with workspace(tmp_path,PASSWORD) as (storage,client):
        login(client)
        with app.db() as con:
            con.execute("UPDATE users SET active=0 WHERE id='usr_owner'")
            con.execute("DELETE FROM inbox_messages WHERE id='msg_direct_inquiry'")
    with workspace(tmp_path,'different-unused-password') as (storage,client):
        with app.db() as con:
            assert con.execute("SELECT active FROM users WHERE id='usr_owner'").fetchone()['active']==0
            assert not con.execute("SELECT 1 FROM inbox_messages WHERE id='msg_direct_inquiry'").fetchone()
        assert client.post('/api/login',json={'email':'owner@workspace.invalid','password':PASSWORD}).status_code==401


def test_owned_reset_is_explicit_offline_and_changes_workspace_identity(tmp_path):
    with workspace(tmp_path,PASSWORD) as (storage,client):
        old_id=client.get('/api/development/workspace').json()['workspace_id']
        with pytest.raises(ValueError): storage.reset('no')
        with pytest.raises(RuntimeError): storage.reset(RESET_CONFIRMATION)
    store=PersistentDevelopment(_test_parent=tmp_path)
    archive=store.reset(RESET_CONFIRMATION)
    assert archive.is_relative_to(tmp_path/'.development') and (archive/'workspace.db').is_file()
    assert not store.storage.exists()
    with workspace(tmp_path,'new-fictional-password') as (storage,client):
        assert client.get('/api/development/workspace').json()['workspace_id']!=old_id
        assert client.post('/api/login',json={'email':'owner@workspace.invalid','password':PASSWORD}).status_code==401
        login(client,'new-fictional-password')


def test_refuse_existing_unowned_or_mismatched_database(tmp_path):
    store=PersistentDevelopment(_test_parent=tmp_path)
    store.storage.mkdir(parents=True)
    (store.storage/'unrelated.txt').write_text('fictional unowned data')
    with pytest.raises(RuntimeError): store.inspect()
    with pytest.raises(RuntimeError): store.reset(RESET_CONFIRMATION)
    assert (store.storage/'unrelated.txt').read_text()=='fictional unowned data'


def test_mismatched_owned_database_is_rejected_before_schema_initialization(tmp_path):
    with workspace(tmp_path,PASSWORD) as (storage,client):
        pass
    # Corrupt only the dedicated fictional marker, never another database.
    metadata=json.loads((storage.root/'workspace.json').read_text())
    metadata['workspace_id']='fictional-mismatched-identity-123456'
    (storage.root/'workspace.json').write_text(json.dumps(metadata))
    with pytest.raises(RuntimeError,match='does not match'):
        with workspace(tmp_path): pass


def test_missing_database_is_not_silently_recreated(tmp_path):
    with workspace(tmp_path,PASSWORD) as (storage,client): pass
    (storage.root/'workspace.db').unlink()
    with pytest.raises(RuntimeError,match='missing'):
        with workspace(tmp_path): pass


def test_disposable_mode_remains_fresh_and_temporary():
    routes=list(app.app.router.routes)
    try:
        for _ in range(2):
            with IsolatedEnvironment() as storage:
                storage.protect_app(app)
                prepare_workspace(app,storage,PASSWORD)
                with TestClient(app.app) as client:
                    login(client)
                    marker=client.get('/api/development/workspace').json()['workspace_id']
                    if _==0:
                        rid=client.post('/api/reservations',json=booking()).json()['id']
                        first=marker
                    else:
                        assert marker!=first
                        assert client.get(f'/api/reservations/{rid}/detail').status_code==404
                root=storage.root
            assert not root.exists()
            app.app.router.routes[:]=routes
    finally:
        app.app.router.routes[:]=routes
