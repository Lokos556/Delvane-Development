"""Fictional data and injected SOAP adapter only; network guard remains active."""
from datetime import timedelta, timezone
import json
import uuid
import pytest
import app
import ntak_reporting as r
from ntak_contracts import NAMESPACE, OPERATIONS, validate
from ntak_protocol import ReportingBlocked, guest_hash, request_xml
from test_flutter_reservation_reception import client, login, body

CONFIG={'enabled':True,'environment':'test','registration_id':'MA99000001',
        'provider_vat':'12345678-1-12','software_id':'FICTIONAL','software_version':'1.0',
        'timezone':'Europe/Budapest','closing_hour':10}
FACTS={'garantaltFoglalas':True,'vendegKuldoOrszaga':'HU','ertekesitesiCsatorna':'DIREKT_ONLINE',
       'foglaltLakoegysegek':{'foglaltLakoegyseg':[{'tipus':'APARTMAN','ferohelyKapacitas':2}]},
       'piaciSzegmens':'SZABADIDOS_EGYENI'}
BASE='/api/government/ntak/properties/prop_flora'


def configured(client):
    login(client)
    response=client.put(BASE,json=CONFIG)
    assert response.status_code==200,response.text
    data=body();data['total_huf']=42000
    made=client.post('/api/reservations',json=data)
    assert made.status_code==200,made.text
    rid=made.json()['id']
    saved=client.put(BASE+f'/reservations/{rid}/facts',json={'values':FACTS,'evidence':'Fictional booking record'})
    assert saved.status_code==200,saved.text
    return rid,saved.json()['job_id']


def get(job):
    with app.db() as con:return dict(con.execute('SELECT * FROM ntak_jobs WHERE id=?',(job,)).fetchone())


class SoapMock:
    def __init__(self,status='TELJESEN_SIKERES',error=None):
        self.status,self.error,self.calls=status,error,[]
        self.receipt=str(uuid.uuid4())
    def exchange(self,operation,xml,**scope):
        validate(operation,xml)
        self.calls.append((operation,xml,scope))
        if self.error=='timeout':raise TimeoutError()
        if self.error and operation!='verification':
            name=OPERATIONS[operation]+'Response'
            return f'<{name} xmlns="{NAMESPACE}"><hibaLista><hiba><mezoNeve>GLOBAL</mezoNeve><kuldottErtek/><hibaKulcs>{self.error}</hibaKulcs><hibaUzenet>Fictional error</hibaUzenet></hiba></hibaLista><figyelmeztetesLista/></{name}>'.encode()
        if operation=='verification':
            return f'<ellenorzesResponse xmlns="{NAMESPACE}"><uzenetValaszok><feldolgozasAzonosito>{self.receipt}</feldolgozasAzonosito><statusz>{self.status}</statusz><figyelmeztetesLista/><hibaLista/></uzenetValaszok></ellenorzesResponse>'.encode()
        name=OPERATIONS[operation]+'Response'
        return f'<{name} xmlns="{NAMESPACE}"><feldolgozasAzonosito>{self.receipt}</feldolgozasAzonosito></{name}>'.encode()


def test_reservation_lifecycle_and_default_transmission_block(client):
    rid,job=configured(client)
    assert get(job)['state']=='ready'
    before=client.get(BASE).json()['jobs']
    assert len(before)==2 and any(x['error_code']=='missing_reporting_data' for x in before)
    saved=client.put(BASE+f'/reservations/{rid}/facts',json={'values':FACTS,'evidence':'Same record'})
    assert saved.json()['job_id'] is None
    assert client.patch('/api/reservations/'+rid,json={'total_huf':43000}).status_code==200
    assert client.delete('/api/reservations/'+rid).status_code==200
    with app.db() as con:
        rows=con.execute("SELECT payload_json FROM ntak_jobs WHERE state='ready'").fetchall()
        assert len(rows)==3
        assert any(json.loads(x['payload_json'])['foglalasEsemeny']['lemondva'] for x in rows)
    r.worker_once(app.db)
    assert get(job)['state']=='blocked' and get(job)['error_code']=='signature_profile_unresolved'
    assert client.get(BASE).json()['connected'] is False


