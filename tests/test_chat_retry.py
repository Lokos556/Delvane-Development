"""Retries of one accepted turn must not create duplicate conversation messages."""
import app
import pytest
import threading
from concurrent.futures import ThreadPoolExecutor
from test_flutter_reservation_reception import client, login
from test_persistent_development import workspace, PASSWORD, login as persistent_login, booking


def test_same_turn_is_returned_once_after_lost_response(client):
    login(client)
    payload={'message':'Hány foglalásom van összesen?','language':'hu',
             'client_request_id':'0123456789abcdef0123456789abcdef'}
    first=client.post('/api/rosa/chat',json=payload)
    second=client.post('/api/rosa/chat',json=payload)
    assert first.status_code==second.status_code==200
    assert first.json()['answer']==second.json()['answer']
    history=client.get('/api/rosa/conversation').json()['messages']
    assert len(history)==2
    assert [m['role'] for m in history]==['user','rosa']
    with app.db() as con:
        assert con.execute("SELECT COUNT(*) c FROM audit_events WHERE event_type='rosa.chat'").fetchone()['c']==1


def test_retry_identifier_cannot_be_reused_for_different_content_or_user(client):
    login(client)
    payload={'message':'Who arrives tomorrow?','client_request_id':'a'*32}
    assert client.post('/api/rosa/chat',json=payload).status_code==200
    assert client.post('/api/rosa/chat',json={**payload,'message':'Different question'}).status_code==409
    assert client.post('/api/rosa/chat',json={**payload,'language':'hu'}).status_code==409
    login(client,'manager')
    response=client.post('/api/rosa/chat',json=payload)
    assert response.status_code==200
    with app.db() as con:
        assert con.execute("SELECT COUNT(*) c FROM rosa_chat_messages WHERE role='user'").fetchone()['c']==2


@pytest.mark.parametrize('key',['','invalid','x'*32,'a'*33])
def test_invalid_retry_id_keeps_validation(client,key):
    login(client)
    assert client.post('/api/rosa/chat',json={'message':'Who arrives tomorrow?','client_request_id':key}).status_code==400


def test_retry_after_rolled_back_attempt_can_complete(client,monkeypatch):
    login(client)
    original=app._owner_assistant_reply
    calls=[]
    def temporary_failure(*args,**kwargs):
        calls.append(1)
        if len(calls)==1:raise app.HTTPException(503,'Temporary fictional failure')
        return original(*args,**kwargs)
    monkeypatch.setattr(app,'_owner_assistant_reply',temporary_failure)
    payload={'message':'Who arrives tomorrow?','client_request_id':'b'*32}
    assert client.post('/api/rosa/chat',json=payload).status_code==503
    assert client.post('/api/rosa/chat',json=payload).status_code==200
    assert len(client.get('/api/rosa/conversation').json()['messages'])==2


def test_simultaneous_copies_compute_and_persist_once(client,monkeypatch):
    login(client)
    started=threading.Event();release=threading.Event();calls=[]
    original=app._owner_assistant_reply
    def slow(*args,**kwargs):
        calls.append(1);started.set()
        assert release.wait(5)
        return original(*args,**kwargs)
    monkeypatch.setattr(app,'_owner_assistant_reply',slow)
    payload={'message':'Who arrives tomorrow?','client_request_id':'c'*32}
    with ThreadPoolExecutor(max_workers=2) as pool:
        first=pool.submit(client.post,'/api/rosa/chat',json=payload)
        assert started.wait(5)
        second=pool.submit(client.post,'/api/rosa/chat',json=payload)
        release.set()
        assert first.result(timeout=10).status_code==200
        assert second.result(timeout=10).status_code==200
    assert calls==[1]
    assert len(client.get('/api/rosa/conversation').json()['messages'])==2


def test_saved_turn_replays_after_persistent_restart_without_recomputing(tmp_path):
    payload={'message':'How many reservations do I have?','client_request_id':'d'*32}
    with workspace(tmp_path,PASSWORD) as (_,c):
        persistent_login(c)
        first=c.post('/api/rosa/chat',json=payload).json()
        assert c.post('/api/reservations',json=booking()).status_code==200
    with workspace(tmp_path) as (_,c):
        persistent_login(c)
        replay=c.post('/api/rosa/chat',json=payload).json()
        assert replay==first
        assert len(c.get('/api/rosa/conversation').json()['messages'])==2
        fresh=c.post('/api/rosa/chat',json={**payload,'client_request_id':'e'*32}).json()
        assert fresh['facts']['count']==first['facts']['count']+1
