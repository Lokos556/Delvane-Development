"""Post-device-acceptance contracts, using synthetic guarded data only."""
from datetime import timedelta
import pytest
import app
from test_flutter_reservation_reception import client, login, body


@pytest.mark.parametrize('values,code,field,status',[
    ({'guest_name':''},'guest_name_required','guest_name',400),
    ({'guest_count':0},'invalid_guest_count','guest_count',400),
    ({'guest_count':99},'capacity_exceeded','guest_count',400),
    ({'arrival_date':'not-a-date'},'invalid_dates','arrival_date',400),
    ({'property_id':'prop_other'},'property_unavailable','property_id',404),
    ({'room_type_id':'not-a-room'},'room_unavailable','room_type_id',404),
])
def test_precise_reservation_codes(client,values,code,field,status):
    login(client)
    response=client.post('/api/reservations',json={**body(),**values})
    assert response.status_code==status
    assert response.json()['detail']=={'code':code,'field':field}


def test_overlap_does_not_disclose_another_guest_and_dates_are_distinct(client):
    login(client)
    payload=body()
    assert client.post('/api/reservations',json=payload).status_code==200
    response=client.post('/api/reservations',json=payload)
    assert response.status_code==409 and response.json()['detail']['code']=='availability_conflict'
    assert payload['guest_name'] not in response.text
    payload['departure_date']=payload['arrival_date']
    assert client.post('/api/reservations',json=payload).json()['detail']['code']=='departure_not_after_arrival'
    response=client.post('/api/reservations',json={'guest_name':'PRIVATE INPUT'})
    assert response.status_code==422 and response.json()['detail']['code']=='invalid_fields'
    assert 'PRIVATE INPUT' not in response.text


def test_edit_validation_and_no_active_room_is_safe(client):
    login(client)
    rid=client.post('/api/reservations',json=body()).json()['id']
    for values,code in [({'guest_count':0},'invalid_guest_count'),({'departure_date':body()['arrival_date']},'departure_not_after_arrival'),({'property_id':'other'},'property_unavailable')]:
        response=client.patch(f'/api/reservations/{rid}',json=values)
        assert response.status_code in {400,404} and response.json()['detail']['code']==code
    with app.db() as con: con.execute("UPDATE room_types SET active=0 WHERE property_id='prop_flora'")
    assert client.post('/api/reservations',json=body()).json()['detail']['code']=='room_unavailable'


def new_stay(client,offset,guest_id=None):
    payload=body();arrival=app.date.today()+timedelta(days=300+offset*10)
    payload.update(guest_name='Fictional George',arrival_date=str(arrival),departure_date=str(arrival+timedelta(days=2)))
    if guest_id:payload['guest_id']=guest_id
    response=client.post('/api/reservations',json=payload);assert response.status_code==200,response.text
    rid=response.json()['id']
    return rid,client.get(f'/api/reservations/{rid}/detail').json()['guest_profile']['id']


def test_no_name_merging_and_explicit_history_excludes_host_cancellations(client):
    login(client)
    first,gid=new_stay(client,1)
    other,other_gid=new_stay(client,2)
    assert gid!=other_gid
    assert client.request('DELETE',f'/api/reservations/{first}',json={'initiator':'guest','reason':'Fictional travel change'}).status_code==200
    second,same=new_stay(client,3,gid)
    assert same==gid
    assert client.request('DELETE',f'/api/reservations/{second}',json={'initiator':'host','reason':'Fictional maintenance'}).status_code==200
    third,same=new_stay(client,4,gid)
    history=client.get(f'/api/guests/{gid}').json()
    assert history['history_summary']['guest_cancellations']==1
    assert history['history_summary']['host_cancellations']==1
    assert history['history_summary']['previous_reservations']==2
    assert history['history_summary']['completed_stays'] is None
    assert len(history['stays'])==3 and other not in {x['id'] for x in history['stays']}
    cancelled=next(x for x in history['stays'] if x['id']==first)
    assert cancelled['cancelled_at'] and cancelled['cancellation_reason']=='Fictional travel change'
    assert cancelled['cancellation_source']=='operator'
    assert client.get(f'/api/reservations/{third}/detail').json()['guest_profile']['history_summary']['guest_cancellations']==1


@pytest.mark.parametrize('role',['cleaner','maintenance'])
def test_guest_history_is_operator_only(client,role):
    login(client)
    rid,gid=new_stay(client,1)
    login(client,role)
    assert client.get(f'/api/guests/{gid}').status_code==403
    assert client.get(f'/api/reservations/{rid}/detail').status_code==403


