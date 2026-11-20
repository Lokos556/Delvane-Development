"""V08 synthetic engineering rehearsal. NOT official exercises or device/OCR evidence."""
from datetime import timedelta,timezone
from pathlib import Path
import json,sqlite3,uuid
import pytest
from cryptography import x509
from cryptography.x509.oid import NameOID
from cryptography.hazmat.primitives import hashes,serialization
from cryptography.hazmat.primitives.asymmetric import rsa
import app,viza_contracts as contract,viza_delivery as delivery,viza_reporting as reporting,viza_identity as identity
from viza_security import OfflineMockTransport,Binding,verify_property
from test_flutter_reservation_reception import client,login,body
from test_reservation_allocations import setup,assign
from test_actual_stays import act
from test_viza_delivery import CONFIG,BASE,receipt,status_raw


def synthetic_key(root,now):
    folder=root/'v08_synthetic';folder.mkdir()
    key=rsa.generate_private_key(public_exponent=65537,key_size=4096)
    name=x509.Name([x509.NameAttribute(NameOID.COMMON_NAME,CONFIG['reporting_id'])])
    cert=x509.CertificateBuilder().subject_name(name).issuer_name(name).public_key(key.public_key()).serial_number(x509.random_serial_number()).not_valid_before(now-timedelta(days=2)).not_valid_after(now+timedelta(days=60)).sign(key,hashes.SHA256())
    (folder/'private-key.pem').write_bytes(key.private_bytes(serialization.Encoding.PEM,serialization.PrivateFormat.PKCS8,serialization.NoEncryption()))
    (folder/'certificate.pem').write_bytes(cert.public_bytes(serialization.Encoding.PEM))
    fingerprint=cert.fingerprint(hashes.SHA256()).hex()
    (folder/'binding.json').write_text(json.dumps({'system':'VIZA','organization_id':'org_casa_rosa','property_id':'prop_flora','environment':'test','reporting_id':CONFIG['reporting_id'],'endpoint':CONFIG['endpoint'],'certificate_sha256':fingerprint}),encoding='utf8')
    return fingerprint


def job_count(rid):
    with app.db() as con:return con.execute('SELECT COUNT(*) n FROM viza_jobs j JOIN stay_events e ON e.id=j.event_id WHERE e.reservation_id=?',(rid,)).fetchone()['n']


