"""Real API mutation validation under the repository's temporary-data guards."""
from datetime import timedelta
import pytest
from fastapi.testclient import TestClient
import app


@pytest.fixture
def client(request):
    safety=request.config._delvane_safety
    assert app.DB_PATH.resolve().is_relative_to(safety.root)
    assert not app.CHANNEX_API_KEY and not app.OPENAI_API_KEY
    app.init_db()
    with app.db() as con:
        con.execute("INSERT INTO users(id,organization_id,full_name,email,password_hash,role,active) VALUES (?,?,?,?,?,?,1)",
                    ('port_manager','org_casa_rosa','Synthetic Manager','manager@port.invalid',app.hash_password('synthetic-port-password'),'manager'))
    with TestClient(app.app) as client:
        yield client


def login(client,role='owner'):
    email,password={'owner':('owner@demo.rosa','rosa-owner'),'manager':('manager@port.invalid','synthetic-port-password'),
                    'cleaner':('cleaner@demo.rosa','rosa-cleaner'),'maintenance':('maintenance@demo.rosa','rosa-maintenance')}[role]
    response=client.post('/api/login',json={'email':email,'password':password})
    assert response.status_code==200
    client.headers['X-Rosa-CSRF']=response.json()['csrf_token']


def body():
    arrival=app.date.today()+timedelta(days=100)
    return {'property_id':'prop_flora','guest_name':'Synthetic port guest','source':'Direct',
            'arrival_date':str(arrival),'departure_date':str(arrival+timedelta(days=2)),
            'guest_count':2,'total_huf':9007199254740993,'special_requests':['Cot'],
            'arrival_time':'16:00','external_ref':'SYNTHETIC-PORT'}


@pytest.mark.parametrize('role',['owner','manager'])
def test_native_booking_create_edit_notes_history_and_cancel(client,role):
    login(client,role)
    made=client.post('/api/reservations',json=body())
    assert made.status_code==200
    rid=made.json()['id']
    detail=client.get(f'/api/reservations/{rid}/detail').json()
    assert detail['reservation']['total_huf']==9007199254740993
    assert detail['reservation']['guest_count']==2
    assert client.post('/api/reservations',json=body()).status_code==409
    assert client.patch(f'/api/reservations/{rid}',json={'arrival_time':'20:30','guest_count':1}).status_code==200
    assert client.patch(f'/api/reservations/{rid}/operations',json={'payment_status':'partial','arrival_time':'20:30'}).status_code==200
    assert client.post(f'/api/reservations/{rid}/notes',json={'body':'Synthetic internal note'}).status_code==200
    detail=client.get(f'/api/reservations/{rid}/detail').json()
    assert detail['reservation']['arrival_time']=='20:30'
    assert detail['reservation']['payment_status']=='partial'
    assert detail['notes'][0]['body']=='Synthetic internal note'
    assert detail['events']
    assert client.delete(f'/api/reservations/{rid}').status_code==200
    detail=client.get(f'/api/reservations/{rid}/detail').json()
    assert detail['reservation']['status']=='cancelled'
    assert any(e['event_type']=='cancelled' for e in detail['events'])


def test_room_types_rate_plans_validation_and_tenant_boundaries(client):
    login(client)
    rooms=client.get('/api/properties/prop_flora/room-types').json()['room_types']
    assert rooms and 'rate_plans' in rooms[0]
    assert client.get('/api/properties/prop_flora/rate-plans').status_code==200
    assert client.get('/api/properties/prop_other/room-types').status_code==404
    invalid=body();invalid['departure_date']=invalid['arrival_date']
    assert client.post('/api/reservations',json=invalid).status_code==400
    invalid=body();invalid['room_type_id']='not-a-room'
    assert client.post('/api/reservations',json=invalid).status_code==404


@pytest.mark.parametrize('role',['cleaner','maintenance'])
def test_worker_mutations_and_guest_message_reads_are_denied(client,role):
    login(client,role)
    assert client.post('/api/reservations',json=body()).status_code==403
    assert client.patch('/api/reservations/res_terra_next',json={'arrival_time':'22:00'}).status_code==403
    assert client.delete('/api/reservations/res_terra_next').status_code==403
    assert client.get('/api/inbox').status_code==403
    assert client.post('/api/inbox',json={'body':'Synthetic denied'}).status_code==403
    assert client.get('/api/communications/outbox').status_code==403


