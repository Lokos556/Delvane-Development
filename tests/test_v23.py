import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from fastapi.testclient import TestClient
import app as rosa


def fresh(tmp_path, monkeypatch):
    db_file=tmp_path/'v23.db'
    monkeypatch.setattr(rosa,'DB_PATH',db_file)
    rosa.init_db(reset=True)
    return TestClient(rosa.app)


def login(c,email='owner@demo.rosa',password='rosa-owner'):
    r=c.post('/api/login',json={'email':email,'password':password})
    assert r.status_code==200,r.text
    c.headers.update({'X-Rosa-CSRF':r.json()['csrf_token']})
    return r


def get_integration(c,prop,provider):
    rows=c.get('/api/integrations').json()
    return next(x for x in rows if x['property_name']==prop and x['provider']==provider)


def test_sandbox_connections_and_summary(tmp_path,monkeypatch):
    c=fresh(tmp_path,monkeypatch); login(c)
    items=c.get('/api/integrations')
    assert items.status_code==200
    assert len(items.json())==6
    assert all(x['status']=='sandbox' for x in items.json())
    summary=c.get('/api/integration-sync/summary').json()
    assert summary['sandbox_connections']==6
    assert summary['pending_changes']>=3
    assert summary['errors']==0


def test_preview_and_apply_imports_new_and_changed_bookings(tmp_path,monkeypatch):
    c=fresh(tmp_path,monkeypatch); login(c)
    i=get_integration(c,'Terra','Booking.com')
    p=c.post(f"/api/integrations/{i['id']}/sync/preview")
    assert p.status_code==200,p.text
    assert p.json()['counts']['new']==1
    assert p.json()['counts']['changed']==1
    old_key=f"cleaning:prop_terra:{rosa.date.today()+rosa.timedelta(days=4)}"
    new_key=f"cleaning:prop_terra:{rosa.date.today()+rosa.timedelta(days=5)}"
    with rosa.db() as con:
        assert con.execute('SELECT 1 FROM work_tasks WHERE source_key=?',(old_key,)).fetchone()
    a=c.post(f"/api/integrations/{i['id']}/sync/apply")
    assert a.status_code==200,a.text
    assert a.json()['counts']['applied']==2
    with rosa.db() as con:
        assert not con.execute('SELECT 1 FROM work_tasks WHERE source_key=?',(old_key,)).fetchone()
        assert con.execute('SELECT 1 FROM work_tasks WHERE source_key=?',(new_key,)).fetchone()
    reservations=c.get('/api/reservations').json()
    imported=next(r for r in reservations if r['external_ref']=='BKG-SBX-1001')
    assert imported['guest_name']=='Marta Klein' and imported['source']=='Booking.com'
    daniel=next(r for r in reservations if r['external_ref']=='BKG-4411')
    assert daniel['departure_date']==str(rosa.date.today()+rosa.timedelta(days=5))
    actions=c.get('/api/rosa/actions').json()
    downstream=[x for x in actions if x.get('source_type')=='integration_sync']
    assert downstream and all(x['status']=='simulated' for x in downstream)
    assert any(x['action_type']=='request_registration' for x in downstream)


def test_duplicate_prevention_and_cancellation_roundtrip(tmp_path,monkeypatch):
    c=fresh(tmp_path,monkeypatch); login(c)
    i=get_integration(c,'Aqua','Booking.com')
    body={'external_ref':'DUP-100','guest_name':'Test Guest','arrival_date':str(rosa.date.today()+rosa.timedelta(days=40)),'departure_date':str(rosa.date.today()+rosa.timedelta(days=42)),'guest_count':2}
    assert c.post(f"/api/integrations/{i['id']}/sandbox/events",json=body).status_code==200
    assert c.post(f"/api/integrations/{i['id']}/sandbox/events",json=body).status_code==409
    assert c.post(f"/api/integrations/{i['id']}/sync/apply").status_code==200
    assert c.patch(f"/api/integrations/{i['id']}/sandbox/events/DUP-100",json={'status':'cancelled'}).status_code==200
    preview=c.post(f"/api/integrations/{i['id']}/sync/preview").json()
    row=next(x for x in preview['changes'] if x['external_ref']=='DUP-100')
    assert row['kind']=='cancelled'
    assert c.post(f"/api/integrations/{i['id']}/sync/apply").status_code==200
    res=next(x for x in c.get('/api/reservations').json() if x['external_ref']=='DUP-100')
    assert res['status']=='cancelled'


def test_feed_outage_recovery_and_sync_error_log(tmp_path,monkeypatch):
    c=fresh(tmp_path,monkeypatch); login(c)
    i=get_integration(c,'Flora','Szallas.hu')
    assert c.post(f"/api/integrations/{i['id']}/sandbox/outage").status_code==200
    assert c.post(f"/api/integrations/{i['id']}/sync/preview").status_code==503
    s=c.get('/api/integration-sync/summary').json()
    assert s['errors']>=1
    runs=c.get('/api/integration-sync/runs').json()
    assert any(r['status']=='error' for r in runs)
    assert c.post(f"/api/integrations/{i['id']}/sandbox/recover").status_code==200
    assert c.post(f"/api/integrations/{i['id']}/sync/preview").status_code==200


def test_ical_sample_parser_and_feed_loading(tmp_path,monkeypatch):
    c=fresh(tmp_path,monkeypatch); login(c)
    i=get_integration(c,'Flora','Szallas.hu')
    ics='''BEGIN:VCALENDAR\nVERSION:2.0\nBEGIN:VEVENT\nUID:ICAL-ABC-1\nDTSTART;VALUE=DATE:20261120\nDTEND;VALUE=DATE:20261123\nSUMMARY:Sample Guest\nEND:VEVENT\nEND:VCALENDAR'''
    r=c.post(f"/api/integrations/{i['id']}/sandbox/ical",json={'ical_text':ics,'replace_feed':True})
    assert r.status_code==200,r.text
    assert r.json()['count']==1
    feed=c.get(f"/api/integrations/{i['id']}/feed").json()['items']
    assert len(feed)==1 and feed[0]['external_ref']=='ICAL-ABC-1'
    preview=c.post(f"/api/integrations/{i['id']}/sync/preview").json()
    assert preview['counts']['new']==1


def test_integration_tenant_isolation(tmp_path,monkeypatch):
    c=fresh(tmp_path,monkeypatch); login(c)
    casa_id=get_integration(c,'Terra','Booking.com')['id']
    c.post('/api/logout')
    login(c,'owner@isolation.demo','rosa-isolation')
    assert c.get(f'/api/integrations/{casa_id}/feed').status_code==404
    assert c.post(f'/api/integrations/{casa_id}/sync/preview').status_code==404