def test_full_public_registration_to_signed_mock_arrival_transfer_departure(client,tmp_path):
    _,units=setup(client)
    now=app.datetime.now(timezone.utc);at=now-timedelta(days=2)
    details={**body(),'guest_count':3,'guest_name':'V08 fictional party','arrival_date':str(at.date()),'departure_date':str(now.date()+timedelta(days=2))}
    created=client.post('/api/reservations',json=details);assert created.status_code==200,created.text
    rid=created.json()['id']
    assert assign(client,rid,details,[units[0][0],units[1][0]]).status_code==200
    assert client.patch('/api/reservations/'+rid,json={'arrival_time':'16:30','departure_date':str(now.date()+timedelta(days=3))}).status_code==200
    assert client.put(BASE+'/settings',json=CONFIG).status_code==200
    links=client.get(f'/api/reservations/{rid}/guest-checkin-links').json()['links'];assert len(links)==3
    # Exercise real public token routes without an owner session, not direct guest inserts.
    client.cookies.clear();client.headers.pop('X-Rosa-CSRF',None)
    originals={}
    for n,link in enumerate(links):
        dob='1990-01-02' if n!=1 else str(at.date().replace(year=at.year-13))
        scanned={'csaladnev':f'V08SYNTHETIC{n}','utonev':'\u00c1rv\u00edzt\u0171r\u0151','szuletesiDatum':dob,'allampolgarsagKod':'HUN','nem':'NO'}
        if n!=1:scanned.update(okmanyTipus='UTLEVEL',okmanyAzonositoSzam=f'V08-SYNTHETIC-ID-{n}')
        token=link['url'].rsplit('/',1)[-1];url='/api/public/checkin/'+token
        assert client.get(url).status_code==200
        payload={'full_name':f'V08 SYNTHETIC {n}','date_of_birth':dob,'nationality':'HUN','sex':'F','document_type':'passport' if n!=1 else '',
          'document_number':scanned.get('okmanyAzonositoSzam',''),'scanned_fields':scanned,'scan_method':'camera_mrz','guest_confirmed':True,
          'reader_context':{'mrz_format':'TD3'}}
        result=client.post(url,json=payload);assert result.status_code==200,result.text
        assert client.get(url).status_code==410
        originals[link['guest_record_id']]=scanned
        assert job_count(rid)==0
    login(client)
    gids=list(originals)
    for n,gid in enumerate(gids):
        manual={'csaladnev':'\u0150rfi'} if n==0 else {}
        reviewed=client.put(f'/api/registration/records/{gid}/viza-identity',json={'manual':manual,'reason':'V08 fictional owner review','third_country_applicable':False})
        assert reviewed.status_code==200,reviewed.text
        data=client.get(f'/api/registration/records/{gid}/viza-identity').json()
        assert data['original']==originals[gid]
        if n==0:assert data['manual']['utonev']==originals[gid]['utonev']
        verified=client.post(f'/api/reservations/{rid}/guests/{gid}/verify',json={'verification_method':'in_person'})
        assert verified.status_code==200,verified.text
        assert client.get(f'/api/registration/records/{gid}/viza-identity').json()['readiness']['ready']
        assert job_count(rid)==0
    fingerprint=synthetic_key(tmp_path,now)
    seen=[]
    def signed(job,wire_now):
        raw=delivery.render_bound_job(app,job,tmp_path,wire_now,credential_reference='v08_synthetic')
        operation='erkezesiAdatokBekuldese' if job['kind']=='arrival' else 'tavozasiAdatokBekuldese'
        parsed=contract.parse(operation,raw,response=False)
        members=parsed.erkezoVendeg if job['kind']=='arrival' else parsed.tavozoVendeg
        bound=Binding('org_casa_rosa','prop_flora','test',CONFIG['reporting_id'],CONFIG['endpoint'],'v08_synthetic')
        verify_property(parsed.pmsValidaciosUzenet,bound,[g.erkezesAzonosito for g in members],job['report_timestamp'],now=wire_now,expected_fingerprint=fingerprint)
        seen.append((operation,[g.erkezesAzonosito for g in members]));return raw
    mock=OfflineMockTransport(receipt)
    first,request=act(client,rid,[gids[0]],at,uid=units[0][0]);assert first.status_code==200,first.text
    assert client.post(f'/api/reservations/{rid}/actual-stay',json=request).json()['duplicate']
    group,_=act(client,rid,gids[1:],at+timedelta(hours=1),uid=units[0][0]);assert group.status_code==200,group.text
    assert job_count(rid)==2
    assert delivery.worker_once(app,transport=mock,renderer=signed,now=now)==2
    with app.db() as con:arrival_ids={r['guest_record_id']:r['arrival_uuid'] for r in con.execute('SELECT * FROM viza_visits WHERE reservation_id=?',(rid,))}
    assert len(set(arrival_ids.values()))==3
    moved,_=act(client,rid,[gids[0]],at+timedelta(hours=3),kind='transfer',uid=units[1][0]);assert moved.status_code==200,moved.text
    assert job_count(rid)==2
    app.init_db()
    with app.db() as con:assert {r['guest_record_id']:r['arrival_uuid'] for r in con.execute('SELECT * FROM viza_visits WHERE reservation_id=?',(rid,))}==arrival_ids
    monitor=OfflineMockTransport(lambda op,raw,bound,wire:status_raw(now,'WARNING|VIZA-OFFLINE') if op=='allapotLekerdezes' else contract.serialize(op,contract.Listing(eredmenyKod='OK'),response=True))
    assert delivery.monitor_once(app,'org_casa_rosa','prop_flora',transport=monitor,now=now)['state']=='mock_observed'
    for selector in ('NEMBEKULDOTT','HIBAS'):assert delivery.monitor_once(app,'org_casa_rosa','prop_flora',selector=selector,transport=monitor,now=now)['state']=='mock_observed'
    for n,gid in enumerate([gids[1],gids[0],gids[2]]):
        departed,_=act(client,rid,[gid],at+timedelta(hours=4+n),kind='depart');assert departed.status_code==200,departed.text
        assert delivery.worker_once(app,transport=mock,renderer=signed,now=now)==1
    report=client.get(BASE).json()
    own=[j for j in report['jobs'] if j['reservation_id']==rid]
    assert len(own)==5 and all(j['state']=='accepted' and j['mode']=='mock' for j in own)
    assert report['official_transmission_enabled'] is False
    assert all(g['downstream_state']=='unknown' for j in own for g in j['guests'])
    assert sorted(a for op,ids in seen if op=='tavozasiAdatokBekuldese' for a in ids)==sorted(arrival_ids.values())
    assert client.get(f'/api/reservations/{rid}/actual-stay').json()['actual_occupants']==0
    # Inspect stored paths without leaking values to diagnostics or generated evidence.
    secrets=['V08-SYNTHETIC-ID-0','V08-SYNTHETIC-ID-2','\u0150rfi','\u00c1rv\u00edzt\u0171r\u0151']
    with app.db() as con:
        for table,column in [('government_outbox','payload_json'),('government_scan_events','payload_json'),('government_delivery_attempts','response_summary')]:
            text=' '.join(str(r[column] or '') for r in con.execute(f'SELECT {column} FROM {table}'))
            assert all(secret not in text for secret in secrets)
        snapshots=con.execute('SELECT encrypted_facts FROM viza_jobs WHERE event_id IN (SELECT id FROM stay_events WHERE reservation_id=?)',(rid,)).fetchall()
        assert all(all(secret not in r['encrypted_facts'] for secret in secrets) for r in snapshots)
        for gid in gids:
            row=con.execute('SELECT date_of_birth,document_number FROM guest_records WHERE id=?',(gid,)).fetchone()
            assert row['date_of_birth'] is None and row['document_number'] is None
        with pytest.raises(sqlite3.IntegrityError):con.execute('UPDATE viza_jobs SET encrypted_facts=encrypted_facts WHERE id=?',(own[0]['id'],))
    assert 'V08-SYNTHETIC-ID' not in json.dumps(report)

