from datetime import timedelta,timezone
import uuid
import pytest
import app
import guest_stays
import guest_reporting
from test_flutter_reservation_reception import client,login
from test_reservation_allocations import setup,booking,assign
from test_ntak_reporting import CONFIG,BASE
from test_guest_reporting_profile import PROFILE


def prepared(client,frozen=False):
    rt,units=setup(client);rid,data=booking(client,-2)
    assert assign(client,rid,data,[units[0][0],units[1][0]]).status_code==200
    client.put(BASE,json=CONFIG)
    with app.db() as con:
        gids=[r['id'] for r in con.execute('SELECT id FROM guest_records WHERE reservation_id=? ORDER BY id',(rid,))]
        con.execute("UPDATE guest_records SET nationality='HU' WHERE reservation_id=?",(rid,))
    for gid in gids:
        assert client.put(f'/api/registration/records/{gid}/reporting-profile',json={**PROFILE,'effective_from':data['arrival_date']}).status_code==200
        if frozen:
            with app.db() as con:guest_reporting.identity_for_submission(app,con,'org_casa_rosa','prop_flora',gid,canonical_identity='Fictional '+gid+' Budapest 1986.01.01.')
    at=app.datetime.now(timezone.utc)-timedelta(days=2)
    return rid,data,units,gids,at


def act(client,rid,gids,at,kind='arrive',uid=None,**extra):
    body={'request_id':str(uuid.uuid4()),'kind':kind,'guest_ids':gids,'occurred_at':at.isoformat(),'reason':'Fictional owner-observed event',**extra}
    if uid:body['unit_id']=uid
    return client.post(f'/api/reservations/{rid}/actual-stay',json=body),body


def test_individual_lifecycle_no_inferred_arrival_blocker_and_recovery(client):
    rid,p,units,gids,at=prepared(client)
    url=f'/api/reservations/{rid}/actual-stay'
    assert client.get(url).json()['actual_occupants']==0
    response,body=act(client,rid,[gids[0]],at,uid=units[0][0]);assert response.status_code==200,response.text
    assert client.post(url,json=body).json()['duplicate']
    events=client.get(url).json()['events'];assert events[0]['error_code']=='identity_normalization_unresolved'
    assert act(client,rid,[gids[0]],at,uid=units[0][0])[0].status_code==409
    assert act(client,rid,[gids[1]],at+timedelta(days=1),uid=units[1][0])[0].status_code==200
    assert act(client,rid,[gids[0]],at+timedelta(days=1),kind='depart')[0].status_code==200
    assert client.get(url).json()['actual_occupants']==1
    assert act(client,rid,[gids[0]],at+timedelta(days=1),kind='depart')[0].status_code==409
    with app.db() as con:
        guest_reporting.identity_for_submission(app,con,'org_casa_rosa','prop_flora',gids[0],canonical_identity='Fictional identity Budapest 1986.01.01.')
    assert client.post(url+'/reporting-recovery/'+events[0]['id']).status_code==200
    assert client.get(url).json()['events'][0]['reporting_state']=='ready'
    app.init_db();assert client.get(url).json()['actual_occupants']==1


def test_group_arrival_departure_schema_ready_and_rollback(client):
    rid,p,units,gids,at=prepared(client,True)
    response,_=act(client,rid,gids,at,uid=units[0][0]);assert response.status_code==200,response.text
    result=client.get(f'/api/reservations/{rid}/actual-stay').json()
    assert result['actual_occupants']==2 and result['events'][0]['reporting_state']=='ready'
    assert act(client,rid,[gids[0],'missing'],at,kind='depart')[0].status_code==404
    assert client.get(f'/api/reservations/{rid}/actual-stay').json()['actual_occupants']==2
    response,_=act(client,rid,gids,at+timedelta(hours=3),kind='depart');assert response.status_code==200
    with app.db() as con:
        guest_stays.migrate(con,app.now_iso());guest_stays.migrate(con,app.now_iso())
        assert con.execute('SELECT COUNT(*) c FROM stay_events WHERE reservation_id=?',(rid,)).fetchone()['c']==2


def test_lifecycle_authorization_and_time_validation(client):
    rid,p,units,gids,at=prepared(client)
    assert act(client,rid,gids,at.replace(tzinfo=None),uid=units[0][0])[0].status_code==422
    assert act(client,rid,gids,at+timedelta(days=10),uid=units[0][0])[0].status_code==422
    login(client,'cleaner');assert client.get(f'/api/reservations/{rid}/actual-stay').status_code==403
    login(client);assert client.get('/api/reservations/res_other_secret/actual-stay').status_code==404
    client.headers.pop('X-Rosa-CSRF');assert act(client,rid,gids,at,uid=units[0][0])[0].status_code==403


