import sys
from pathlib import Path
from datetime import date, timedelta
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from fastapi.testclient import TestClient
import app as rosa


def login(client,email,password):
    r=client.post('/api/login',json={'email':email,'password':password})
    assert r.status_code==200, r.text
    client.headers.update({'X-Rosa-CSRF':r.json()['csrf_token']})


def test_role_faces_and_cleaning_flow(tmp_path, monkeypatch):
    db_file=tmp_path/'test.db'
    monkeypatch.setattr(rosa,'DB_PATH',db_file)
    rosa.init_db(reset=True)
    client=TestClient(rosa.app)

    login(client,'owner@demo.rosa','rosa-owner')
    me=client.get('/api/me').json()
    assert me['role']=='owner'
    owner=client.get('/api/owner/dashboard')
    assert owner.status_code==200
    assert len(owner.json()['properties'])==3
    assert client.get('/api/worker/dashboard').status_code==403
    client.post('/api/logout')

    login(client,'cleaner@demo.rosa','rosa-cleaner')
    worker=client.get('/api/worker/dashboard')
    assert worker.status_code==200
    tasks=worker.json()['tasks']
    assert tasks
    terra=next(t for t in tasks if t['property_name']=='Terra')
    assert terra['deadline_time']=='15:00'
    assert 'Extra towels' in terra['special_requests']
    assert client.get('/api/owner/dashboard').status_code==403

    r=client.post(f"/api/work-tasks/{terra['id']}/start")
    assert r.status_code==200
    after=client.get('/api/worker/dashboard').json()['tasks']
    terra2=next(t for t in after if t['id']==terra['id'])
    assert terra2['status']=='in_progress'

    r=client.post(f"/api/work-tasks/{terra['id']}/finish",json={'note':'Everything ready.'})
    assert r.status_code==200
    after=client.get('/api/worker/dashboard').json()['tasks']
    terra3=next(t for t in after if t['id']==terra['id'])
    assert terra3['status']=='complete'

def test_create_reservation_and_overlap_guard(tmp_path, monkeypatch):
    db_file=tmp_path/'reservations.db'
    monkeypatch.setattr(rosa,'DB_PATH',db_file)
    rosa.init_db(reset=True)
    client=TestClient(rosa.app)
    login_response = client.post('/api/login', json={'email':'owner@demo.rosa','password':'rosa-owner'})
    assert login_response.status_code == 200
    client.headers.update({'X-Rosa-CSRF':login_response.json()['csrf_token']})
    props = client.get('/api/properties').json()
    terra = next(p for p in props if p['name']=='Terra')
    a = date.today()+timedelta(days=20); d=a+timedelta(days=3)
    payload={'property_id':terra['id'],'guest_name':'V1.3 Test Guest','arrival_date':str(a),'departure_date':str(d),'guest_count':2,'source':'Direct','special_requests':['High chair']}
    made=client.post('/api/reservations',json=payload)
    assert made.status_code==200
    reservations=client.get('/api/reservations').json()
    assert any(r['guest_name']=='V1.3 Test Guest' for r in reservations)
    conflict=client.post('/api/reservations',json={**payload,'guest_name':'Overlap Guest'})
    assert conflict.status_code==409
    cancelled=client.delete('/api/reservations/'+made.json()['id'])
    assert cancelled.status_code==200

def test_owner_property_overview_and_attention_targets(tmp_path, monkeypatch):
    db_file=tmp_path/'overview.db'
    monkeypatch.setattr(rosa,'DB_PATH',db_file)
    rosa.init_db(reset=True)
    client=TestClient(rosa.app)
    login(client,'owner@demo.rosa','rosa-owner')

    dash=client.get('/api/owner/dashboard')
    assert dash.status_code==200
    body=dash.json()
    assert body['attention']
    assert all('property_id' in item for item in body['attention'])

    terra=next(p for p in body['properties'] if p['name']=='Terra')
    overview=client.get(f"/api/properties/{terra['id']}/overview")
    assert overview.status_code==200
    data=overview.json()
    assert data['same_day_turnover'] is True
    assert data['departing_today']['guest_name']=='Kovács Eszter'
    assert data['arriving_today']['guest_name']=='Daniel Weber'
    assert data['property']['checkout_time']=='10:00'
    assert data['property']['checkin_time']=='15:00'
    assert data['cleaning']['deadline_time']=='15:00'


def test_inbox_existing_guest_message_updates_reservation_and_cleaner(tmp_path, monkeypatch):
    db_file=tmp_path/'inbox-existing.db'
    monkeypatch.setattr(rosa,'DB_PATH',db_file)
    rosa.init_db(reset=True)
    client=TestClient(rosa.app)
    login(client,'owner@demo.rosa','rosa-owner')
    assert client.patch('/api/organization/mode',json={'mode':'assist'}).status_code==200

    items=client.get('/api/inbox')
    assert items.status_code==200
    msg=next(x for x in items.json() if x['id']=='msg_terra_arrival')
    assert msg['status']=='new'

    analyzed=client.post('/api/inbox/msg_terra_arrival/analyze')
    assert analyzed.status_code==200
    body=analyzed.json()
    assert body['kind']=='existing_guest'
    assert body['extracted']['arrival_time']=='20:30'
    assert 'High chair' in body['extracted']['special_requests']
    assert not any('Parking' in x for x in body['unresolved'])
    assert any(k['key']=='parking' for k in body['knowledge_used'])
    assert body['reply_authority']=='ask'

    applied=client.post('/api/inbox/msg_terra_arrival/apply',json={'draft_reply':body['draft_reply']})
    assert applied.status_code==200
    reservations=client.get('/api/reservations').json()
    terra=next(r for r in reservations if r['id']=='res_terra_next')
    assert terra['arrival_time']=='20:30'
    assert 'High chair' in rosa.json.loads(terra['special_requests'])

    client.post('/api/logout')
    login(client,'cleaner@demo.rosa','rosa-cleaner')
    tasks=client.get('/api/worker/dashboard').json()['tasks']
    terra_task=next(t for t in tasks if t['property_name']=='Terra')
    assert 'High chair' in terra_task['special_requests']
    assert '20:30' in terra_task['detail']


