from datetime import timedelta,timezone
import json,sqlite3,uuid
import pytest
import app,viza_identity as vi,viza_reporting as vr
from test_flutter_reservation_reception import client,login
from test_actual_stays import prepared,act

FIELDS={'csaladnev':'Fictional','utonev':'\u00c1rv\u00edzt\u0171r\u0151','szuletesiDatum':'1990-01-02','nem':'NO','allampolgarsagKod':'HU','okmanyTipus':'UTLEVEL','okmanyAzonositoSzam':'FICTIONAL-ONLY'}

def path(gid):return f'/api/registration/records/{gid}/viza-identity'
def edit(client,gid,fields=None,**extra):return client.put(path(gid),json={'manual':fields or {},'reason':'Fictional review only','third_country_applicable':False,**extra})
def jobs(rid):
    with app.db() as con:return [dict(r) for r in con.execute('SELECT j.* FROM viza_jobs j JOIN stay_events e ON e.id=j.event_id WHERE e.reservation_id=? ORDER BY e.sequence,j.batch_number,j.revision',(rid,))]

def test_original_pair_correction_encryption_restart_and_security(client):
    rid,_,units,gids,at=prepared(client);gid=gids[0]
    with app.db() as con:
        row=vi.scope(con,'org_casa_rosa',gid)
        vi.append(app,con,row,FIELDS,'fixture-reader','scan')
    assert edit(client,gid,{'csaladnev':'Fictional corrected'}).status_code==200
    p=client.get(path(gid)).json()
    assert p['original']['csaladnev']=='Fictional'
    assert p['manual']['utonev']==FIELDS['utonev'] and p['manual']['csaladnev']=='Fictional corrected'
    assert p['provenance']['utonev']['actor_id']=='usr_owner'
    with app.db() as con:
        vi.append(app,con,vi.scope(con,'org_casa_rosa',gid),{'csaladnev':'Conflicting later read'},'later-reader','scan')
    reviewed=client.get(path(gid)).json()
    assert reviewed['provenance']['csaladnev']['actor_id']=='usr_owner'
    assert reviewed['effective']['csaladnev']=='Fictional corrected'
    app.init_db();assert client.get(path(gid)).json()['original']==FIELDS
    with app.db() as con:
        raw=con.execute('SELECT encrypted_payload FROM guest_identity_sources WHERE guest_record_id=?',(gid,)).fetchone()[0]
        assert 'FICTIONAL-ONLY' not in raw and FIELDS['utonev'] not in raw
        with pytest.raises(sqlite3.IntegrityError):con.execute("UPDATE guest_identity_sources SET kind='manual' WHERE guest_record_id=?",(gid,))
        vi.migrate(con,app.now_iso());vi.migrate(con,app.now_iso());vr.migrate(con,app.now_iso());vr.migrate(con,app.now_iso())
    assert client.put(path(gid),json={'manual':{},'reason':'Fictional','actor_id':'spoof'}).status_code==422
    assert client.get(path('guest-other-tenant')).status_code==404
    login(client,'cleaner');assert client.get(path(gid)).status_code==403
    login(client);client.headers.pop('X-Rosa-CSRF');assert edit(client,gid,FIELDS).status_code==403


def test_country_third_country_optional_fields_and_readiness(client):
    rid,_,_,gids,at=prepared(client);gid=gids[0]
    assert edit(client,gid,{**FIELDS,'allampolgarsagKod':'NLD'}).status_code==422
    assert edit(client,gid,FIELDS,third_country_applicable=True).status_code==200
    p=client.get(path(gid)).json();assert 'missing:beutazasDatuma' in p['readiness']['blockers']
    assert 'missing:szuletesiHely' not in p['readiness']['blockers']
    assert edit(client,gid,{'vizumEngedelySzam':'FICTIONAL-VISA','beutazasDatuma':str(app.date.today()),'beutazasHelye':'Fictional border'},third_country_applicable=True).status_code==200
    assert client.post(f'/api/reservations/{rid}/guests/{gid}/verify',json={'decision':'verify','verification_method':'in_person'}).status_code==200
    p=client.get(path(gid)).json();assert p['readiness']['ready'],p
    assert p['original_state']=='unknown_not_reconstructed'
    assert edit(client,gid,{'csaladnev':'\u0151'*128}).status_code==422
    with app.db() as con:
        assert con.execute('SELECT document_number,date_of_birth FROM guest_records WHERE id=?',(gid,)).fetchone()['document_number'] is None
        for row in con.execute('SELECT payload_json FROM government_outbox WHERE reservation_id=?',(rid,)):assert 'FICTIONAL-ONLY' not in row['payload_json']