@pytest.mark.parametrize('birthday_delta,is_minor',[(-1,False),(0,False),(1,True)])
def test_public_minor_boundary_with_normal_owner_review(client,birthday_delta,is_minor):
    _,units=setup(client);today=app.date.today();arrival=today-timedelta(days=2)
    p={**body(),'guest_count':1,'arrival_date':str(arrival),'departure_date':str(today+timedelta(days=2))}
    rid=client.post('/api/reservations',json=p).json()['id']
    assert assign(client,rid,p,[units[0][0]]).status_code==200
    link=client.get(f'/api/reservations/{rid}/guest-checkin-links').json()['links'][0]
    dob=arrival.replace(year=arrival.year-14)+timedelta(days=birthday_delta)
    scanned={'csaladnev':'V08SYNTHETIC','utonev':'Minor boundary','szuletesiDatum':str(dob),'allampolgarsagKod':'HUN','nem':'NO'}
    payload={'full_name':'V08 Synthetic minor boundary','date_of_birth':str(dob),'nationality':'HUN','sex':'F','scanned_fields':scanned,'scan_method':'manual','guest_confirmed':True}
    public='/api/public/checkin/'+link['url'].rsplit('/',1)[-1]
    response=client.post(public,json=payload)
    if not is_minor:
        assert response.status_code==400
        payload.update(document_type='passport',document_number='V08-SYNTHETIC-BOUNDARY')
        payload['scanned_fields'].update(okmanyTipus='UTLEVEL',okmanyAzonositoSzam='V08-SYNTHETIC-BOUNDARY')
        response=client.post(public,json=payload)
    assert response.status_code==200,response.text
    gid=link['guest_record_id']
    assert client.put(f'/api/registration/records/{gid}/viza-identity',json={'manual':{},'reason':'Synthetic age review','third_country_applicable':False}).status_code==200
    assert client.post(f'/api/reservations/{rid}/guests/{gid}/verify',json={}).status_code==200
    assert job_count(rid)==0
    at=app.datetime.fromisoformat(str(arrival)+'T12:00:00+01:00')
    assert act(client,rid,[gid],at,uid=units[0][0])[0].status_code==200
    with app.db() as con:
        row=con.execute('SELECT encrypted_facts FROM viza_jobs WHERE event_id IN (SELECT id FROM stay_events WHERE reservation_id=?)',(rid,)).fetchone()
        captured=app.decrypt_json(row['encrypted_facts'])['guests'][0]['identity']
        assert captured['ready']
        assert bool(captured['effective'].get('okmanyTipus'))!=is_minor


def test_public_untrusted_scan_method_cannot_leak_identity_into_audit(client):
    _,units=setup(client);p={**body(),'guest_count':1}
    rid=client.post('/api/reservations',json=p).json()['id']
    link=client.get(f'/api/reservations/{rid}/guest-checkin-links').json()['links'][0]
    response=client.post('/api/public/checkin/'+link['url'].rsplit('/',1)[-1],json={'full_name':'V08 Synthetic privacy','date_of_birth':'1990-01-02','nationality':'HUN','document_type':'passport','document_number':'V08-SYNTHETIC-SECRET','scan_method':'V08-SYNTHETIC-SECRET','guest_confirmed':True})
    assert response.status_code==422
    assert 'V08-SYNTHETIC-SECRET' not in response.text
    with app.db() as con:
        records=' '.join(r['metadata_json'] for r in con.execute('SELECT metadata_json FROM audit_events'))
        assert 'V08-SYNTHETIC-SECRET' not in records
    assert job_count(rid)==0