def test_direct_inbox_message_becomes_unconfirmed_inquiry(tmp_path, monkeypatch):
    db_file=tmp_path/'inbox-inquiry.db'
    monkeypatch.setattr(rosa,'DB_PATH',db_file)
    rosa.init_db(reset=True)
    client=TestClient(rosa.app)
    login(client,'owner@demo.rosa','rosa-owner')
    assert client.patch('/api/organization/mode',json={'mode':'assist'}).status_code==200

    analyzed=client.post('/api/inbox/msg_direct_inquiry/analyze')
    assert analyzed.status_code==200
    body=analyzed.json()
    assert body['kind']=='inquiry'
    assert body['extracted']['property_name']=='Terra'
    assert body['extracted']['guest_count']==3
    assert body['availability']=='available'
    assert body['extracted']['arrival_date']
    assert body['extracted']['departure_date']

    applied=client.post('/api/inbox/msg_direct_inquiry/apply',json={'draft_reply':body['draft_reply']})
    assert applied.status_code==200
    rid=applied.json()['reservation_id']
    reservations=client.get('/api/reservations').json()
    inquiry=next(r for r in reservations if r['id']==rid)
    assert inquiry['status']=='inquiry'
    assert inquiry['guest_name']=='Emma Brown'
    assert inquiry['guest_count']==3

    confirmed=client.patch(f'/api/reservations/{rid}',json={'status':'confirmed'})
    assert confirmed.status_code==200
    reservations=client.get('/api/reservations').json()
    confirmed_row=next(r for r in reservations if r['id']==rid)
    assert confirmed_row['status']=='confirmed'



def test_train_rosa_knowledge_override_changes_guest_reply(tmp_path, monkeypatch):
    db_file=tmp_path/'knowledge.db'
    monkeypatch.setattr(rosa,'DB_PATH',db_file)
    rosa.init_db(reset=True)
    client=TestClient(rosa.app)
    login(client,'owner@demo.rosa','rosa-owner')

    knowledge=client.get('/api/knowledge')
    assert knowledge.status_code==200
    body=knowledge.json()
    assert 'shared' in body['scopes']
    assert 'prop_terra' in body['scopes']
    assert body['authority']['refund']['mode']=='never'

    saved=client.put('/api/knowledge/prop_terra',json={'entries':{
        'parking':'Terra guests park in the private courtyard beside the apartment.',
        'wifi':'TerraNet / test-password'
    }})
    assert saved.status_code==200

    # Re-analyze the seeded Terra message. Property knowledge should replace the demo answer.
    analyzed=client.post('/api/inbox/msg_terra_arrival/analyze')
    assert analyzed.status_code==200
    data=analyzed.json()
    parking=next(k for k in data['knowledge_used'] if k['key']=='parking')
    assert parking['scope']=='prop_terra'
    assert parking['value']=='Terra guests park in the private courtyard beside the apartment.'
    assert 'private courtyard' in data['draft_reply']


def test_authority_auto_applies_safe_reservation_action(tmp_path, monkeypatch):
    db_file=tmp_path/'authority.db'
    monkeypatch.setattr(rosa,'DB_PATH',db_file)
    rosa.init_db(reset=True)
    client=TestClient(rosa.app)
    login(client,'owner@demo.rosa','rosa-owner')
    assert client.patch('/api/organization/mode',json={'mode':'autonomous'}).status_code==200

    changed=client.patch('/api/authority/update_arrival_time',json={'mode':'auto'})
    assert changed.status_code==200
    assert changed.json()['mode']=='auto'

    # Analysis itself now performs this authorized operational change.
    analyzed=client.post('/api/inbox/msg_terra_arrival/analyze')
    assert analyzed.status_code==200
    data=analyzed.json()
    assert any('arrival time' in x.lower() for x in data['auto_applied'])

    reservations=client.get('/api/reservations').json()
    terra=next(r for r in reservations if r['id']=='res_terra_next')
    assert terra['arrival_time']=='20:30'


def test_cleaner_cannot_read_or_edit_property_knowledge(tmp_path, monkeypatch):
    db_file=tmp_path/'knowledge-permissions.db'
    monkeypatch.setattr(rosa,'DB_PATH',db_file)
    rosa.init_db(reset=True)
    client=TestClient(rosa.app)
    login(client,'cleaner@demo.rosa','rosa-cleaner')
    assert client.get('/api/knowledge').status_code==403
    assert client.put('/api/knowledge/prop_terra',json={'entries':{'wifi':'secret'}}).status_code==403
    assert client.patch('/api/authority/refund',json={'mode':'auto'}).status_code==403
