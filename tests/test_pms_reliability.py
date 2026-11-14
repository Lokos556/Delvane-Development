"""Permissions and identity state contracts against guarded disposable API data."""
from datetime import timedelta
import pytest
import app
from test_flutter_reservation_reception import client, login, body


def cleaning(client, assignee='usr_cleaner', property_id='prop_flora'):
    response=client.post('/api/work-tasks',json={'property_id':property_id,'assigned_to':assignee,'title':'Synthetic work','scheduled_date':str(app.date.today())})
    assert response.status_code==200,response.text
    return response.json()['id']


@pytest.mark.parametrize('role',['owner','manager'])
def test_operator_assignment_and_immediate_worker_access(client,role):
    login(client,role)
    tid=cleaning(client)
    checklist=client.get(f'/api/work-tasks/{tid}/checklist').json()
    assert client.patch(f'/api/work-tasks/{tid}/assignment',json={'assigned_to':'usr_cleaner2'}).status_code==200
    login(client,'cleaner')
    assert client.get(f'/api/work-tasks/{tid}/checklist').status_code==404
    assert client.patch(f"/api/work-tasks/{tid}/checklist/{checklist[0]['id']}",json={'completed':True}).status_code==404
    assert client.post(f'/api/work-tasks/{tid}/start').status_code==404
    login(client,role)
    assert client.patch(f'/api/work-tasks/{tid}/assignment',json={'assigned_to':'usr_cleaner'}).status_code==200
    login(client,'cleaner')
    assert client.get(f'/api/work-tasks/{tid}/checklist').status_code==200
    assert client.post(f'/api/work-tasks/{tid}/start').status_code==200


@pytest.mark.parametrize('assignee',['usr_maint','usr_owner','not-found'])
def test_invalid_cleaning_assignee_is_rejected(client,assignee):
    login(client)
    tid=cleaning(client)
    assert client.patch(f'/api/work-tasks/{tid}/assignment',json={'assigned_to':assignee}).status_code==400


@pytest.mark.parametrize('role',['cleaner','maintenance'])
def test_worker_cannot_assign_create_or_read_foreign_task(client,role):
    login(client)
    tid=cleaning(client,None)
    login(client,role)
    assert client.post('/api/work-tasks',json={'property_id':'prop_flora','title':'Denied','scheduled_date':str(app.date.today())}).status_code==403
    assert client.patch(f'/api/work-tasks/{tid}/assignment',json={'assigned_to':'usr_cleaner'}).status_code==403
    assert client.get('/api/work-tasks/foreign/checklist').status_code in {403,404}


def test_cleaner_cross_property_reads_and_report_are_scoped(client):
    login(client)
    with app.db() as con:
        con.execute("UPDATE work_tasks SET assigned_to='usr_cleaner2' WHERE property_id='prop_flora'")
    login(client,'cleaner')
    assert 'prop_flora' not in {p['id'] for p in client.get('/api/operations/properties').json()}
    assert not any(m['property_id']=='prop_flora' for m in client.get('/api/maintenance').json())
    assert client.post('/api/maintenance',json={'property_id':'prop_flora','title':'Denied'}).status_code==404
    assert client.post('/api/maintenance',json={'property_id':'prop_other','title':'Denied'}).status_code==404


@pytest.mark.parametrize('route',['status','resolve'])
def test_maintenance_cannot_modify_other_assignment_or_steal_it(client,route):
    login(client)
    mid=client.post('/api/maintenance',json={'property_id':'prop_flora','title':'Synthetic'}).json()['id']
    with app.db() as con:
        con.execute("INSERT INTO users(id,organization_id,full_name,email,password_hash,role,active) VALUES (?,?,?,?,?,'maintenance',1)",('maint2','org_casa_rosa','Other','other@synthetic.invalid',app.hash_password('synthetic')))
        con.execute("UPDATE maintenance_cases SET assigned_to='maint2' WHERE id=?",(mid,))
    login(client,'maintenance')
    assert mid not in {m['id'] for m in client.get('/api/maintenance').json()}
    response=client.patch(f'/api/maintenance/{mid}/status',json={'status':'resolved','assigned_to':'usr_maint'}) if route=='status' else client.post(f'/api/maintenance/{mid}/resolve')
    assert response.status_code==404