def test_public_link_rotation_and_payload_cannot_choose_another_guest(client):
    _,units=setup(client);p={**body(),'guest_count':1}
    rid=client.post('/api/reservations',json=p).json()['id']
    old=client.get(f'/api/reservations/{rid}/guest-checkin-links').json()['links'][0]
    current=client.get(f'/api/reservations/{rid}/guest-checkin-links').json()['links'][0]
    # Rotation removes the old token hash; absence (404) is the intended denial.
    assert client.get('/api/public/checkin/'+old['url'].rsplit('/',1)[-1]).status_code==404
    rt=client.get('/api/properties/prop_terra/room-types').json()['room_types'][0]['id']
    victim=client.post('/api/reservations',json={**p,'property_id':'prop_terra','room_type_id':rt}).json()['id']
    other=client.get(f'/api/reservations/{victim}/guest-checkin-links').json()['links'][0]['guest_record_id']
    public='/api/public/checkin/'+current['url'].rsplit('/',1)[-1]
    client.cookies.clear();client.headers.pop('X-Rosa-CSRF',None)
    assert client.post(public,json={'guest_record_id':other,'full_name':'V08 Synthetic token scope','date_of_birth':'1990-01-02','nationality':'HUN','document_type':'passport','document_number':'V08-SYNTHETIC-SCOPED','scan_method':'manual','guest_confirmed':True}).status_code==200
    assert client.get(public).status_code==410
    with app.db() as con:
        assert con.execute('SELECT completeness FROM guest_records WHERE id=?',(other,)).fetchone()['completeness']=='incomplete'
        assert not con.execute('SELECT 1 FROM sensitive_guest_data WHERE guest_record_id=?',(other,)).fetchone()
    assert job_count(victim)==0 and job_count(rid)==0

def test_owner_correction_after_capture_never_sends_obsolete_identity(client):
    from test_viza_delivery import fixture_job,renderer,dispatch
    from test_viza_identity_capture import edit
    rid,jid,now=fixture_job(client)
    guest=client.get(BASE).json()['jobs'][0]['guests'][0]['guest_id']
    assert edit(client,guest,{'csaladnev':'V08 Synthetic corrected after capture'}).status_code==200
    mock=OfflineMockTransport(receipt)
    delivery.worker_once(app,transport=mock,renderer=renderer,now=now)
    assert not mock.calls,'A correction requiring renewed verification must not send the old verified snapshot'
    assert client.post(f'/api/reservations/{rid}/guests/{guest}/verify',json={}).status_code==200
    delivery.worker_once(app,transport=mock,renderer=renderer,now=now)
    assert len(mock.calls)==1
    with app.db() as con:
        old=con.execute('SELECT state FROM viza_jobs WHERE id=?',(jid,)).fetchone()
        assert old['state']=='superseded_before_submission'
        sent=con.execute("SELECT encrypted_facts FROM viza_jobs WHERE event_id IN (SELECT id FROM stay_events WHERE reservation_id=?) AND state='accepted'",(rid,)).fetchone()
        assert app.decrypt_json(sent['encrypted_facts'])['guests'][0]['identity']['effective']['csaladnev']=='V08 Synthetic corrected after capture'

def test_correction_during_render_is_held_before_send_marker(client):
    from test_viza_delivery import fixture_job,renderer,dispatch
    from test_viza_identity_capture import edit
    rid,jid,now=fixture_job(client)
    guest=client.get(BASE).json()['jobs'][0]['guests'][0]['guest_id']
    def changed(job,clock):
        raw=renderer(job,clock)
        assert edit(client,guest,{'csaladnev':'V08 Late synthetic correction'}).status_code==200
        return raw
    mock=OfflineMockTransport(receipt)
    assert delivery.worker_once(app,transport=mock,renderer=changed,now=now)==0
    assert not mock.calls and dispatch(jid)['state']=='blocked'
    with app.db() as con:assert con.execute('SELECT attempts FROM viza_jobs WHERE id=?',(jid,)).fetchone()['attempts']==0


def test_unsent_source_refresh_preserves_departure_dependencies(client):
    from test_viza_delivery import fixture_job,renderer
    from test_viza_identity_capture import edit
    rid,jid,now=fixture_job(client)
    guest=client.get(BASE).json()['jobs'][0]['guests'][0]['guest_id']
    depart,_=act(client,rid,[guest],now-timedelta(days=1),kind='depart');assert depart.status_code==200,depart.text
    with app.db() as con:delivery.synchronize(app,con,now)
    assert edit(client,guest,{'csaladnev':'V08 Synthetic replacement'}).status_code==200
    assert client.post(f'/api/reservations/{rid}/guests/{guest}/verify',json={}).status_code==200
    mock=OfflineMockTransport(receipt)
    assert delivery.worker_once(app,transport=mock,renderer=renderer,now=now)==2
    assert [call[0] for call in mock.calls]==['erkezesiAdatokBekuldese','tavozasiAdatokBekuldese']
    own=[j for j in client.get(BASE).json()['jobs'] if j['reservation_id']==rid]
    assert [j['kind'] for j in own if j['state']=='accepted'].count('departure')==1
    with app.db() as con:
        assert con.execute('SELECT state FROM viza_jobs WHERE id=?',(jid,)).fetchone()['state']=='superseded_before_submission'