def test_visit_uuid_lifecycle_transfer_retirement_restart_and_recovery(client):
    rid,_,units,gids,at=prepared(client);gid=gids[0]
    first,body=act(client,rid,[gid],at,uid=units[1][0]);assert first.status_code==200,first.text
    assert client.post(f'/api/reservations/{rid}/actual-stay',json=body).json()['duplicate']
    with app.db() as con:original=vr.visit(con,gid)['arrival_uuid']
    assert str(uuid.UUID(original))==original and original!=first.json()['id']
    before=jobs(rid)[0];assert 'owner_verification_required' in json.loads(before['blockers_json'])
    assert edit(client,gid,FIELDS).status_code==200
    assert client.post(f'/api/reservations/{rid}/guests/{gid}/verify',json={}).status_code==200
    assert client.post(f'/api/reservations/{rid}/actual-stay/reporting-recovery/'+first.json()['id']).status_code==200
    assert len(jobs(rid))==2 and jobs(rid)[0]['state']=='superseded_before_submission'
    assert act(client,rid,[gid],at+timedelta(hours=1),kind='transfer',uid=units[2][0])[0].status_code==200
    app.init_db()
    with app.db() as con:assert vr.visit(con,gid,active=True)['arrival_uuid']==original
    assert act(client,rid,[gid],at+timedelta(hours=2),kind='depart')[0].status_code==200
    last=jobs(rid)[-1]
    with app.db() as con:assert app.decrypt_json(last['encrypted_facts'])['guests'][0]['arrival_uuid']==original
    # Separate guest: erroneous arrival closes and retires UUID, next actual visit gets another.
    gid=gids[1];arr,_=act(client,rid,[gid],at,uid=units[0][0]);assert arr.status_code==200
    with app.db() as con:old=vr.visit(con,gid)['arrival_uuid']
    assert act(client,rid,[gid],at+timedelta(minutes=1),kind='undo_arrival',correction_of=arr.json()['id'])[0].status_code==200
    assert act(client,rid,[gid],at+timedelta(minutes=2),uid=units[0][0])[0].status_code==200
    with app.db() as con:
        assert con.execute('SELECT retired FROM viza_visits WHERE arrival_uuid=?',(old,)).fetchone()['retired']==1
        assert vr.visit(con,gid,active=True)['arrival_uuid']!=old
    assert all('official_transmission_disabled' in json.loads(j['blockers_json']) for j in jobs(rid))


def test_capture_rollback_and_unknown_submitted_correction(client,monkeypatch):
    rid,_,units,gids,at=prepared(client)
    original=vr.queue
    def broken(*a,**kw):
        original(*a,**kw);raise RuntimeError('Synthetic capture rollback')
    monkeypatch.setattr(vr,'queue',broken)
    with pytest.raises(RuntimeError):act(client,rid,gids,at,uid=units[0][0])
    assert not jobs(rid)
    with app.db() as con:assert con.execute('SELECT COUNT(*) n FROM viza_visits WHERE reservation_id=?',(rid,)).fetchone()['n']==0
    monkeypatch.setattr(vr,'queue',original)
    response,_=act(client,rid,gids,at,uid=units[0][0]);assert response.status_code==200
    with app.db() as con:con.execute("UPDATE viza_jobs SET state='uncertain',attempts=1 WHERE event_id=?",(response.json()['id'],))
    corrected,_=act(client,rid,gids,at+timedelta(minutes=10),kind='correct_timestamp',correction_of=response.json()['id'],corrected_at=(at+timedelta(minutes=1)).isoformat());assert corrected.status_code==200,corrected.text
    assert 'Q5_submitted_correction_unresolved' in json.loads(jobs(rid)[-1]['blockers_json'])