def test_unassigned_maintenance_claim_and_operator_verification(client):
    login(client,'manager')
    mid=client.post('/api/maintenance',json={'property_id':'prop_flora','title':'Synthetic'}).json()['id']
    assert client.patch(f'/api/maintenance/{mid}/status',json={'status':'reported','assigned_to':''}).status_code==200
    login(client,'maintenance')
    assert client.patch(f'/api/maintenance/{mid}/status',json={'status':'in_progress','assigned_to':'usr_maint'}).status_code==403
    assert client.patch(f'/api/maintenance/{mid}/status',json={'status':'in_progress'}).status_code==200
    assert next(m for m in client.get('/api/maintenance').json() if m['id']==mid)['assigned_to']=='usr_maint'
    assert client.post(f'/api/maintenance/{mid}/resolve').status_code==200
    assert client.patch(f'/api/maintenance/{mid}/status',json={'status':'verified'}).status_code==403
    login(client,'manager')
    assert client.patch(f'/api/maintenance/{mid}/status',json={'status':'verified'}).status_code==200


def stay(client):
    payload=body();payload['guest_count']=1
    response=client.post('/api/reservations',json=payload); assert response.status_code==200,response.text
    rid=response.json()['id']
    links=client.get(f'/api/reservations/{rid}/guest-checkin-links').json()['links']
    token=links[0]['url'].rsplit('/',1)[-1]
    return rid,links[0]['guest_record_id'],token


IDENTITY={'full_name':'Synthetic Guest','date_of_birth':'2000-01-02','nationality':'HUN','document_type':'passport','document_number':'SYNTHETIC-PRIVATE','guest_confirmed':True}


def test_guest_submit_review_duplicates_and_sensitive_edit(client):
    login(client)
    rid,gid,token=stay(client)
    public=f'/api/public/checkin/{token}'
    assert client.post(public,json=IDENTITY).json()['verification_status']=='needs_review'
    assert client.post(public,json=IDENTITY).status_code==410
    state=client.get(f'/api/reservations/{rid}/guest-checkin-status').json()
    assert state['registration_status']=='pending' and len(state['guests'])==1
    assert 'SYNTHETIC-PRIVATE' not in str(state)
    assert client.get(f'/api/reservations/{rid}/detail').json()['reservation']['registration_status']=='pending'
    endpoint=f'/api/reservations/{rid}/guests/{gid}/verify'
    assert client.post(endpoint,json={'decision':'verify'}).json()['government_submission_queued'] is True
    assert client.post(endpoint,json={'decision':'verify'}).json()['government_submission_queued'] is False
    assert client.get(f'/api/reservations/{rid}/detail').json()['reservation']['registration_status']=='complete'
    with app.db() as con:
        assert con.execute('SELECT COUNT(*) c FROM guest_records WHERE reservation_id=?',(rid,)).fetchone()['c']==1
        assert con.execute('SELECT COUNT(*) c FROM government_scan_events WHERE reservation_id=?',(rid,)).fetchone()['c']==1
        assert con.execute("SELECT COUNT(*) c FROM government_outbox WHERE reservation_id=? AND event_type='guest.registration_verified'",(rid,)).fetchone()['c']==2
    assert client.put(f'/api/registration/records/{gid}/sensitive',json={'address':'Synthetic correction'}).status_code==200
    assert client.get(f'/api/reservations/{rid}/guest-checkin-status').json()['registration_status']=='pending'


@pytest.mark.parametrize('change',[{'status':'cancelled'},{'status':'inquiry'},{'arrival_date':'2030-01-01','departure_date':'2030-01-03'},{'guest_name':'Changed guest'}])
def test_edits_revoke_link_permanently(client,change):
    login(client)
    rid,gid,token=stay(client)
    assert client.patch(f'/api/reservations/{rid}',json=change).status_code==200
    assert client.get(f'/api/public/checkin/{token}').status_code==410
    if change.get('status'):
        assert client.patch(f'/api/reservations/{rid}',json={'status':'confirmed'}).status_code==200
        assert client.get(f'/api/public/checkin/{token}').status_code==410


