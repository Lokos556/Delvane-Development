"""Queue and monitoring verification against injected in-process fictional THF responses."""
from datetime import timedelta,timezone
from concurrent.futures import ThreadPoolExecutor
import json,uuid
import pytest
import app,viza_delivery as d,viza_contracts as c,viza_reporting as capture
from viza_security import OfflineMockTransport,DefinitelyNotSent,OutcomeUncertain,PermanentFailure,DisabledOfficialTransport
from test_flutter_reservation_reception import client,login
from test_actual_stays import prepared,act
from test_viza_identity_capture import edit,FIELDS

BASE='/api/government/viza/properties/prop_flora'
CONFIG={'environment':'test','reporting_id':'TEST0000','endpoint':'https://fictional-thf.invalid/ws','property_name':'Fictional accommodation','provider_name':'Fictional provider','provider_tax':'12345678-1-12','poll_minutes':5}

def fixture_job(client,count=1):
    rid,_,units,gids,at=prepared(client)
    assert client.put(BASE+'/settings',json=CONFIG).status_code==200
    for gid in gids[:count]:
        assert edit(client,gid,FIELDS).status_code==200
        assert client.post(f'/api/reservations/{rid}/guests/{gid}/verify',json={}).status_code==200
    response,_=act(client,rid,gids[:count],at,uid=units[0][0]);assert response.status_code==200,response.text
    now=app.datetime.now(timezone.utc)
    with app.db() as con:
        d.synchronize(app,con,now)
        jid=con.execute('SELECT id FROM viza_jobs WHERE event_id=?',(response.json()['id'],)).fetchone()['id']
    return rid,jid,now

def renderer(job,now):
    cfg=job['config']
    header={'uzenetAzonosito':job['id'],'szallashely':{'adatszolgaltatasiAzonosito':cfg['reporting_id'],'szallasNev':cfg['property_name'],'szallashelySzolgaltatoAdoszam':cfg['provider_tax'],'szallashelySzolgaltatoNev':cfg['provider_name']},'bejelentesIdopontja':job['report_timestamp'],'pmsValidaciosUzenet':c.Validation(ellenorzoString='MOCK ONLY',alairoTanusitvany='MOCK ONLY',alairas='MOCK ONLY')}
    return capture.request_for_snapshot(app,job,header)

def receipt(op,raw,bound,wire,*,mixed=False,rejected=False):
    request=c.parse(op,raw,response=False)
    guests=request.erkezoVendeg if hasattr(request,'erkezoVendeg') else request.tavozoVendeg
    outcomes=[c.Outcome(erkezesAzonosito=g.erkezesAzonosito,hibaKod='EF0034;EF0036' if rejected or mixed and i==0 else 'OK',hibaSzoveg='Fictional private explanation') for i,g in enumerate(guests)]
    dto=c.Receipt(sikeresBefogadas=not rejected,fogadasAzonosito=str(uuid.uuid4()),fogadasIdeje=app.datetime.now(timezone.utc),hibaLista=outcomes)
    return c.serialize(op,dto,response=True)

def dispatch(jid):
    with app.db() as con:return dict(con.execute('SELECT * FROM viza_dispatch WHERE job_id=?',(jid,)).fetchone())

def test_automatic_capture_and_mock_receipt_concurrent_workers(client):
    rid,jid,now=fixture_job(client)
    transport=OfflineMockTransport(receipt)
    with ThreadPoolExecutor(max_workers=2) as pool:counts=list(pool.map(lambda _:d.worker_once(app,transport=transport,renderer=renderer,now=now),[0,1]))
    assert sum(counts)==1 and len(transport.calls)==1
    row=dispatch(jid);assert row['state']=='accepted' and row['mode']=='mock'
    data=client.get(BASE).json();assert data['official_transmission_enabled'] is False
    assert data['jobs'][0]['guests'][0]['downstream_state']=='unknown'
    assert 'Fictional private explanation' not in json.dumps(data)
    assert d.worker_once(app,transport=transport,renderer=renderer,now=now)==0
    app.init_db();assert dispatch(jid)['receipt_id']==row['receipt_id']
    with app.db() as con:
        assert con.execute('SELECT COUNT(*) n FROM government_delivery_attempts WHERE outbox_id=?',(jid,)).fetchone()['n']==1
        assert con.execute('SELECT encrypted_response FROM viza_attempts WHERE job_id=?',(jid,)).fetchone()['encrypted_response']

