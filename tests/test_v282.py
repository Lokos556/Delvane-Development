import sys
from pathlib import Path
from fastapi.testclient import TestClient

sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import app as rosa


def fresh(tmp_path,monkeypatch,email='owner@demo.rosa',password='rosa-owner'):
    monkeypatch.setattr(rosa,'DB_PATH',tmp_path/'v282.db')
    rosa.init_db(reset=True)
    c=TestClient(rosa.app)
    r=c.post('/api/login',json={'email':email,'password':password})
    assert r.status_code==200,r.text
    c.headers.update({'X-Rosa-CSRF':r.json()['csrf_token']})
    return c


def test_v282_schema_runtime_and_team_overview(tmp_path,monkeypatch):
    c=fresh(tmp_path,monkeypatch)
    runtime=c.get('/api/system/runtime').json()
    assert runtime['version']=='2.10.27'
    assert runtime['schema_version']==3056
    with rosa.db() as con:
        mig=con.execute('SELECT name FROM schema_migrations WHERE version=2820').fetchone()
        assert mig and mig['name']=='team_and_access_workspace'
        cols=rosa.table_columns(con,'users')
        assert {'phone','job_title','created_at','updated_at'} <= cols
    d=c.get('/api/team/overview')
    assert d.status_code==200,d.text
    body=d.json()
    assert body['can_manage'] is True
    assert body['stats']['active']>=4
    assert {'owner','manager','cleaner','maintenance'} <= set(body['roles'])
    assert all('permission_groups' in m for m in body['members'])


def test_owner_can_create_worker_and_generated_password_really_logs_in(tmp_path,monkeypatch):
    c=fresh(tmp_path,monkeypatch)
    r=c.post('/api/team/members',json={'full_name':'Kata Test','email':'kata.test@example.com','role':'cleaner','phone':'+36 30 111 2222','job_title':'Housekeeper'})
    assert r.status_code==200,r.text
    out=r.json(); password=out['setup_password']; uid=out['member_id']
    assert len(password)>=12
    with rosa.db() as con:
        row=con.execute('SELECT * FROM users WHERE id=?',(uid,)).fetchone()
        assert row['role']=='cleaner' and row['phone']=='+36 30 111 2222'
        assert row['password_hash']!=password
        sec=con.execute('SELECT * FROM user_security WHERE user_id=?',(uid,)).fetchone()
        assert sec and sec['email_verified']==0
    other=TestClient(rosa.app)
    login=other.post('/api/login',json={'email':'kata.test@example.com','password':password})
    assert login.status_code==200,login.text
    assert other.get('/api/me').json()['role']=='cleaner'


def test_manager_can_view_team_but_cannot_create_accounts(tmp_path,monkeypatch):
    c=fresh(tmp_path,monkeypatch)
    # Owner creates a manager first.
    r=c.post('/api/team/members',json={'full_name':'Mira Manager','email':'mira@example.com','role':'manager'})
    pwd=r.json()['setup_password']
    manager=TestClient(rosa.app)
    lr=manager.post('/api/login',json={'email':'mira@example.com','password':pwd}); assert lr.status_code==200
    manager.headers.update({'X-Rosa-CSRF':lr.json()['csrf_token']})
    overview=manager.get('/api/team/overview'); assert overview.status_code==200
    assert overview.json()['can_manage'] is False
    denied=manager.post('/api/team/members',json={'full_name':'No Access','email':'no@example.com','role':'cleaner'})
    assert denied.status_code==403


def test_suspend_member_revokes_sessions_and_restore_is_possible(tmp_path,monkeypatch):
    c=fresh(tmp_path,monkeypatch)
    r=c.post('/api/team/members',json={'full_name':'Session Worker','email':'session@example.com','role':'maintenance'})
    uid,pwd=r.json()['member_id'],r.json()['setup_password']
    worker=TestClient(rosa.app)
    lr=worker.post('/api/login',json={'email':'session@example.com','password':pwd}); assert lr.status_code==200
    assert worker.get('/api/me').status_code==200
    s=c.patch(f'/api/team/members/{uid}',json={'active':False}); assert s.status_code==200,s.text
    assert worker.get('/api/me').status_code==401
    restore=c.patch(f'/api/team/members/{uid}',json={'active':True}); assert restore.status_code==200
    assert worker.post('/api/login',json={'email':'session@example.com','password':pwd}).status_code==200


def test_reset_access_rotates_password_and_revokes_previous_login(tmp_path,monkeypatch):
    c=fresh(tmp_path,monkeypatch)
    r=c.post('/api/team/members',json={'full_name':'Reset Worker','email':'reset@example.com','role':'cleaner'})
    uid,old=r.json()['member_id'],r.json()['setup_password']
    worker=TestClient(rosa.app); assert worker.post('/api/login',json={'email':'reset@example.com','password':old}).status_code==200
    rr=c.post(f'/api/team/members/{uid}/reset-access'); assert rr.status_code==200,rr.text
    new=rr.json()['setup_password']; assert new!=old
    assert worker.get('/api/me').status_code==401
    fresh_login=TestClient(rosa.app)
    assert fresh_login.post('/api/login',json={'email':'reset@example.com','password':old}).status_code==401
    assert fresh_login.post('/api/login',json={'email':'reset@example.com','password':new}).status_code==200


def test_team_mutations_are_tenant_scoped_and_self_lockout_is_blocked(tmp_path,monkeypatch):
    c=fresh(tmp_path,monkeypatch)
    assert c.patch('/api/team/members/usr_owner',json={'active':False}).status_code==400
    assert c.patch('/api/team/members/usr_owner',json={'role':'cleaner'}).status_code==400
    assert c.patch('/api/team/members/usr_other_owner',json={'job_title':'stolen'}).status_code==404
    assert c.post('/api/team/members/usr_other_owner/reset-access').status_code==404


def test_team_workload_contains_cleaning_and_maintenance_signals(tmp_path,monkeypatch):
    c=fresh(tmp_path,monkeypatch)
    d=c.get('/api/team/overview').json()
    anna=next(m for m in d['members'] if m['id']=='usr_cleaner')
    balint=next(m for m in d['members'] if m['id']=='usr_maint')
    assert 'upcoming_cleaning' in anna and 'open_maintenance' in balint
    assert isinstance(d['workload'],list)
    assert all({'kind','property_name','assigned_name','status'} <= set(x) for x in d['workload'])


def test_frontend_team_is_people_access_and_workload_not_task_only():
    root=Path(__file__).resolve().parents[1]
    js=(root/'static'/'app.js').read_text(encoding='utf-8')
    css=(root/'static'/'styles.css').read_text(encoding='utf-8')
    block=js[js.index('// ROSA V2.8.2'):]
    assert '/api/team/overview' in block
    assert '+ Add team member' in block
    assert 'People <span>' in block
    assert 'Access & roles' in block
    assert 'Workload' in block
    assert '/api/team/members/' in block
    assert 'Reset access' in block and 'Revoke sessions' in block
    assert 'This password is shown once' in block
    assert '.v282-people-grid' in css and '.v282-role-grid' in css and '.v282-work-table' in css