def test_more_than_ten_guests_split_and_registration_never_arrives(client):
    rid,_,units,gids,at=prepared(client)
    with app.db() as con:
        # Fictional operational fixture: large unit, one reservation, 12 individual guests.
        con.execute('UPDATE physical_unit_versions SET single_beds=20 WHERE unit_id=?',(units[0][0],))
        for n in range(10):
            con.execute('INSERT INTO guest_records(id,organization_id,reservation_id,full_name,completeness) VALUES (?,?,?,?,?)',(f'viza-group-{n}','org_casa_rosa',rid,'Fictional Guest','incomplete'))
        gids=[r['id'] for r in con.execute('SELECT id FROM guest_records WHERE reservation_id=?',(rid,))]
    assert not jobs(rid)
    response,_=act(client,rid,gids,at,uid=units[0][0]);assert response.status_code==200,response.text
    captured=jobs(rid);assert len(captured)==2
    with app.db() as con:
        sizes=[len(app.decrypt_json(j['encrypted_facts'])['guests']) for j in captured]
        assert sizes==[10,2]
        uuids=[r['arrival_uuid'] for r in con.execute('SELECT arrival_uuid FROM viza_visits WHERE reservation_id=?',(rid,))]
        assert len(set(uuids))==12

def test_capture_unsigned_body_and_concurrent_duplicate_requests(client):
    from concurrent.futures import ThreadPoolExecutor
    import guest_stays
    from test_viza_contracts import HEADER
    rid,_,units,gids,at=prepared(client);gid=gids[0]
    assert edit(client,gid,FIELDS).status_code==200
    assert client.post(f'/api/reservations/{rid}/guests/{gid}/verify',json={}).status_code==200
    action=guest_stays.StayAction(request_id=uuid.uuid4(),kind='arrive',guest_ids=[gid],occurred_at=at,unit_id=units[0][0],reason='Fictional concurrent duplicate')
    def submit(_):
        with app.db() as con:return guest_stays.apply(app,con,'org_casa_rosa',rid,action,'usr_owner')
    with ThreadPoolExecutor(max_workers=2) as pool:responses=list(pool.map(submit,[0,1]))
    assert sorted(r['duplicate'] for r in responses)==[False,True]
    captured=jobs(rid);assert len(captured)==1
    with app.db() as con:
        raw=vr.unsigned_request(app,con,captured[0]['id'],{**HEADER,'bejelentesIdopontja':app.datetime.now(timezone.utc)})
        assert b'FICTIONAL-ONLY' in raw and b'xsi:nil="true"' in raw
        assert con.execute('SELECT COUNT(*) n FROM viza_visits WHERE guest_record_id=?',(gid,)).fetchone()['n']==1
    assert 'identity_normalization_unresolved' not in json.loads(captured[0]['blockers_json'])


def test_minor_registration_and_legacy_privacy_migration(client):
    rid,data,_,gids,at=prepared(client);gid=gids[0]
    born=app.date.fromisoformat(data['arrival_date']).replace(year=app.date.fromisoformat(data['arrival_date']).year-13)
    child={**FIELDS,'szuletesiDatum':str(born),'okmanyTipus':None,'okmanyAzonositoSzam':None}
    assert edit(client,gid,child).status_code==200
    assert client.post(f'/api/reservations/{rid}/guests/{gid}/verify',json={}).status_code==200
    assert client.get(path(gid)).json()['readiness']['ready']
    with app.db() as con:
        con.execute("UPDATE guest_records SET date_of_birth='1991-02-03',document_number='LEGACY-FICTIONAL' WHERE id=?",(gids[1],))
        vi.vault_merge(app,con,gids[1],'org_casa_rosa',{'document_number':'NEWER-FICTIONAL','address':'Fictional preserved address'})
        vi.protect_legacy(app,con);vi.protect_legacy(app,con)
        archived=con.execute('SELECT encrypted_payload FROM legacy_guest_identity_archives WHERE guest_record_id=?',(gids[1],)).fetchall()
        assert len(archived)==1
        data=app.decrypt_json(archived[0]['encrypted_payload'])
        assert data['previous_vault']['document_number']=='NEWER-FICTIONAL'
        assert data['legacy_mutable_record']['document_number']=='LEGACY-FICTIONAL'
        protected=vi.compatibility(app,con,vi.scope(con,'org_casa_rosa',gids[1]))
        assert protected['document_number']=='LEGACY-FICTIONAL'
        assert con.execute('SELECT document_number FROM guest_records WHERE id=?',(gids[1],)).fetchone()['document_number'] is None
        assert vi.project(app,con,gids[1])['original_state']=='unknown_not_reconstructed'