@pytest.mark.parametrize('state',['expired','revoked','completed'])
def test_inactive_tokens_cannot_submit(client,state):
    login(client)
    rid,gid,token=stay(client)
    with app.db() as con:
        if state=='expired': con.execute('UPDATE guest_checkin_tokens SET expires_at=? WHERE reservation_id=?',('2000-01-01T00:00:00',rid))
        else: con.execute('UPDATE guest_checkin_tokens SET status=? WHERE reservation_id=?',(state,rid))
    assert client.get(f'/api/public/checkin/{token}').status_code==410
    assert client.post(f'/api/public/checkin/{token}',json=IDENTITY).status_code==410


def test_no_manual_identity_completion_and_invalid_transitions(client):
    login(client)
    rid,gid,token=stay(client)
    for path in [f'/api/reservations/{rid}',f'/api/reservations/{rid}/operations']:
        assert client.patch(path,json={'registration_status':'complete'}).status_code==409
    assert client.post(f'/api/reservations/{rid}/guests/{gid}/verify',json={'decision':'verify'}).status_code==409
    assert client.patch(f'/api/reservations/{rid}',json={'status':'invented'}).status_code==400
    assert client.post(f'/api/public/checkin/{token}',json={'full_name':'Synthetic','guest_confirmed':True}).status_code==400
    assert client.delete(f'/api/reservations/{rid}').status_code==200
    assert client.post(f'/api/reservations/{rid}/guests/{gid}/verify',json={'decision':'verify'}).status_code==409


def test_scanner_merge_is_not_identity_verification_or_sensitive_log(client):
    login(client)
    rid,gid,token=stay(client)
    path='/api/government/viza/id-scan'
    base={'reservation_id':rid,'guest_record_id':gid}
    assert client.post(path,json={**base,'full_name':'Synthetic'}).json()['registration_status']=='incomplete'
    fields={k:v for k,v in IDENTITY.items() if k not in {'guest_confirmed'}}
    assert client.post(path,json={**base,**fields}).json()['registration_status']=='pending'
    with app.db() as con:
        logs=[x['payload_json'] for x in con.execute('SELECT payload_json FROM government_scan_events WHERE reservation_id=?',(rid,))]
        assert 'SYNTHETIC-PRIVATE' not in str(logs)
    state=client.get(f'/api/reservations/{rid}/guest-checkin-status').json()
    assert state['guests'][0]['verification_status']=='needs_review'


def test_concurrent_public_submission_consumes_token_only_once(client):
    from concurrent.futures import ThreadPoolExecutor
    login(client)
    rid,gid,token=stay(client)
    with ThreadPoolExecutor(max_workers=2) as pool:
        statuses=list(pool.map(lambda _:client.post(f'/api/public/checkin/{token}',json=IDENTITY).status_code,range(2)))
    assert sorted(statuses)==[200,410]
    with app.db() as con:
        assert con.execute('SELECT COUNT(*) c FROM government_scan_events WHERE reservation_id=?',(rid,)).fetchone()['c']==1


def test_rejection_can_be_corrected_and_scanner_retry_preserves_review(client):
    login(client)
    rid,gid,token=stay(client)
    assert client.post(f'/api/public/checkin/{token}',json=IDENTITY).status_code==200
    review=f'/api/reservations/{rid}/guests/{gid}/verify'
    assert client.post(review,json={'decision':'reject'}).json()['registration_status']=='pending'
    replacement=client.get(f'/api/reservations/{rid}/guest-checkin-links').json()['links'][0]['url'].rsplit('/',1)[-1]
    assert client.post(f'/api/public/checkin/{replacement}',json=IDENTITY).status_code==200
    fields={k:v for k,v in IDENTITY.items() if k!='guest_confirmed'}
    scan={'reservation_id':rid,'guest_record_id':gid,**fields}
    assert client.post('/api/government/viza/id-scan',json=scan).status_code==200
    assert client.post(review,json={'decision':'verify'}).json()['registration_status']=='complete'
    retry=client.post('/api/government/viza/id-scan',json=scan)
    assert retry.json()['duplicate'] is True and retry.json()['registration_status']=='complete'


