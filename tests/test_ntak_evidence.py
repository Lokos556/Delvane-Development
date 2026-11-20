"""Synthetic immutable protocol/evidence rehearsal, not official validation."""
import base64
from concurrent.futures import ThreadPoolExecutor
from datetime import timedelta,timezone
import json
import uuid
import pytest
import app
import ntak_evidence as e
import ntak_reporting as r
from ntak_contracts import NAMESPACE,validate
from ntak_protocol import ReportingBlocked
from test_ntak_reporting import configured,get,SoapMock,BASE,CONFIG,closing
from test_flutter_reservation_reception import client,login

PRIVATE='FICTIONAL_SENSITIVE_PROSE_ONLY'


def events(job,phase=None):
    with app.db() as con:
        return [(dict(row),app.decrypt_json(row['encrypted_event'])) for row in con.execute(
            'SELECT * FROM ntak_evidence_events WHERE job_id=? ORDER BY created_at,id',(job,)) if phase is None or row['phase']==phase]


def package(client,job):return client.post(BASE+f'/jobs/{job}/evidence-export',json={'reason':'Offline review'})


class ResendMock(SoapMock):
    def exchange(self,operation,xml,**scope):
        if operation=='verification':self.status='UJRA_KULDENDO' if len([x for x in self.calls if x[0]!='verification'])==1 else 'TELJESEN_SIKERES'
        else:self.receipt=str(uuid.uuid4())
        return super().exchange(operation,xml,**scope)


def resend_ready(client):
    login(client);assert client.put(BASE,json=CONFIG).status_code==200
    now=r.datetime.now(timezone.utc)
    with app.db() as con:job=r.enqueue(con,'org_casa_rosa','prop_flora',CONFIG,'daily_close','synthetic-EU03',{'napiFeltoltes':closing(str((now-timedelta(days=1)).date()))},now=now)
    mock=ResendMock()
    r.worker_once(app.db,transport=mock,now=now)
    r.worker_once(app.db,transport=mock,now=now+timedelta(minutes=6))
    assert get(job)['state']=='retry'
    return job,now,mock


def test_eu03_unchanged_content_both_receipts_and_polls_survive_restart(client):
    job,now,mock=resend_ready(client)
    original=get(job)
    app.init_db()
    r.worker_once(app.db,transport=mock,now=now+timedelta(minutes=12))
    r.worker_once(app.db,transport=mock,now=now+timedelta(minutes=18))
    assert get(job)['state']=='succeeded' and get(job)['message_id']==original['message_id']
    requests=events(job,'request');assert len(requests)==4
    submissions=[x for x in requests if x[1]['operation']=='daily_close']
    assert [x[1]['kind'] for x in submissions]==['original','explicit_protocol_resend']
    assert submissions[0][1]['wire_base64']==submissions[1][1]['wire_base64']
    responses=events(job,'response');assert len(responses)==4
    for _,value in requests:validate(value['operation'],base64.b64decode(value['wire_base64']))
    receipts=[x[1]['processing_id'] for x in events(job,'outcome') if x[1]['operation']=='daily_close']
    assert len(set(receipts))==2
    assert {x[1]['processing_id'] for x in requests if x[1]['operation']=='verification'}==set(receipts)
    with app.db() as con:
        token=con.execute('SELECT encrypted_snapshot FROM ntak_evidence_versions WHERE job_id=?',(job,)).fetchone()[0]
        assert original['payload_json'] not in token
        with pytest.raises(Exception):con.execute("UPDATE ntak_evidence_versions SET snapshot_hash='changed' WHERE job_id=?",(job,))
    exported=package(client,job)
    assert exported.status_code==200
    data=exported.json();assert data['official_acceptance_confirmed'] is False
    assert len(data['events'])==12 and data['versions'][0]['state']=='succeeded'
    assert all(x in exported.text for x in receipts)
    assert 'wire_base64' not in exported.text
    assert exported.headers['Cache-Control']=='no-store'
    assert exported.headers['X-Evidence-SHA256']==e.digest(exported.content)
    assert package(client,job).content==exported.content