@pytest.mark.parametrize('attempt,delay',[(1,0),(2,0),(3,17),(4,600),(5,3600),(6,21600),(7,86400),(12,86400)])
def test_retry_schedule(attempt,delay):assert d.retry_delay(attempt,lambda a,b:17)==delay

def test_definitely_not_sent_timing_and_no_pms_outage(client):
    rid,jid,now=fixture_job(client)
    def unavailable(*args):raise DefinitelyNotSent('Do not log fictional identity')
    mock=OfflineMockTransport(unavailable)
    assert d.worker_once(app,transport=mock,renderer=renderer,now=now,randint=lambda a,b:17,limit=10)==3
    assert dispatch(jid)['due_at']==d.stamp(now+timedelta(seconds=17))
    assert d.worker_once(app,transport=mock,renderer=renderer,now=now+timedelta(seconds=16))==0
    assert d.worker_once(app,transport=mock,renderer=renderer,now=now+timedelta(seconds=17),limit=1)==1
    assert dispatch(jid)['due_at']==d.stamp(now+timedelta(seconds=617))
    assert client.get(f'/api/reservations/{rid}/actual-stay').json()['actual_occupants']==1

@pytest.mark.parametrize('failure,state',[(OutcomeUncertain,'uncertain'),(PermanentFailure,'rejected')])
def test_uncertain_and_permanent_do_not_replay(client,failure,state):
    _,jid,now=fixture_job(client)
    def failed(*args):raise failure('Fictional secret must not enter diagnostics')
    mock=OfflineMockTransport(failed)
    assert d.worker_once(app,transport=mock,renderer=renderer,now=now)==1
    assert dispatch(jid)['state']==state
    assert d.worker_once(app,transport=mock,renderer=renderer,now=now+timedelta(days=1))==0
    assert client.post(BASE+f'/jobs/{jid}/recover',json={'action':'retry_not_sent'}).status_code==409


def test_mixed_per_guest_errors_are_preserved_without_batch_success(client):
    _,jid,now=fixture_job(client,2)
    mock=OfflineMockTransport(lambda *a:receipt(*a,mixed=True))
    assert d.worker_once(app,transport=mock,renderer=renderer,now=now)==1
    assert dispatch(jid)['state']=='review_required'
    data=client.get(BASE).json();guests=data['jobs'][0]['guests']
    assert {g['state'] for g in guests}=={'rejected','accepted_candidate'}
    rejected=next(g for g in guests if g['errors'])
    assert [e['code'] for e in rejected['errors']]==['EF0034','EF0036']
    assert all(e['message_en'] and e['message_hu'] for e in rejected['errors'])


def test_claim_crash_and_sending_crash_recovery(client):
    _,jid,now=fixture_job(client)
    first=d.claim(app,now,mode='mock');assert first
    with app.db() as con:d.recover_leases(con,now+timedelta(seconds=61))
    second=d.claim(app,now+timedelta(seconds=61),mode='mock');assert second and first['claim_id']!=second['claim_id']
    with app.db() as con:
        con.execute("UPDATE viza_dispatch SET state='sending' WHERE job_id=?",(jid,))
        d.recover_leases(con,now+timedelta(seconds=122))
    assert dispatch(jid)['state']=='uncertain'
    assert d.claim(app,now+timedelta(days=1),mode='mock') is None


def test_environment_binding_and_official_disabled(client):
    _,jid,now=fixture_job(client)
    assert d.worker_once(app,transport=DisabledOfficialTransport(),renderer=renderer,now=now)==0
    assert client.put(BASE+'/settings',json={**CONFIG,'environment':'production'}).status_code==200
    assert dispatch(jid)['error_code']=='environment_or_configuration_changed'
    assert d.worker_once(app,transport=OfflineMockTransport(receipt),renderer=renderer,now=now)==0
    assert client.post(BASE+'/observe').json()['code']=='official_transmission_disabled'
    assert client.post(BASE+'/lists/HIBAS').json()['code']=='official_transmission_disabled'