def test_receipt_is_not_success_and_restart_preserves_receipt(client):
    _,job=configured(client);now=r.datetime.now(timezone.utc);mock=SoapMock()
    r.worker_once(app.db,transport=mock,now=now)
    assert get(job)['state']=='accepted'
    assert client.get(BASE).json()['last_success_at'] is None
    app.init_db()  # same isolated test store, no reset
    r.worker_once(app.db,transport=mock,now=now+timedelta(minutes=6))
    assert get(job)['state']=='succeeded'
    assert [x[0] for x in mock.calls]==['reservation','verification']
    assert client.get(BASE).json()['last_success_at']


def test_timeout_no_blind_retry_and_receipt_reconciliation(client):
    _,job=configured(client);now=r.datetime.now(timezone.utc);mock=SoapMock(error='timeout')
    r.worker_once(app.db,transport=mock,now=now)
    r.worker_once(app.db,transport=mock,now=now+timedelta(days=1))
    assert get(job)['state']=='uncertain' and len(mock.calls)==1
    denied=client.post(BASE+f'/jobs/{job}/recovery',json={'action':'retry_after_resolution','reason':'Fictional support resolution'})
    assert denied.status_code==409
    mock.error=None
    restored=client.post(BASE+f'/jobs/{job}/recovery',json={'action':'record_processing_id','reason':'Fictional official receipt','processing_id':mock.receipt})
    assert restored.status_code==200
    r.worker_once(app.db,transport=mock,now=now+timedelta(minutes=6))
    assert get(job)['state']=='succeeded'


def test_server_error_exact_retry_delays_and_exhaustion(client):
    _,job=configured(client);now=r.datetime.now(timezone.utc);mock=SoapMock(error='SzerverHiba')
    for delay in (1,10,60):
        r.worker_once(app.db,transport=mock,now=now)
        state=get(job)
        assert state['state']=='retry'
        assert r.datetime.fromisoformat(state['next_attempt_at'])==now+timedelta(minutes=delay)
        now+=timedelta(minutes=delay)
    r.worker_once(app.db,transport=mock,now=now)
    assert get(job)['state']=='retry_exhausted' and len(mock.calls)==4
    assert len({x[1] for x in mock.calls})==1  # identical unsigned body on retries


@pytest.mark.parametrize('status,expected',[('BEFOGADVA','accepted'),('TELJESEN_HIBAS','rejected'),('VIZSGALANDO','review_required'),('UJRA_KULDENDO','retry')])
def test_processing_states(client,status,expected):
    _,job=configured(client);now=r.datetime.now(timezone.utc);mock=SoapMock(status=status)
    r.worker_once(app.db,transport=mock,now=now)
    r.worker_once(app.db,transport=mock,now=now+timedelta(minutes=6))
    assert get(job)['state']==expected


def test_expired_worker_lease_becomes_uncertain(client):
    _,job=configured(client);now=r.datetime.now(timezone.utc)
    with app.db() as con:con.execute("UPDATE ntak_jobs SET state='sending',lease_until=? WHERE id=?",(r.stamp(now-timedelta(minutes=1)),job))
    mock=SoapMock();r.worker_once(app.db,transport=mock,now=now)
    assert get(job)['state']=='uncertain' and not mock.calls


def closing(day):
    return {'lezartNap':day,'napiZarasBesorolas':{'besorolas':'UJ'},'lezarasIdopont':r.stamp(),
      'szallashelyNemUzemel':False,'szobaAdatok':{'osszesSzoba':1,'oooSzobak':0,'oosSzobak':0,'kiadottSzobak':0,'kiadhatoSzobak':1},
      'ferohelyAdatok':{'osszesFerohelyKapacitas':2,'oooFerohelyKapacitas':0,'oosFerohelyKapacitas':0,'kiadottFerohelyKapacitas':0,'kiadhatoFerohelyKapacitas':2}}


