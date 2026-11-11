import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from fastapi.testclient import TestClient
import app as rosa


def fresh(tmp_path, monkeypatch):
    db_file=tmp_path/'v22.db'
    monkeypatch.setattr(rosa,'DB_PATH',db_file)
    rosa.init_db(reset=True)
    return TestClient(rosa.app)


def login(client,email='owner@demo.rosa',password='rosa-owner',attach=True):
    r=client.post('/api/login',json={'email':email,'password':password})
    assert r.status_code==200,r.text
    if attach:
        client.headers.update({'X-Rosa-CSRF':r.json()['csrf_token']})
    return r


def test_csrf_hashed_sessions_and_security_headers(tmp_path,monkeypatch):
    c=fresh(tmp_path,monkeypatch)
    r=login(c,attach=False)
    # Authenticated mutations without the per-session CSRF token are rejected.
    denied=c.patch('/api/organization/mode',json={'mode':'assist'})
    assert denied.status_code==403
    c.headers.update({'X-Rosa-CSRF':r.json()['csrf_token']})
    assert c.patch('/api/organization/mode',json={'mode':'assist'}).status_code==200
    me=c.get('/api/me')
    assert me.status_code==200 and me.json()['operating_mode']=='assist'
    assert me.headers['x-frame-options']=='DENY'
    with rosa.db() as con:
        session=con.execute('SELECT token_hash,csrf_token FROM secure_sessions').fetchone()
        cookie=c.cookies.get('rosa_session')
        assert cookie and session['token_hash'] != cookie
        assert len(session['token_hash'])==64


def test_tenant_isolation_and_least_privilege(tmp_path,monkeypatch):
    c=fresh(tmp_path,monkeypatch)
    login(c)
    names=[r['guest_name'] for r in c.get('/api/reservations').json()]
    assert 'Isolation Secret Guest' not in names
    assert c.get('/api/properties/prop_other/overview').status_code==404
    assert not any(x['title']=='Isolation Secret Guest' for x in c.get('/api/search?q=Isolation').json()['results'])
    c.post('/api/logout')
    login(c,'cleaner@demo.rosa','rosa-cleaner')
    assert c.get('/api/reservations').status_code==403
    assert c.get('/api/guests').status_code==403
    assert c.get('/api/registration').status_code==403
    assert c.get('/api/audit').status_code==403


def test_observe_records_without_mutating_then_assist_executes(tmp_path,monkeypatch):
    c=fresh(tmp_path,monkeypatch)
    login(c)
    before=next(r for r in c.get('/api/reservations').json() if r['id']=='res_terra_next')
    assert before['arrival_time']=='15:30'
    analyzed=c.post('/api/inbox/msg_terra_arrival/analyze')
    assert analyzed.status_code==200
    assert analyzed.json()['auto_applied']
    after=next(r for r in c.get('/api/reservations').json() if r['id']=='res_terra_next')
    assert after['arrival_time']=='15:30'
    actions=c.get('/api/rosa/actions').json()
    assert any(a['status']=='simulated' and a['action_type']=='update_arrival_time' for a in actions)
    assert c.patch('/api/organization/mode',json={'mode':'assist'}).status_code==200
    body=analyzed.json()
    applied=c.post('/api/inbox/msg_terra_arrival/apply',json={'draft_reply':body['draft_reply']})
    assert applied.status_code==200
    changed=next(r for r in c.get('/api/reservations').json() if r['id']=='res_terra_next')
    assert changed['arrival_time']=='20:30'
    executed=[a for a in c.get('/api/rosa/actions').json() if a['status']=='executed' and a['action_type']=='update_arrival_time']
    assert executed and executed[0]['reversible']
    assert c.post(f"/api/rosa/actions/{executed[0]['id']}/undo").status_code==200
    restored=next(r for r in c.get('/api/reservations').json() if r['id']=='res_terra_next')
    assert restored['arrival_time']=='15:30'


def test_guest_registration_integration_memory_foundation(tmp_path,monkeypatch):
    c=fresh(tmp_path,monkeypatch)
    login(c)
    guests=c.get('/api/guests')
    assert guests.status_code==200
    daniel=next(g for g in guests.json() if g['full_name']=='Daniel Weber')
    assert daniel['stays']>=2
    assert any(p['preference_key']=='high_chair' for p in daniel['preferences'])
    assert c.post(f"/api/guests/{daniel['id']}/preferences",json={'preference_key':'pillow','preference_value':'extra pillow'}).status_code==200
    detail=c.get(f"/api/guests/{daniel['id']}").json()
    assert any(p['preference_key']=='pillow' for p in detail['preferences'])
    reg=c.get('/api/registration')
    assert reg.status_code==200 and any(x['state'] in ('ready','waiting','needs_owner') for x in reg.json())
    integrations=c.get('/api/integrations')
    assert integrations.status_code==200 and len(integrations.json())>=6
    assert all(x['status'] in ('not_connected','sandbox') for x in integrations.json())
    memory=c.get('/api/memory')
    assert memory.status_code==200 and memory.json()['business']


def test_security_audit_sessions_and_retention(tmp_path,monkeypatch):
    c=fresh(tmp_path,monkeypatch)
    login(c)
    sec=c.get('/api/security')
    assert sec.status_code==200
    data=sec.json()
    assert data['password_scheme']=='scrypt'
    assert data['csrf']=='per-session token'
    assert data['tenant_scope']=='server-side organization_id'
    assert data['sessions']
    audit=c.get('/api/audit').json()
    assert any(x['event_type']=='auth.login' for x in audit)
    retention=c.get('/api/retention').json()
    identity=next(x for x in retention if x['data_class']=='identity_document')
    assert identity['retention_days'] is None
    assert 'Do not store passport scans' in identity['description']
