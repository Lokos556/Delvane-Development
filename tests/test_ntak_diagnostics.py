"""Synthetic schema-valid responses only, under repository DB/network guards."""
from datetime import timedelta, timezone
import json
import pytest
import app
import ntak_reporting as r
import ntak_diagnostics as d
from ntak_protocol import response
from ntak_contracts import NAMESPACE
from test_ntak_reporting import configured, get, SoapMock, BASE
from test_flutter_reservation_reception import client, login

SECRET = 'SYNTHETIC_PRIVATE_GUEST_VALUE'


def issue(field, code):
    return f'<hiba><mezoNeve>{field}</mezoNeve><kuldottErtek>{SECRET}</kuldottErtek><hibaKulcs>{code}</hibaKulcs><hibaUzenet>{SECRET}</hibaUzenet></hiba>'


class DiagnosticsMock(SoapMock):
    def exchange(self, operation, xml, **scope):
        if operation != 'verification':
            return super().exchange(operation,xml,**scope)
        return (f'<ellenorzesResponse xmlns="{NAMESPACE}"><uzenetValaszok>'
                f'<feldolgozasAzonosito>{self.receipt}</feldolgozasAzonosito>'
                '<statusz>VIZSGALANDO</statusz><figyelmeztetesLista>'
                + issue('foglalasEsemeny.foglalasBruttoOsszege', 'MasodlagosMax')
                + issue('foglalasEsemeny.vendegKuldoOrszaga', 'FoglalasOrszagKod')
                + issue(SECRET, SECRET)
                + '</figyelmeztetesLista><hibaLista/></uzenetValaszok></ellenorzesResponse>').encode()


def delivered(client):
    rid,job=configured(client)
    now=r.datetime.now(timezone.utc);mock=DiagnosticsMock()
    r.worker_once(app.db,transport=mock,now=now)
    r.worker_once(app.db,transport=mock,now=now+timedelta(minutes=6))
    return rid,job,mock


def test_multiple_warnings_persist_across_restart_without_sensitive_values(client):
    rid,job,mock=delivered(client)
    assert get(job)['state']=='review_required'
    app.init_db()
    data=client.get(BASE+f'/jobs/{job}/diagnostics').json()
    assert data['source']=={'kind':'reservation','reservation_id':rid}
    assert [x['phase'] for x in data['results']]==['receipt','verification']
    values=data['results'][1]['diagnostics']
    assert len(values)==3
    assert values[0]=={'severity':'warning','code':'MasodlagosMax','field':'foglalasEsemeny.foglalasBruttoOsszege','guidance':'range'}
    assert values[1]['code']=='FoglalasOrszagKod'
    assert values[2]['code']=='unknown_remote_diagnostic' and values[2]['field']=='GLOBAL'
    assert SECRET not in json.dumps(data)
    with app.db() as con:
        for table,columns in [('ntak_diagnostic_results','diagnostics_json'),('government_delivery_attempts','response_summary')]:
            assert all(SECRET not in str(x[0]) for x in con.execute(f'SELECT {columns} FROM {table}'))
    before=data['results']
    assert client.patch('/api/reservations/'+rid,json={'total_huf':44000}).status_code==200
    assert client.get(BASE+f'/jobs/{job}/diagnostics').json()['results']==before


def test_synchronous_errors_and_unknown_keys_are_redacted(client):
    _,job=configured(client)
    r.worker_once(app.db,transport=SoapMock(error=SECRET))
    data=client.get(BASE+f'/jobs/{job}/diagnostics').json()
    assert data['results'][0]['diagnostics'][0]['code']=='unknown_remote_diagnostic'
    assert get(job)['error_code']=='remote_validation_error'
    with app.db() as con:
        assert SECRET not in str(dict(con.execute('SELECT * FROM government_delivery_attempts WHERE outbox_id=?',(job,)).fetchone()))


def test_property_role_and_tenant_isolation(client):
    _,job=configured(client)
    path=BASE+f'/jobs/{job}/diagnostics'
    assert client.get(path.replace('prop_flora','prop_luna')).status_code==404
    assert client.get(path.replace(job,'missing')).status_code==404
    login(client,'cleaner');assert client.get(path).status_code==403
    login(client,'manager');assert client.get(path).status_code==200
    with app.db() as con:
        assert d.history(con,'another-tenant','prop_flora',job)==[]
    client.cookies.clear();assert client.get(path).status_code==401


def test_migration_repeatability_and_existing_gates(client):
    _,job=configured(client)
    with app.db() as con:
        d.migrate(con,r.stamp());d.migrate(con,r.stamp())
        assert con.execute('SELECT COUNT(*) n FROM schema_migrations WHERE version=3088').fetchone()['n']==1
    r.worker_once(app.db)
    assert get(job)['error_code']=='signature_profile_unresolved'
    assert client.get(BASE).json()['transmission_enabled'] is False