def test_guest_count_changes_preserve_identity_and_consistent_aggregate(client):
    login(client)
    rid,gid,token=stay(client)
    assert client.post(f'/api/public/checkin/{token}',json=IDENTITY).status_code==200
    review=f'/api/reservations/{rid}/guests/{gid}/verify'
    assert client.post(review,json={'decision':'verify'}).status_code==200
    assert client.patch(f'/api/reservations/{rid}',json={'guest_count':2}).status_code==200
    for _ in range(2):
        state=client.get(f'/api/reservations/{rid}/guest-checkin-status').json()
        assert state['registration_status']=='incomplete' and len(state['guests'])==2
    # Untouched spare slot can be removed; reviewed guest data remains intact.
    assert client.patch(f'/api/reservations/{rid}',json={'guest_count':1}).status_code==200
    state=client.get(f'/api/reservations/{rid}/guest-checkin-status').json()
    assert state['registration_status']=='complete' and len(state['guests'])==1
    assert state['guests'][0]['id']==gid


def test_foreign_tenant_task_and_identity_requests_are_not_disclosed(client):
    login(client)
    tid=cleaning(client)
    rid,gid,token=stay(client)
    result=client.post('/api/login',json={'email':'owner@isolation.demo','password':'rosa-isolation'})
    assert result.status_code==200
    client.headers['X-Rosa-CSRF']=result.json()['csrf_token']
    assert client.get(f'/api/work-tasks/{tid}/checklist').status_code==404
    assert client.patch(f'/api/work-tasks/{tid}/assignment',json={'assigned_to':None}).status_code==404
    assert client.get(f'/api/reservations/{rid}/guest-checkin-status').status_code==404
    assert client.post(f'/api/reservations/{rid}/guests/{gid}/verify',json={'decision':'verify'}).status_code==404


def test_role_change_revokes_cleaner_actions_on_next_request(client):
    login(client)
    tid=cleaning(client)
    login(client,'cleaner')
    assert client.get(f'/api/work-tasks/{tid}/checklist').status_code==200
    # Model an administrative role change without retaining a stale role in the session.
    with app.db() as con:
        con.execute("UPDATE users SET role='maintenance' WHERE id='usr_cleaner'")
    assert client.get(f'/api/work-tasks/{tid}/checklist').status_code==403


def test_explicit_csrf_is_still_required_for_assignment(client):
    login(client)
    tid=cleaning(client)
    client.headers.pop('X-Rosa-CSRF')
    assert client.patch(f'/api/work-tasks/{tid}/assignment',json={'assigned_to':'usr_cleaner2'}).status_code==403



def test_invalid_scanned_birth_date_stays_incomplete(client):
    login(client)
    rid,gid,token=stay(client)
    fields={k:v for k,v in IDENTITY.items() if k!='guest_confirmed'}
    fields['date_of_birth']='not-a-date'
    scan=client.post('/api/government/viza/id-scan',json={'reservation_id':rid,'guest_record_id':gid,**fields})
    assert scan.status_code==200 and scan.json()['registration_status']=='incomplete'
    assert client.post(f'/api/reservations/{rid}/guests/{gid}/verify',json={'decision':'verify'}).status_code==409


def test_identical_sensitive_retry_does_not_invalidate_new_review(client):
    login(client)
    rid,gid,token=stay(client)
    assert client.post(f'/api/public/checkin/{token}',json=IDENTITY).status_code==200
    sensitive=f'/api/registration/records/{gid}/sensitive'
    assert client.put(sensitive,json={'address':'Synthetic'}).status_code==200
    assert client.post(f'/api/reservations/{rid}/guests/{gid}/verify',json={'decision':'verify'}).status_code==200
    assert client.put(sensitive,json={'address':'Synthetic'}).json()['duplicate'] is True
    assert client.get(f'/api/reservations/{rid}/guest-checkin-status').json()['registration_status']=='complete'



def test_completed_cleaning_history_does_not_grant_current_property_access(client):
    login(client)
    with app.db() as con:
        con.execute("UPDATE work_tasks SET status='complete' WHERE property_id='prop_flora' AND assigned_to='usr_cleaner'")
    login(client,'cleaner')
    assert 'prop_flora' not in {p['id'] for p in client.get('/api/operations/properties').json()}
    assert not any(m['property_id']=='prop_flora' for m in client.get('/api/maintenance').json())
    assert client.post('/api/maintenance',json={'property_id':'prop_flora','title':'Denied'}).status_code==404