def test_erroneous_arrival_departure_corrections_and_actual_transfer(client):
    rid,p,units,gids,at=prepared(client,True)
    arrival,_=act(client,rid,[gids[0]],at,uid=units[1][0]);assert arrival.status_code==200
    undo,_=act(client,rid,[gids[0]],at+timedelta(minutes=1),kind='undo_arrival',correction_of=arrival.json()['id']);assert undo.status_code==200,undo.text
    url=f'/api/reservations/{rid}/actual-stay'
    assert client.get(url).json()['actual_occupants']==0
    arrival,_=act(client,rid,[gids[0]],at+timedelta(minutes=2),uid=units[1][0]);assert arrival.status_code==200
    moved,_=act(client,rid,[gids[0]],at+timedelta(days=1),kind='transfer',uid=units[2][0]);assert moved.status_code==200,moved.text
    result=client.get(url).json();assert result['guests'][0]['occupancy']['unit_id']==units[2][0]
    departure,_=act(client,rid,[gids[0]],at+timedelta(days=1,hours=1),kind='depart');assert departure.status_code==200
    undo,_=act(client,rid,[gids[0]],at+timedelta(days=1,hours=2),kind='undo_departure',correction_of=departure.json()['id']);assert undo.status_code==200,undo.text
    assert client.get(url).json()['actual_occupants']==1
    with app.db() as con:
        assert con.execute('SELECT COUNT(*) c FROM guest_occupancy WHERE guest_id=?',(gids[0],)).fetchone()['c']==3
        assert con.execute('SELECT COUNT(*) c FROM stay_events WHERE reservation_id=?',(rid,)).fetchone()['c']==6


def test_latest_timestamp_correction_preserves_counter_and_replacement(client):
    rid,p,units,gids,at=prepared(client,True)
    initial,_=act(client,rid,[gids[0]],at,uid=units[0][0])
    # Offline fixture: original response was fully processed; no network call.
    with app.db() as con:con.execute("UPDATE ntak_jobs SET state='succeeded' WHERE id=(SELECT reporting_job_id FROM stay_events WHERE id=?)",(initial.json()['id'],))
    correction,_=act(client,rid,[gids[0]],at+timedelta(hours=1),kind='correct_timestamp',correction_of=initial.json()['id'],corrected_at=(at+timedelta(minutes=10)).isoformat())
    assert correction.status_code==200,correction.text
    out=client.get(f'/api/reservations/{rid}/actual-stay').json()
    assert [e['kind'] for e in out['events']]==['arrive','timestamp_counter','timestamp_replacement']
    assert out['guests'][0]['occupancy']['started_at']==(at+timedelta(minutes=10)).isoformat()
    with app.db() as con:
        job=con.execute('SELECT j.predecessor_job_id FROM stay_events e JOIN ntak_jobs j ON j.id=e.reporting_job_id WHERE e.kind=?',('timestamp_replacement',)).fetchone()
        assert job['predecessor_job_id']


def test_concurrent_arrivals_cannot_exceed_actual_unit_capacity(client):
    from concurrent.futures import ThreadPoolExecutor
    rid,p,units,gids,at=prepared(client)
    assert client.patch('/api/reservations/'+rid,json={'guest_count':3}).status_code==200
    with app.db() as con:gids=[g['id'] for g in con.execute('SELECT id FROM guest_records WHERE reservation_id=? ORDER BY id',(rid,))]
    def arrive(group):
        command=guest_stays.StayAction(request_id=uuid.uuid4(),kind='arrive',guest_ids=group,occurred_at=at,unit_id=units[1][0],reason='Fictional concurrent observation')
        try:
            with app.db() as con:guest_stays.apply(app,con,'org_casa_rosa',rid,command,'usr_owner')
            return 200
        except app.HTTPException as exc:return exc.status_code
    with ThreadPoolExecutor(max_workers=2) as pool:codes=list(pool.map(arrive,[gids[:2],gids[2:]]))
    assert sorted(codes)==[200,409]
    assert client.get(f'/api/reservations/{rid}/actual-stay').json()['actual_occupants']<=2


def test_reporting_failure_rolls_back_actual_transition(client,monkeypatch):
    rid,p,units,gids,at=prepared(client)
    monkeypatch.setattr(guest_stays,'capture',lambda *a:(_ for _ in ()).throw(RuntimeError('Fictional database failure')))
    with pytest.raises(RuntimeError):act(client,rid,gids,at,uid=units[0][0])
    with app.db() as con:
        assert con.execute('SELECT COUNT(*) n FROM stay_events WHERE reservation_id=?',(rid,)).fetchone()['n']==0
        assert con.execute('SELECT COUNT(*) n FROM guest_occupancy WHERE reservation_id=?',(rid,)).fetchone()['n']==0