def test_legacy_associations_and_unknown_channel_cancellations_are_not_accusations(client):
    login(client)
    rid,gid=new_stay(client,1)
    with app.db() as con:
        con.execute("UPDATE guest_reservations SET association_source='legacy_unverified' WHERE reservation_id=?",(rid,))
        app._record_sync_downstream(con,'org_casa_rosa',rid,'fictional-channel','cancelled','Fictional George','Synthetic property')
        con.execute("UPDATE reservations SET status='cancelled' WHERE id=?",(rid,))
    result=client.get(f'/api/guests/{gid}').json()
    assert result['stays'][0]['cancellation_initiator']=='unknown'
    assert result['history_summary']['guest_cancellations']==0
    with app.db() as con:
        app.ensure_v3072_schema(con);app.ensure_v3072_schema(con)
        assert con.execute('SELECT COUNT(*) c FROM schema_migrations WHERE version=3072').fetchone()['c']==1


@pytest.mark.parametrize('birth,valid',[('1919-12-31',False),('1920-01-01',True),('2000-02-30',False),('2999-01-01',False)])
def test_guest_birth_date_range(client,birth,valid):
    login(client)
    rid,gid=new_stay(client,1)
    link=client.get(f'/api/reservations/{rid}/guest-checkin-links').json()['links'][0]['url'].rsplit('/',1)[-1]
    result=client.post(f'/api/public/checkin/{link}',json={'full_name':'Fictional George','date_of_birth':birth,'nationality':'Hungarian','document_type':'passport','document_number':'SYNTHETIC','guest_confirmed':True,'sex':''})
    assert result.status_code==(200 if valid else 400)
    if not valid:assert result.json()['detail']['code']=='invalid_birth_date'


def test_retry_cancellation_cannot_erase_explicit_guest_initiator(client):
    login(client)
    rid,gid=new_stay(client,1)
    assert client.request('DELETE',f'/api/reservations/{rid}',json={'initiator':'guest','reason':'Fictional change'}).status_code==200
    assert client.delete(f'/api/reservations/{rid}').status_code==200
    reservation=client.get(f'/api/reservations/{rid}/detail').json()['reservation']
    assert reservation['cancellation_initiator']=='guest'
    assert reservation['cancellation_reason']=='Fictional change'


def test_old_schema_upgrade_retains_data_and_does_not_trust_name_matches(client):
    login(client)
    rid,gid=new_stay(client,1)
    with app.db() as con:
        con.execute('ALTER TABLE guest_reservations DROP COLUMN association_source')
        for column in ['cancelled_at','cancellation_initiator','cancellation_reason','cancellation_source']:
            con.execute('ALTER TABLE reservations DROP COLUMN '+column)
        con.execute('DELETE FROM schema_migrations WHERE version=3072')
        app.ensure_v3072_schema(con)
        assert con.execute('SELECT guest_name FROM reservations WHERE id=?',(rid,)).fetchone()['guest_name']=='Fictional George'
        assert con.execute('SELECT association_source FROM guest_reservations WHERE reservation_id=?',(rid,)).fetchone()['association_source']=='legacy_unverified'
        assert con.execute('SELECT COUNT(*) c FROM schema_migrations WHERE version=3072').fetchone()['c']==1


def test_relinking_primary_profile_preserves_secondary_guest_associations(client):
    login(client)
    rid,gid=new_stay(client,1)
    other,other_gid=new_stay(client,2)
    with app.db() as con:
        con.execute("INSERT INTO guest_reservations(guest_id,reservation_id,is_primary,association_source) VALUES (?,?,0,'legacy_unverified')",(other_gid,rid))
        app._associate_guest(con,'org_casa_rosa',rid,gid)
        assert con.execute('SELECT is_primary FROM guest_reservations WHERE guest_id=? AND reservation_id=?',(other_gid,rid)).fetchone()['is_primary']==0


def test_identity_review_restrictions_have_actionable_reservation_codes(client):
    login(client)
    response=client.post('/api/reservations',json={**body(),'registration_status':'complete'})
    assert response.status_code==409 and response.json()['detail']['code']=='registration_review_required'
    rid,gid=new_stay(client,1)
    with app.db() as con:
        con.execute("UPDATE guest_records SET completeness='complete' WHERE reservation_id=?",(rid,))
    response=client.patch(f'/api/reservations/{rid}',json={'guest_count':1})
    assert response.status_code==409 and response.json()['detail']['code']=='guest_records_review_required'