def status_raw(now,code='OK'):
    return c.serialize('allapotLekerdezes',c.Status(szoftverVerzio='Fictional 7',allapotKod=code,bekuldetlenUzenetekSzama=2,hibasUzenetekSzama=1,idoPecset=now),response=True)

@pytest.mark.parametrize('flag',sorted(d.FLAGS))
def test_all_health_flags(flag):
    value=c.parse('allapotLekerdezes',status_raw(app.datetime.now(timezone.utc),('ERROR' if flag=='CERT-EXPIRED' else 'WARNING')+'|'+flag))
    assert d.parse_health(value)['flags']==[flag]


def test_monitor_polling_stale_and_lists_do_not_prove_delivery(client):
    _,jid,now=fixture_job(client)
    def thf(op,raw,bound,wire):
        if op=='allapotLekerdezes':return status_raw(now,'WARNING|VIZA-OFFLINE|KM-OFFLINE|OUTOFKEYS')
        selector=c.parse(op,raw,response=False).bekuldetlenAdatTipus
        return c.serialize(op,c.Listing(eredmenyKod='OK',bekuldetlenAdat=[c.Unsent(uzenetAzonosito=jid,adatszolgaltatasiAzonosito=CONFIG['reporting_id'],hibaUzenet='EF0034;EF0036: Fictional confidential text')] if selector=='HIBAS' else []),response=True)
    mock=OfflineMockTransport(thf)
    assert d.monitor_once(app,'org_casa_rosa','prop_flora',transport=mock,now=now)['state']=='mock_observed'
    assert d.monitor_once(app,'org_casa_rosa','prop_flora',transport=mock,now=now+timedelta(minutes=1))['state']=='not_due'
    for selector in ('NEMBEKULDOTT','HIBAS'):assert d.monitor_once(app,'org_casa_rosa','prop_flora',selector=selector,transport=mock,now=now)['state']=='mock_observed'
    model=client.get(BASE).json();assert model['health']['mode']=='mock' and model['health']['unsent']==2
    assert model['lists']['NEMBEKULDOTT']['delivery_inferred'] is False
    assert model['lists']['HIBAS']['items'][0]['codes']==['EF0034','EF0036']
    assert 'Fictional confidential text' not in json.dumps(model)
    with app.db() as con:
        from viza_api import read_model
        assert read_model(app,con,'org_casa_rosa','prop_flora',now+timedelta(minutes=11))['health']['state']=='stale'
    assert dispatch(jid)['state']=='blocked'

@pytest.mark.parametrize('raw',[b'<malformed',b'<!DOCTYPE x><x/>',b'x'*(8*1024*1024+1)],ids=['malformed','dtd','oversize'])
def test_invalid_receipt_held_uncertain(client,raw):
    _,jid,now=fixture_job(client)
    assert d.worker_once(app,transport=OfflineMockTransport(lambda *a:raw),renderer=renderer,now=now)==1
    assert dispatch(jid)['state']=='uncertain'


def test_admin_authorization_csrf_and_repeatable_migration(client):
    _,jid,now=fixture_job(client)
    assert client.get('/api/government/viza/properties/other-tenant-property').status_code==404
    assert client.put(BASE+'/settings',json={**CONFIG,'poll_minutes':0}).status_code==422
    assert client.put(BASE+'/settings',json={**CONFIG,'private_key':'FORBIDDEN'}).status_code==422
    login(client,'manager');assert client.put(BASE+'/settings',json=CONFIG).status_code==403
    login(client,'cleaner');assert client.get(BASE).status_code==403
    login(client);client.headers.pop('X-Rosa-CSRF');assert client.post(BASE+'/observe').status_code==403
    with app.db() as con:d.migrate(con,app.now_iso());d.migrate(con,app.now_iso())