def test_duplicate_and_concurrent_replay_requests_never_create_jobs(client):
    job,now,mock=resend_ready(client)
    request_id=str(uuid.uuid4());url=BASE+f'/jobs/{job}/replay'
    def post(_):return client.post(url,json={'request_id':request_id,'reason':PRIVATE})
    with ThreadPoolExecutor(max_workers=2) as pool:results=list(pool.map(post,[0,1]))
    assert [x.status_code for x in results]==[200,200]
    assert sorted(x.json()['duplicate'] for x in results)==[False,True]
    assert client.post(url,json={'request_id':str(uuid.uuid4()),'reason':'Different request'}).status_code==409
    with app.db() as con:
        assert con.execute('SELECT COUNT(*) FROM ntak_jobs WHERE id=?',(job,)).fetchone()[0]==1
        row=con.execute('SELECT * FROM ntak_replay_requests WHERE job_id=?',(job,)).fetchone()
        assert PRIVATE not in str(dict(row)) and app.decrypt_json(row['encrypted_reason'])['reason']==PRIVATE
    r.worker_once(app.db,transport=mock,now=now+timedelta(minutes=12))
    assert len([x for x in mock.calls if x[0]=='daily_close'])==2
    assert post(0).status_code==200 # idempotency survives state advancement


def test_timeout_and_crash_are_not_replayed(client):
    _,job=configured(client);now=r.datetime.now(timezone.utc)
    class Crash(SoapMock):
        def exchange(self,*a,**kw):raise KeyboardInterrupt()
    with pytest.raises(KeyboardInterrupt):r.worker_once(app.db,transport=Crash(),now=now)
    assert len(events(job,'request'))==1 and not events(job,'response')
    app.init_db();mock=SoapMock()
    r.worker_once(app.db,transport=mock,now=now+timedelta(minutes=3))
    assert get(job)['state']=='uncertain' and not mock.calls
    assert len(events(job,'interrupted'))==1
    denied=client.post(BASE+f'/jobs/{job}/replay',json={'request_id':str(uuid.uuid4()),'reason':'No receipt'})
    assert denied.status_code==409
    data=package(client,job).json()
    assert next(v for v in data['versions'] if v['job_id']==job)['state']=='uncertain' and not data['official_acceptance_confirmed']


@pytest.mark.parametrize('error,state',[(None,'accepted'),('Formatum','rejected'),('timeout','uncertain')])
def test_attempt_states_and_redaction(client,error,state):
    _,job=configured(client);r.worker_once(app.db,transport=SoapMock(error=error))
    assert get(job)['state']==state
    data=package(client,job).json();assert next(v for v in data['versions'] if v['job_id']==job)['state']==state
    assert data['transmission_enabled'] is False
    assert all('wire_base64' not in x for x in data['events'])


def test_raw_reply_encrypted_but_not_exported_and_history_immutable(client):
    rid,job=configured(client)
    class PrivateReply(SoapMock):
        def exchange(self,operation,xml,**scope):
            return (f'<foglalasEsemenyResponse xmlns="{NAMESPACE}"><hibaLista><hiba><mezoNeve>GLOBAL</mezoNeve>'
                f'<kuldottErtek>{PRIVATE}</kuldottErtek><hibaKulcs>Formatum</hibaKulcs><hibaUzenet>{PRIVATE}</hibaUzenet>'
                '</hiba></hibaLista><figyelmeztetesLista/></foglalasEsemenyResponse>').encode()
    r.worker_once(app.db,transport=PrivateReply())
    before=events(job)
    assert PRIVATE in base64.b64decode(events(job,'response')[0][1]['wire_base64']).decode()
    with app.db() as con:
        for row in con.execute('SELECT encrypted_event FROM ntak_evidence_events'):assert PRIVATE not in row[0]
    assert PRIVATE not in package(client,job).text
    assert client.patch('/api/reservations/'+rid,json={'total_huf':45000}).status_code==200
    assert events(job)==before
    data=package(client,job).json();assert len(data['versions'])>=2 and data['lineage']
    with app.db() as con:
        for row in con.execute('SELECT encrypted_event FROM ntak_evidence_events LIMIT 1'):
            with pytest.raises(Exception):con.execute("UPDATE ntak_evidence_events SET phase='overwritten'")