def test_daily_scheduler_missing_facts_confirmation_and_correction(client):
    login(client);now=r.datetime.now(timezone.utc);day=str((now-timedelta(days=2)).date())
    cfg={**CONFIG,'reporting_start_date':day,'reporting_start_evidence':'Fictional official start-date record'}
    assert client.put(BASE,json=cfg).status_code==200
    assert client.get(BASE).json()['daily_closings'][0]['state']=='awaiting_closing_facts'
    data=closing(day)
    url=BASE+'/daily-closing/'+day
    first=client.put(url,json={'values':data,'evidence':'Operator confirmed complete fictional ledger'})
    assert first.status_code==200,first.text
    assert client.put(url,json={'values':data,'evidence':'Same facts'}).json()['duplicate']
    with app.db() as con:
        r.schedule_daily(con,now);r.schedule_daily(con,now)
        assert con.execute("SELECT COUNT(*) c FROM ntak_jobs WHERE operation='daily_close'").fetchone()['c']==1
    data['szallashelyNemUzemel']=True
    assert client.put(url,json={'values':data,'evidence':'Correction'}).status_code==409
    data['napiZarasBesorolas']={'besorolas':'MODOSITO','jegyzokonyvAzonosito':'fictional-1','indoklas':'Fictional operating-status correction'}
    assert client.put(url,json={'values':data,'evidence':'Correction evidence'}).status_code==200


def test_authorization_environment_and_no_secrets(client):
    _,job=configured(client)
    assert client.get(BASE.replace('prop_flora','unknown')).status_code==404
    assert client.put(BASE,json={**CONFIG,'environment':'production'}).status_code==409
    assert client.put(BASE,json={**CONFIG,'private_key':'do-not-accept'}).status_code==422
    login(client,'cleaner');assert client.get(BASE).status_code==403
    login(client,'manager');assert client.put(BASE,json=CONFIG).status_code==403
    login(client);client.headers.pop('X-Rosa-CSRF')
    assert client.put(BASE,json=CONFIG).status_code==403


def test_official_guest_hash_example():
    assert guest_hash('dr. Teszt Edit Budapest 1979.07.12.',b'$2a$10$zDaBMMumxc/1rLNjHHg55O')=='473/rnEtql5aigjoPG33qz1uARVImcW'


def test_unresolved_information_and_idempotent_event_binding(client):
    configured(client)
    with app.db() as con:
        job=r.enqueue(con,'org_casa_rosa','prop_flora',CONFIG,'information','information:1',{})
        assert r.enqueue(con,'org_casa_rosa','prop_flora',CONFIG,'information','information:1',{})==job
        with pytest.raises(ReportingBlocked):r.enqueue(con,'org_casa_rosa','prop_flora',CONFIG,'information','information:1',{'invented':True})
    assert get(job)['error_code']=='information_response_contract_unresolved'


def test_scanning_one_guest_of_two_cannot_complete_registration(client):
    login(client);data=body();data['total_huf']=10000
    rid=client.post('/api/reservations',json=data).json()['id']
    with app.db() as con:gid=con.execute('SELECT id FROM guest_records WHERE reservation_id=? ORDER BY id',(rid,)).fetchone()['id']
    result=client.post('/api/government/viza/id-scan',json={'reservation_id':rid,'guest_record_id':gid,'full_name':'Fictional Guest','date_of_birth':'1990-01-02','nationality':'HUN','document_type':'ID','document_number':'FICTIONAL'})
    assert result.status_code==200 and result.json()['registration_status']=='incomplete'
    verified=client.post(f'/api/reservations/{rid}/guests/{gid}/verify',json={'decision':'verify','verification_method':'in_person'})
    assert verified.json()['registration_status']=='incomplete'
    assert verified.json()['government_submission_queued'] is False