@pytest.mark.parametrize('field,expected',[
    ('napiFeltoltes.lakoegysegEjszakak[0].vendegek[0].szuletesiEv','napiFeltoltes.lakoegysegEjszakak[0].vendegek[0].szuletesiEv'),
    ('GLOBAL','GLOBAL'), ('napiFeltoltes.'+SECRET,'GLOBAL'),
    ('napiFeltoltes.vendegek[9999999]','GLOBAL'), ('<script>','GLOBAL'),
])
def test_only_schema_vocabulary_can_be_exposed(field,expected):
    assert d.safe_field('daily_close',field)==expected


def test_response_correlation_and_multiple_error_lists():
    from ntak_protocol import ReportingBlocked
    xml=(f'<ellenorzesResponse xmlns="{NAMESPACE}"><uzenetValaszok>'
         '<feldolgozasAzonosito>00000000-0000-0000-0000-000000000001</feldolgozasAzonosito>'
         '<statusz>TELJESEN_HIBAS</statusz><figyelmeztetesLista>'+issue('GLOBAL','MagasEletkor')+
         '</figyelmeztetesLista><hibaLista>'+issue('GLOBAL','Formatum')+
         '</hibaLista></uzenetValaszok></ellenorzesResponse>').encode()
    with pytest.raises(ReportingBlocked):response('verification',xml,'00000000-0000-0000-0000-000000000002')
    result=response('verification',xml,'00000000-0000-0000-0000-000000000001')
    assert [v['severity'] for v in result['diagnostics']]==['error','warning']
    assert SECRET not in str(result)


def test_non_schema_poll_error_keeps_original_outcome_unresolved(client):
    _,job=configured(client)
    class PollRejected(SoapMock):
        def exchange(self,operation,xml,**scope):
            if operation!='verification':return super().exchange(operation,xml,**scope)
            return (f'<ellenorzesResponse xmlns="{NAMESPACE}"><hibaLista>'+
                    issue('GLOBAL','Formatum')+'</hibaLista><figyelmeztetesLista/></ellenorzesResponse>').encode()
    now=r.datetime.now(timezone.utc);mock=PollRejected()
    r.worker_once(app.db,transport=mock,now=now)
    receipt=get(job)['processing_id']
    r.worker_once(app.db,transport=mock,now=now+timedelta(minutes=6))
    assert get(job)['state']=='accepted' and get(job)['processing_id']==receipt
    assert get(job)['error_code']=='outcome_unknown'
    result=client.get(BASE+f'/jobs/{job}/diagnostics').json()['results'][-1]
    assert result['phase']=='verification' and result['diagnostics']==[]


def test_daily_closing_source_link_uses_immutable_reported_date(client):
    from test_ntak_reporting import closing
    login(client)
    from test_ntak_reporting import CONFIG
    assert client.put(BASE,json=CONFIG).status_code==200
    day='2026-10-30'
    payload={'napiFeltoltes':closing(day)}
    with app.db() as con:
        job=r.enqueue(con,'org_casa_rosa','prop_flora',CONFIG,'daily_close','synthetic-day-diagnostics',payload)
    data=client.get(BASE+f'/jobs/{job}/diagnostics').json()
    assert data['source']=={'kind':'business_day','business_date':day}


def test_official_error_catalog_coverage():
    from pathlib import Path
    fixture=json.loads((Path(__file__).parent/'fixtures/ntak_diagnostic_keys.json').read_text(encoding='utf8'))
    assert len(fixture['keys'])==66
    assert all(row['code'] in d.CATALOG for row in fixture['keys'])


def test_top_level_poll_error_list_is_not_permitted_by_official_schema():
    xml=(f'<ellenorzesResponse xmlns="{NAMESPACE}"><hibaLista/><figyelmeztetesLista/></ellenorzesResponse>').encode()
    from ntak_contracts import ContractError
    with pytest.raises(ContractError):
        response('verification',xml,'00000000-0000-0000-0000-000000000001')


def test_poll_soap_fault_is_not_report_rejection(client):
    _,job=configured(client)
    class PollFault(SoapMock):
        def exchange(self,operation,xml,**scope):
            if operation!='verification':return super().exchange(operation,xml,**scope)
            return (f'<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body>'
                    f'<s:Fault><faultcode>s:Server</faultcode><faultstring>{SECRET}</faultstring>'
                    '</s:Fault></s:Body></s:Envelope>').encode()
    now=r.datetime.now(timezone.utc);mock=PollFault()
    r.worker_once(app.db,transport=mock,now=now)
    receipt=get(job)['processing_id']
    r.worker_once(app.db,transport=mock,now=now+timedelta(minutes=6))
    assert get(job)['state']=='review_required' and get(job)['error_code']=='soap_fault'
    assert get(job)['processing_id']==receipt
    assert SECRET not in client.get(BASE+f'/jobs/{job}/diagnostics').text