def test_scope_roles_csrf_and_audit(client):
    _,job=configured(client);url=BASE+f'/jobs/{job}/evidence-export'
    assert package(client,job).status_code==200
    assert client.post(url.replace('prop_flora','prop_luna'),json={'reason':'Review'}).status_code==404
    assert package(client,'missing').status_code==404
    login(client,'manager');assert package(client,job).status_code==403
    login(client,'cleaner');assert package(client,job).status_code==403
    login(client);client.headers.pop('X-Rosa-CSRF')
    assert package(client,job).status_code==403
    with app.db() as con:
        row=dict(con.execute('SELECT * FROM ntak_jobs WHERE id=?',(job,)).fetchone())
        with pytest.raises(ReportingBlocked):e.export(con,{**row,'organization_id':'foreign-tenant'})
        assert con.execute("SELECT COUNT(*) FROM ntak_evidence_access WHERE action='export'").fetchone()[0]==1


def test_legacy_capture_repeat_migration_and_payload_tamper_gate(client):
    _,job=configured(client)
    with app.db() as con:
        e.migrate(con,r.stamp());e.migrate(con,r.stamp())
        assert con.execute('SELECT COUNT(*) FROM schema_migrations WHERE version=3089').fetchone()[0]==1
        con.execute("UPDATE ntak_jobs SET payload_json='{}' WHERE id=?",(job,))
    mock=SoapMock();r.worker_once(app.db,transport=mock)
    assert get(job)['state']=='blocked' and get(job)['error_code']=='immutable_evidence_conflict' and not mock.calls
    assert package(client,job).status_code==200


def test_default_gates_and_blocked_export(client):
    _,job=configured(client);r.worker_once(app.db)
    assert get(job)['state']=='blocked' and not events(job)
    data=package(client,job).json()
    assert not data['events'] and not data['official_acceptance_confirmed']


def test_redaction_excludes_identity_free_text_and_secrets():
    value={'vendegek':[{'szuletesiEv':1980,'nev':PRIVATE}], 'private_key':PRIVATE,
           'indoklas':PRIVATE,'foglalasBruttoOsszege':3000,'lezartNap':'2026-10-31','raw_document_scan':PRIVATE}
    data=e.redact(value)
    assert PRIVATE not in json.dumps(data) and '1980' not in json.dumps(data)
    assert data['foglalasBruttoOsszege']==3000 and data['lezartNap']=='2026-10-31'


def test_protocol_modified_successor_has_explicit_lineage(client):
    login(client);assert client.put(BASE,json=CONFIG).status_code==200
    now=r.datetime.now(timezone.utc)
    with app.db() as con:
        job=r.enqueue(con,'org_casa_rosa','prop_flora',CONFIG,'daily_close','synthetic-processing-recovery',{'napiFeltoltes':closing('2026-10-31')},now=now)
    class ProcessingFailure(SoapMock):
        def exchange(self,operation,xml,**scope):
            if operation!='verification':return super().exchange(operation,xml,**scope)
            return (f'<ellenorzesResponse xmlns="{NAMESPACE}"><uzenetValaszok><feldolgozasAzonosito>{self.receipt}</feldolgozasAzonosito>'
                '<statusz>UJRA_KULDENDO</statusz><figyelmeztetesLista/><hibaLista><hiba><mezoNeve>GLOBAL</mezoNeve>'
                '<kuldottErtek/><hibaKulcs>FeldolgozasHiba</hibaKulcs><hibaUzenet>Fictional failure</hibaUzenet></hiba>'
                '</hibaLista></uzenetValaszok></ellenorzesResponse>').encode()
    mock=ProcessingFailure();r.worker_once(app.db,transport=mock,now=now)
    original=get(job)['payload_json']
    r.worker_once(app.db,transport=mock,now=now+timedelta(minutes=6))
    assert get(job)['state']=='replaced_by_correction' and get(job)['payload_json']==original
    data=package(client,job).json()
    assert any(edge['relation']=='protocol_correction' and edge['parent_id']==job for edge in data['lineage'])
    with app.db() as con:
        child=con.execute("SELECT * FROM ntak_jobs WHERE protocol_resends=2").fetchone()
        assert json.loads(child['payload_json'])['napiFeltoltes']['napiZarasBesorolas']['besorolas']=='MODOSITO'
        assert json.loads(original)['napiFeltoltes']['napiZarasBesorolas']['besorolas']=='UJ'


