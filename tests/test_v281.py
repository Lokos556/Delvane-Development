import sys
from pathlib import Path
from fastapi.testclient import TestClient

sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import app as rosa


def fresh(tmp_path,monkeypatch):
    monkeypatch.setattr(rosa,'DB_PATH',tmp_path/'v281.db')
    rosa.init_db(reset=True)
    c=TestClient(rosa.app)
    r=c.post('/api/login',json={'email':'owner@demo.rosa','password':'rosa-owner'})
    assert r.status_code==200,r.text
    c.headers.update({'X-Rosa-CSRF':r.json()['csrf_token']})
    return c


def test_v281_runtime_and_today_registration_is_contextual(tmp_path,monkeypatch):
    c=fresh(tmp_path,monkeypatch)
    runtime=c.get('/api/system/runtime').json()
    assert runtime['version']=='2.10.27'
    assert runtime['schema_version']==3056
    today=c.get('/api/operations/today-command').json()
    assert 'registration_risks' in today
    # The contextual surface must only carry incomplete, near-term registration work.
    for item in today['registration_risks']:
        assert item['registration_status']!='complete'
        assert item['arrival_date']>=today['date']


def test_reservation_detail_contains_guest_memory_context(tmp_path,monkeypatch):
    c=fresh(tmp_path,monkeypatch)
    d=c.get('/api/reservations/res_terra_next/detail')
    assert d.status_code==200,d.text
    body=d.json()
    assert 'guest_profile' in body
    gp=body['guest_profile']
    assert gp and gp['id']
    assert gp['stay_count']>=1
    assert isinstance(gp['previous_stays'],list)
    assert isinstance(gp['preferences'],list)


def test_prepare_registration_reminder_creates_reception_draft_only(tmp_path,monkeypatch):
    c=fresh(tmp_path,monkeypatch)
    center=c.get('/api/registration').json()
    target=next(x for x in center if x['registration_status']!='complete')
    out=c.post(f"/api/reservations/{target['id']}/registration-reminder")
    assert out.status_code==200,out.text
    data=out.json()
    assert data['external_send'] is False
    items=c.get('/api/communications/outbox').json()
    item=next(x for x in items if x['id']==data['id'])
    assert item['reservation_id']==target['id']
    assert item['status'] in {'draft','preview','awaiting_approval','ready'}
    assert item['subject']=='Registration reminder'
    # Repeated preparation does not create duplicates.
    second=c.post(f"/api/reservations/{target['id']}/registration-reminder").json()
    assert second['created'] is False
    assert second['id']==data['id']


def test_complete_registration_does_not_prepare_reminder(tmp_path,monkeypatch):
    c=fresh(tmp_path,monkeypatch)
    center=c.get('/api/registration').json()
    complete=next(x for x in center if x['registration_status']=='complete')
    r=c.post(f"/api/reservations/{complete['id']}/registration-reminder")
    assert r.status_code==409


def test_reception_includes_guest_context_for_linked_stay(tmp_path,monkeypatch):
    c=fresh(tmp_path,monkeypatch)
    items=c.get('/api/inbox').json()
    linked=next(x for x in items if x.get('reservation_id'))
    assert 'guest_context' in linked
    if linked['guest_context']:
        assert linked['guest_context']['stays']>=1
        assert isinstance(linked['guest_context']['preferences'],list)


def test_search_guest_result_scales_by_history_not_directory(tmp_path,monkeypatch):
    c=fresh(tmp_path,monkeypatch)
    r=c.get('/api/search?q=Daniel')
    assert r.status_code==200
    guests=[x for x in r.json()['results'] if x['type']=='guest']
    assert guests
    assert 'stay' in guests[0]['detail']


def test_frontend_removes_directory_destinations_but_keeps_contextual_access():
    root=Path(__file__).resolve().parents[1]
    js=(root/'static'/'app.js').read_text(encoding='utf-8')
    css=(root/'static'/'styles.css').read_text(encoding='utf-8')
    # Latest settings override has only team under account, not guest/registration directories.
    start=js.index('// ROSA V2.8.1')
    block=js[start:]
    assert "[['team',v223('teamAccess'),'♙']]" in block
    assert "['guests',v223('manageGuests')" not in block
    assert "['registration',v223('registrationCenter')" not in block
    assert 'v281-registration-strip' in block
    assert 'data-guest-history' in block
    assert 'registration-reminder' in block
    assert 'data-v281-guest' in block
    assert 'v281-registration-strip' in css
    assert 'v281-reception-guest' in css