def test_same_day_pms_remains_valid_with_explicit_viza_hold(client):
    from test_reservation_allocations import setup
    from test_day_use import make
    _,units=setup(client);made,data=make(client,units[2:],offset=-1);assert made.status_code==200
    rid=made.json()['id']
    with app.db() as con:gid=con.execute('SELECT id FROM guest_records WHERE reservation_id=?',(rid,)).fetchone()['id']
    at=app.datetime.fromisoformat(data['arrival_date']+'T10:30:00').replace(tzinfo=timezone(timedelta(hours=1)))
    response,_=act(client,rid,[gid],at,uid=units[2][0]);assert response.status_code==200,response.text
    assert 'Q6_same_day_expected_departure_unresolved' in json.loads(jobs(rid)[0]['blockers_json'])
    assert client.get(f'/api/reservations/{rid}/actual-stay').json()['actual_occupants']==1

@pytest.mark.parametrize('state,attempts,hold',[
    ('blocked',0,'never_sent_arrival_voided_no_submission'),
    ('accepted',1,None),('uncertain',1,'Q7_uncertain_arrival_closure')])
def test_erroneous_arrival_outcome_policy(client,state,attempts,hold):
    rid,_,units,gids,at=prepared(client);gid=gids[0]
    first,_=act(client,rid,[gid],at,uid=units[0][0]);assert first.status_code==200
    with app.db() as con:con.execute('UPDATE viza_jobs SET state=?,attempts=? WHERE event_id=?',(state,attempts,first.json()['id']))
    undo,_=act(client,rid,[gid],at+timedelta(minutes=1),kind='undo_arrival',correction_of=first.json()['id']);assert undo.status_code==200
    captured=jobs(rid);last=captured[-1]
    assert last['kind']=='departure'
    if hold:assert hold in json.loads(last['blockers_json'])
    else:assert not any(b.startswith(('Q5','Q7','never_sent')) for b in json.loads(last['blockers_json']))
    with app.db() as con:
        event=dict(con.execute('SELECT * FROM stay_events WHERE id=?',(undo.json()['id'],)).fetchone())
        vr.capture(app,con,event);assert vr.visit(con,gid)['retired']==1
    assert len(jobs(rid))==2


def test_untrusted_review_flags_and_recovery_do_not_reopen_departed_visit(client):
    rid,_,units,gids,at=prepared(client);gid=gids[0]
    response=client.post('/api/government/viza/id-scan',json={'reservation_id':rid,'guest_record_id':gid,'scanned_fields':FIELDS,'scan_ambiguities':['SECRET-DO-NOT-LOG']})
    assert response.status_code==422
    first,_=act(client,rid,[gid],at,uid=units[0][0]);assert first.status_code==200
    departure,_=act(client,rid,[gid],at+timedelta(minutes=1),kind='depart');assert departure.status_code==200
    undo,_=act(client,rid,[gid],at+timedelta(minutes=2),kind='undo_departure',correction_of=departure.json()['id']);assert undo.status_code==200
    assert act(client,rid,[gid],at+timedelta(minutes=3),kind='depart')[0].status_code==200
    with app.db() as con:
        event=dict(con.execute('SELECT * FROM stay_events WHERE id=?',(undo.json()['id'],)).fetchone())
        vr.capture(app,con,event)
        assert vr.visit(con,gid,active=True) is None

def test_migration_excludes_legacy_events_without_inventing_visit_uuid(client):
    rid,_,units,gids,at=prepared(client);gid=gids[0]
    arrival,_=act(client,rid,[gid],at,uid=units[0][0]);assert arrival.status_code==200
    with app.db() as con:
        for job in jobs(rid):
            con.execute('DELETE FROM viza_job_guests WHERE job_id=?',(job['id'],))
            con.execute('DELETE FROM viza_jobs WHERE id=?',(job['id'],))
            con.execute('DELETE FROM government_outbox WHERE id=?',(job['id'],))
        con.execute('DELETE FROM viza_visits WHERE guest_record_id=?',(gid,))
        con.execute('DELETE FROM viza_captured_events')
        con.execute('DELETE FROM schema_migrations WHERE version=3086')
        vr.migrate(con,app.now_iso())
        event=dict(con.execute('SELECT * FROM stay_events WHERE id=?',(arrival.json()['id'],)).fetchone())
        vr.capture(app,con,event)
        assert vr.visit(con,gid) is None
        assert con.execute('SELECT origin FROM viza_captured_events WHERE event_id=?',(event['id'],)).fetchone()['origin']=='legacy_excluded_no_inferred_uuid'
    departure,_=act(client,rid,[gid],at+timedelta(minutes=1),kind='depart');assert departure.status_code==200,departure.text
    assert 'legacy_arrival_uuid_unknown' in json.loads(jobs(rid)[0]['blockers_json'])