def test_source_daily_correction_versions_remain_correlated(client):
    login(client);assert client.put(BASE,json={**CONFIG,'reporting_start_date':'2026-10-31','reporting_start_evidence':'Fictional operator confirmation'}).status_code==200
    day='2026-10-31';url=BASE+'/daily-closing/'+day
    facts=closing(day)
    assert client.put(url,json={'values':facts,'evidence':'Fictional source ledger'}).status_code==200
    facts['szallashelyNemUzemel']=True
    facts['napiZarasBesorolas']={'besorolas':'MODOSITO','jegyzokonyvAzonosito':'fictional-correction','indoklas':'Fictional correction'}
    assert client.put(url,json={'values':facts,'evidence':'Fictional correction'}).status_code==200
    with app.db() as con:ids=[x[0] for x in con.execute("SELECT id FROM ntak_jobs WHERE operation='daily_close'")]
    assert len(ids)==2
    data=package(client,ids[-1]).json()
    assert len(data['versions'])==2 and any(x['relation']=='daily_version' for x in data['lineage'])


def test_late_receipt_preserved_without_overwriting_uncertain_outcome(client):
    _,job=configured(client);now=r.datetime.now(timezone.utc)
    class Late(SoapMock):
        def exchange(self,operation,xml,**scope):
            result=super().exchange(operation,xml,**scope)
            with app.db() as con:
                con.execute("UPDATE ntak_jobs SET state='uncertain',lease_token=NULL,lease_until=NULL WHERE id=?",(job,))
            return result
    mock=Late();r.worker_once(app.db,transport=mock,now=now)
    assert get(job)['state']=='uncertain' and get(job)['processing_id'] is None
    late=events(job,'late_outcome')[0][1]
    assert late['processing_id']==mock.receipt and late['lease_current'] is False
    assert mock.receipt in package(client,job).text


def test_concurrent_workers_send_original_only_once(client):
    _,job=configured(client);mock=SoapMock();now=r.datetime.now(timezone.utc)
    with ThreadPoolExecutor(max_workers=2) as pool:list(pool.map(lambda _:r.worker_once(app.db,transport=mock,now=now),[0,1]))
    assert len(mock.calls)==1 and len(events(job,'request'))==1


def test_manual_receipt_provenance_and_environment_denial(client):
    _,job=configured(client);r.worker_once(app.db,transport=SoapMock(error='timeout'))
    receipt=str(uuid.uuid4())
    assert client.post(BASE+f'/jobs/{job}/recovery',json={'action':'record_processing_id','reason':PRIVATE,'processing_id':receipt}).status_code==200
    data=package(client,job).json()
    assert any(a.get('kind')=='operator_recovery' and a.get('processing_id')==receipt for a in data['operator_actions'])
    assert PRIVATE not in json.dumps(data) and data['official_acceptance_confirmed'] is False
    with app.db() as con:
        row=dict(con.execute('SELECT * FROM ntak_jobs WHERE id=?',(job,)).fetchone())
        with pytest.raises(ReportingBlocked):e.export(con,{**row,'environment':'production'})
    client.headers.pop('X-Rosa-CSRF')
    assert client.post(BASE+f'/jobs/{job}/replay',json={'request_id':str(uuid.uuid4()),'reason':'Review'}).status_code==403


def test_evidence_cannot_be_deleted_or_include_unknown_payload_keys(client):
    _,job=configured(client)
    with app.db() as con:
        with pytest.raises(Exception):con.execute('DELETE FROM ntak_evidence_versions WHERE job_id=?',(job,))
    value=e.redact({PRIVATE:123,'lezartNap':'2026-10-31 '+PRIVATE,'vendegszam':2})
    assert PRIVATE not in json.dumps(value)