def test_official_group_partial_party_and_102_to_103_sequence(client):
    # ES_01A/B/C, ES_02/03/04A/04B/05: fictional ordinary PMS records.
    from test_flutter_reservation_reception import body
    from test_guest_reporting_profile import PROFILE
    rt,units=setup(client);client.put(BASE,json=CONFIG)
    at=app.datetime.now(timezone.utc)-timedelta(days=4)
    def party(count,uid,label):
        data=body();data.update(guest_name=label,guest_count=count,arrival_date=str(at.date()),departure_date=str((at+timedelta(days=4)).date()))
        made=client.post('/api/reservations',json=data);assert made.status_code==200,made.text
        rid=made.json()['id'];assert assign(client,rid,data,[uid]).status_code==200
        with app.db() as con:
            gids=[g['id'] for g in con.execute('SELECT id FROM guest_records WHERE reservation_id=? ORDER BY id',(rid,))]
            con.execute("UPDATE guest_records SET nationality='HU' WHERE reservation_id=?",(rid,))
        for gid in gids:
            client.put(f'/api/registration/records/{gid}/reporting-profile',json={**PROFILE,'effective_from':data['arrival_date']})
            with app.db() as con:guest_reporting.identity_for_submission(app,con,'org_casa_rosa','prop_flora',gid,canonical_identity=label+' '+gid+' Budapest 1986.01.01.')
        return rid,gids
    first,g1=party(3,units[0][0],'Fictional leisure party')
    second,g2=party(2,units[1][0],'Fictional independent party')
    incoming,_=act(client,first,g1,at,uid=units[0][0]);assert incoming.status_code==200
    # Offline processed-response fixture, not an external NTAK result.
    with app.db() as con:con.execute("UPDATE ntak_jobs SET state='succeeded' WHERE id=(SELECT reporting_job_id FROM stay_events WHERE id=?)",(incoming.json()['id'],))
    assert act(client,first,[g1[2]],at+timedelta(minutes=1),kind='undo_arrival',correction_of=incoming.json()['id'])[0].status_code==200
    assert act(client,second,[g2[0]],at,uid=units[1][0])[0].status_code==200
    assert act(client,second,[g2[0]],at+timedelta(days=1),kind='transfer',uid=units[2][0])[0].status_code==200
    assert act(client,second,[g2[1]],at+timedelta(days=2),uid=units[2][0])[0].status_code==200
    assert act(client,first,g1[:2],at+timedelta(days=2),kind='depart')[0].status_code==200
    departure,_=act(client,second,[g2[0]],at+timedelta(days=2,hours=1),kind='depart');assert departure.status_code==200
    assert client.get(f'/api/reservations/{second}/actual-stay').json()['actual_occupants']==1
    assert act(client,second,[g2[0]],at+timedelta(days=2,hours=2),kind='undo_departure',correction_of=departure.json()['id'])[0].status_code==200
    assert client.get(f'/api/reservations/{second}/actual-stay').json()['actual_occupants']==2


def test_unsent_group_correction_keeps_valid_guests_and_suppresses_false_arrival(client):
    import json
    rid,p,units,gids,at=prepared(client,True)
    original,_=act(client,rid,gids,at,uid=units[0][0])
    corrected,_=act(client,rid,[gids[0]],at+timedelta(minutes=1),kind='undo_arrival',correction_of=original.json()['id'])
    assert corrected.status_code==200,corrected.text
    with app.db() as con:
        event=con.execute('SELECT * FROM stay_events WHERE id=?',(original.json()['id'],)).fetchone()
        payload=json.loads(con.execute('SELECT payload_json FROM ntak_jobs WHERE id=?',(event['reporting_job_id'],)).fetchone()['payload_json'])
        assert len(payload['esemenyek']['erkezett'][0]['vendegek'])==1
        assert con.execute('SELECT reporting_job_id FROM stay_events WHERE id=?',(corrected.json()['id'],)).fetchone()['reporting_job_id'] is None
        assert con.execute('SELECT COUNT(*) n FROM ntak_jobs WHERE state=?',('replaced_by_recovery',)).fetchone()['n']==1


def test_reporting_waits_for_uncertain_predecessor_but_accepts_processed_warnings(client):
    import ntak_reporting
    from test_ntak_reporting import SoapMock
    rid,p,units,gids,at=prepared(client,True)
    original,_=act(client,rid,gids,at,uid=units[0][0])
    departure,_=act(client,rid,gids,at+timedelta(hours=1),kind='depart')
    with app.db() as con:
        first=con.execute('SELECT reporting_job_id FROM stay_events WHERE id=?',(original.json()['id'],)).fetchone()['reporting_job_id']
        second=con.execute('SELECT reporting_job_id FROM stay_events WHERE id=?',(departure.json()['id'],)).fetchone()['reporting_job_id']
        # Prove the event chronology guard even before dependency edges exist.
        con.execute('DELETE FROM ntak_job_predecessors WHERE job_id=?',(second,))
        con.execute('UPDATE ntak_jobs SET predecessor_job_id=NULL WHERE id=?',(second,))
        con.execute("UPDATE ntak_jobs SET state='uncertain' WHERE id=?",(first,))
    mock=SoapMock()
    ntak_reporting.worker_once(app.db,transport=mock)
    assert not mock.calls
    with app.db() as con:con.execute("UPDATE ntak_jobs SET state='review_required',error_code=NULL WHERE id=?",(first,))
    ntak_reporting.worker_once(app.db,transport=mock)
    assert [call[0] for call in mock.calls]==['stay']