def test_list_limit_property_scope_and_unknown_correlation(client):
    _,jid,now=fixture_job(client)
    unknown=str(uuid.uuid4())
    def listed(items):return OfflineMockTransport(lambda *a:c.serialize('bekuldetlenAdatLista',c.Listing(eredmenyKod='OK',bekuldetlenAdat=items),response=True))
    wrong=c.Unsent(uzenetAzonosito=jid,adatszolgaltatasiAzonosito='OTHER000')
    assert d.monitor_once(app,'org_casa_rosa','prop_flora',selector='HIBAS',transport=listed([wrong]),now=now)['state']=='unknown'
    assert 'HIBAS' not in client.get(BASE).json()['lists']
    item=c.Unsent(uzenetAzonosito=unknown,adatszolgaltatasiAzonosito=CONFIG['reporting_id'])
    future=now+timedelta(minutes=5)
    result=d.monitor_once(app,'org_casa_rosa','prop_flora',selector='HIBAS',transport=listed([item]*10000),now=future)
    assert result['state']=='mock_observed'
    model=client.get(BASE).json()['lists']['HIBAS'];assert model['limit_reached'] and model['total']==10000 and len(model['items'])==100
    page=client.get(BASE+'/lists/HIBAS?offset=9900&limit=100').json();assert len(page['items'])==100 and page['items'][0]['correlation']=='unknown_message'
    assert client.get(BASE+'/lists/HIBAS?offset=-1').status_code==422
    with pytest.raises(ValueError):c.Listing(eredmenyKod='OK',bekuldetlenAdat=[item]*10001)


def test_request_and_receipt_correlation_hold_without_outcome_pollution(client):
    _,jid,now=fixture_job(client)
    def wrong_request(job,when):
        raw=renderer(job,when)
        return raw.replace(job['id'].encode(),str(uuid.uuid4()).encode())
    mock=OfflineMockTransport(receipt)
    assert d.worker_once(app,transport=mock,renderer=wrong_request,now=now)==0
    assert not mock.calls and dispatch(jid)['error_code']=='request_validation_failed'
    with app.db() as con:con.execute("UPDATE viza_dispatch SET error_code=NULL WHERE job_id=?",(jid,))
    def wrong_receipt(op,raw,bound,wire):
        data=c.parse(op,receipt(op,raw,bound,wire));data.hibaLista[0].erkezesAzonosito=str(uuid.uuid4())
        return c.serialize(op,data,response=True)
    assert d.worker_once(app,transport=OfflineMockTransport(wrong_receipt),renderer=renderer,now=now)==1
    assert dispatch(jid)['state']=='uncertain'
    with app.db() as con:assert con.execute('SELECT COUNT(*) n FROM viza_guest_outcomes WHERE job_id=?',(jid,)).fetchone()['n']==0


def test_status_unknown_errors_and_concurrent_poll_claims(client):
    from threading import Event
    _,jid,now=fixture_job(client)
    assert client.get(BASE).json()['health']['unsent'] is None
    entered=Event();release=Event()
    def delayed(*args):entered.set();assert release.wait(5);return status_raw(now,'ERROR|CERT-EXPIRED')
    with ThreadPoolExecutor(max_workers=2) as pool:
        first=pool.submit(d.monitor_once,app,'org_casa_rosa','prop_flora',transport=OfflineMockTransport(delayed),now=now)
        assert entered.wait(5)
        second=d.monitor_once(app,'org_casa_rosa','prop_flora',transport=OfflineMockTransport(delayed),now=now)
        assert second['state']=='busy'
        release.set();assert first.result()['state']=='mock_observed'
    for bad in ('INVALID','OK|UNKNOWN-FLAG','OK|OK'):
        with pytest.raises(c.ContractError):d.parse_health(c.parse('allapotLekerdezes',status_raw(now,bad)))
    assert client.get(BASE).json()['health']['primary']=='ERROR'


def test_every_documented_code_has_localized_details_and_pinned_binding(client):
    import sqlite3
    from viza_api import error_details,ERROR_EN
    assert set(ERROR_EN)==set(c.ERRORS)
    for code in c.ERRORS:
        detail=error_details(code);assert detail['message_en'] and detail['message_hu'] and detail['page']
    _,jid,now=fixture_job(client)
    with app.db() as con:
        with pytest.raises(sqlite3.IntegrityError):con.execute("UPDATE viza_dispatch SET environment='production' WHERE job_id=?",(jid,))