def test_reception_arrival_preparation_draft_and_mark_replied_are_distinct(client):
    login(client)
    assert client.patch('/api/organization/mode',json={'mode':'assist'}).status_code==200
    mid='msg_terra_arrival'
    analyzed=client.post(f'/api/inbox/{mid}/analyze')
    assert analyzed.status_code==200
    assert analyzed.json()['extracted']['arrival_time']=='20:30'
    assert 'High chair' in analyzed.json()['extracted']['special_requests']
    assert client.post(f'/api/inbox/{mid}/draft',json={'tone':'warm_concise'}).json()['provider']=='local'
    assert client.patch(f'/api/inbox/{mid}/draft',json={'draft_reply':'Saved synthetic draft'}).status_code==200
    applied=client.post(f'/api/inbox/{mid}/apply',json={'draft_reply':'Saved synthetic draft'})
    assert applied.status_code==200
    detail=client.get('/api/reservations/res_terra_next/detail').json()
    assert detail['reservation']['arrival_time']=='20:30'
    assert 'High chair' in app.json.loads(detail['reservation']['special_requests'])
    assert client.post(f'/api/inbox/{mid}/reply-sent',json={'draft_reply':'Saved synthetic draft'}).status_code==200
    assert next(m for m in client.get('/api/inbox').json() if m['id']==mid)['status']=='replied'
    assert client.get('/api/reception/summary').json()['external_sending_connected'] is False
    assert client.post(f'/api/inbox/{mid}/archive').status_code==200
    assert not any(m['id']==mid for m in client.get('/api/inbox').json())


def test_reception_inquiry_and_approved_scheduled_messages_stay_local(client):
    login(client)
    assert client.patch('/api/organization/mode',json={'mode':'assist'}).status_code==200
    mid='msg_direct_inquiry'
    assert client.post(f'/api/inbox/{mid}/analyze').status_code==200
    applied=client.post(f'/api/inbox/{mid}/apply',json={})
    assert applied.status_code==200
    rid=applied.json()['reservation_id']
    assert client.get(f'/api/reservations/{rid}/detail').json()['reservation']['status']=='inquiry'
    assert client.patch(f'/api/reservations/{rid}',json={'status':'confirmed'}).status_code==200
    assert client.post('/api/automation/run').status_code==200
    item=next(x for x in client.get('/api/communications/outbox').json() if x['status']=='awaiting_approval')
    oid=item['id']
    assert client.patch(f'/api/communications/outbox/{oid}',json={'body':'Synthetic scheduled edit'}).status_code==200
    assert client.post(f'/api/communications/outbox/{oid}/approve').json()['external_send'] is False
    assert client.post(f'/api/communications/outbox/{oid}/simulate-send').json()=={'ok':True,'status':'simulated_sent','external_send':False}
    assert client.patch(f'/api/communications/outbox/{oid}',json={'status':'cancelled'}).status_code==200
    assert client.post(f'/api/communications/outbox/{oid}/approve').status_code==409


def test_manual_message_links_and_identity_review_use_only_disposable_records(client):
    login(client)
    payload=body();payload['guest_count']=1
    made=client.post('/api/reservations',json=payload)
    assert made.status_code==200
    rid=made.json()['id']
    created=client.post('/api/inbox',json={'source':'Direct email','sender_name':'Synthetic intake',
      'reservation_id':rid,'subject':'Synthetic request','body':'Please prepare a cot.'})
    assert created.status_code==200
    item=next(x for x in client.get('/api/inbox').json() if x['id']==created.json()['id'])
    assert item['reservation_id']==rid and item['property_id']=='prop_flora'
    links=client.get(f'/api/reservations/{rid}/guest-checkin-links')
    assert links.status_code==200 and len(links.json()['links'])==1
    status=client.get(f'/api/reservations/{rid}/guest-checkin-status').json()
    gid=status['guests'][0]['id']
    endpoint=f'/api/reservations/{rid}/guests/{gid}/verify'
    assert client.post(endpoint,json={'decision':'verify','verification_method':'manual_review'}).status_code==409
    # Synthetic submitted fixture, not a document scan or operational identity record.
    with app.db() as con:
        con.execute("UPDATE guest_records SET full_name='Synthetic submitted guest',completeness='complete' WHERE id=?",(gid,))
    verified=client.post(endpoint,json={'decision':'verify','verification_method':'manual_review','review_note':'Synthetic test review'})
    assert verified.status_code==200 and verified.json()['registration_status']=='complete'
    after=client.get(f'/api/reservations/{rid}/guest-checkin-status').json()
    assert after['guests'][0]['verification_status']=='verified'
    # Queueing is a local event, not an assertion of government transport/acceptance.
    assert verified.json()['government_submission_queued'] is True


def test_automation_rule_edits_are_persisted_without_external_delivery(client):
    login(client)
    rule=client.get('/api/automation/rules').json()[0]
    updated=client.patch(f"/api/automation/rules/{rule['id']}",json={'enabled':False,'authority_mode':'never'})
    assert updated.status_code==200 and updated.json()['enabled'] is False
    saved=next(r for r in client.get('/api/automation/rules').json() if r['id']==rule['id'])
    assert saved['authority_mode']=='never' and saved['enabled']==0
    assert client.get('/api/reception/summary').json()['external_sending_connected'] is False