def test_property_signed_body_preserves_exact_header_timestamp(client,tmp_path):
    from cryptography import x509
    from cryptography.x509.oid import NameOID
    from cryptography.hazmat.primitives import hashes,serialization
    from cryptography.hazmat.primitives.asymmetric import rsa
    from viza_security import verify_property,Binding
    _,jid,now=fixture_job(client)
    key=rsa.generate_private_key(public_exponent=65537,key_size=4096)
    subject=x509.Name([x509.NameAttribute(NameOID.COMMON_NAME,CONFIG['reporting_id'])])
    cert=x509.CertificateBuilder().subject_name(subject).issuer_name(subject).public_key(key.public_key()).serial_number(x509.random_serial_number()).not_valid_before(now-timedelta(days=1)).not_valid_after(now+timedelta(days=30)).sign(key,hashes.SHA256())
    folder=tmp_path/'fictional';folder.mkdir()
    (folder/'private-key.pem').write_bytes(key.private_bytes(serialization.Encoding.PEM,serialization.PrivateFormat.PKCS8,serialization.NoEncryption()))
    (folder/'certificate.pem').write_bytes(cert.public_bytes(serialization.Encoding.PEM))
    (folder/'binding.json').write_text(json.dumps({'system':'VIZA','organization_id':'org_casa_rosa','property_id':'prop_flora','environment':'test','reporting_id':CONFIG['reporting_id'],'endpoint':CONFIG['endpoint'],'certificate_sha256':cert.fingerprint(hashes.SHA256()).hex()}),encoding='utf8')
    seen=[]
    def signed(job,when):
        raw=d.render_bound_job(app,job,tmp_path,when,credential_reference='fictional')
        request=c.parse('erkezesiAdatokBekuldese',raw,response=False)
        exact=c.xml_root(raw).find('.//{'+c.NS+'}bejelentesIdopontja').text
        assert exact==job['report_timestamp']
        b=Binding(job['organization_id'],job['property_id'],'test',CONFIG['reporting_id'],CONFIG['endpoint'],'fictional')
        verify_property(request.pmsValidaciosUzenet,b,[g.erkezesAzonosito for g in request.erkezoVendeg],exact,now=when,expected_fingerprint=cert.fingerprint(hashes.SHA256()).hex())
        seen.append(raw);return raw
    assert d.worker_once(app,transport=OfflineMockTransport(receipt),renderer=signed,now=now)==1
    assert len(seen)==1 and dispatch(jid)['state']=='accepted'


def test_downstream_rejection_does_not_invent_batch_guest_outcomes(client):
    _,jid,now=fixture_job(client,2)
    assert d.worker_once(app,transport=OfflineMockTransport(receipt),renderer=renderer,now=now)==1
    raw=c.serialize('bekuldetlenAdatLista',c.Listing(eredmenyKod='OK',bekuldetlenAdat=[c.Unsent(uzenetAzonosito=jid,adatszolgaltatasiAzonosito=CONFIG['reporting_id'],hibaUzenet='EF0034')]),response=True)
    assert d.monitor_once(app,'org_casa_rosa','prop_flora',selector='HIBAS',transport=OfflineMockTransport(lambda *a:raw),now=now)['state']=='mock_observed'
    job=client.get(BASE).json()['jobs'][0]
    assert job['downstream_state']=='rejected'
    assert all(g['downstream_state']=='message_rejected_guest_scope_unknown' for g in job['guests'])
    assert len(job['attempt_history'])==1

def test_polling_configuration_does_not_rebind_immutable_message(client):
    _,jid,now=fixture_job(client)
    original=dispatch(jid)
    for interval in (1,60):assert client.put(BASE+'/settings',json={**CONFIG,'poll_minutes':interval}).status_code==200
    assert client.put(BASE+'/settings',json={**CONFIG,'poll_minutes':61}).status_code==422
    after=dispatch(jid)
    assert after['binding_digest']==original['binding_digest'] and after['encrypted_binding']==original['encrypted_binding']
    assert after['error_code'] is None
    assert d.worker_once(app,transport=OfflineMockTransport(receipt),renderer=renderer,now=now)==1
    assert dispatch(jid)['state']=='accepted'

def test_superseded_during_render_is_not_transmitted(client):
    _,jid,now=fixture_job(client)
    def supersede(job,when):
        raw=renderer(job,when)
        with app.db() as con:con.execute("UPDATE viza_jobs SET state='superseded_before_submission' WHERE id=?",(jid,))
        return raw
    mock=OfflineMockTransport(receipt)
    assert d.worker_once(app,transport=mock,renderer=supersede,now=now)==0
    assert not mock.calls and dispatch(jid)['state']=='superseded_before_submission'
