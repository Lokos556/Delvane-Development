import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from datetime import date, timedelta

from fastapi.testclient import TestClient

from app import app, db, now_iso, _ensure_guest_records


def _future_reservation():
    with db() as con:
        room = con.execute("SELECT id FROM room_types WHERE property_id='prop_terra' LIMIT 1").fetchone()
        rid = "res_test_guest_checkin"
        con.execute("DELETE FROM work_tasks WHERE previous_reservation_id=? OR next_reservation_id=?", (rid,rid))
        con.execute("DELETE FROM reservation_notes WHERE reservation_id=?", (rid,))
        con.execute("DELETE FROM reservation_events WHERE reservation_id=?", (rid,))
        con.execute("DELETE FROM guest_checkin_tokens WHERE reservation_id=?", (rid,))
        con.execute("DELETE FROM guest_checkin_events WHERE reservation_id=?", (rid,))
        con.execute("DELETE FROM government_scan_events WHERE reservation_id=?", (rid,))
        con.execute("DELETE FROM sensitive_guest_data WHERE guest_record_id IN (SELECT id FROM guest_records WHERE reservation_id=?)", (rid,))
        con.execute("DELETE FROM guest_records WHERE reservation_id=?", (rid,))
        con.execute("DELETE FROM reservations WHERE id=?", (rid,))
        con.execute("""INSERT INTO reservations
            (id,organization_id,property_id,room_type_id,source,external_ref,guest_name,arrival_date,departure_date,
             guest_count,total_huf,payment_status,registration_status,arrival_time,special_requests,status,created_at,updated_at)
            VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",
            (rid,"org_casa_rosa","prop_terra",room["id"],"Direct",None,"Test Guest",
             str(date.today()+timedelta(days=10)),str(date.today()+timedelta(days=13)),1,None,
             "unpaid","incomplete",None,"[]","confirmed",now_iso(),now_iso()))
        _ensure_guest_records(con, con.execute("SELECT * FROM reservations WHERE id=?", (rid,)).fetchone())
    return rid


def test_guest_checkin_link_scan_and_confirmation():
    with TestClient(app) as client:
        login = client.post('/api/login', json={'email':'owner@demo.rosa','password':'rosa-owner'})
        assert login.status_code == 200
        csrf = login.json()['csrf_token']
        rid = _future_reservation()
        links = client.get(f'/api/reservations/{rid}/guest-checkin-links')
        assert links.status_code == 200
        token = links.json()['links'][0]['url'].rsplit('/', 1)[-1]
        page = client.get(f'/guest/checkin/{token}')
        assert page.status_code == 200
        assert 'lang="hu"' in page.text and 'guestLanguage' in page.text
        payload = {
            'full_name':'Test Guest', 'birth_name':'Test Guest', 'birth_place':'Eger',
            'date_of_birth':'2000-01-02', 'sex':'M', 'nationality':'HUN',
            'mother_birth_name':'Test Mother', 'document_type':'passport',
            'document_number':'AA123456', 'address':'Eger', 'scan_method':'camera_mrz',
            'guest_confirmed':True,
        }
        result = client.post(f'/api/public/checkin/{token}', json=payload)
        assert result.status_code == 200
        assert result.json()['status'] == 'pre_checkin_complete_needs_owner_review'
        status = client.get(f'/api/reservations/{rid}/guest-checkin-status').json()
        assert status['guests'][0]['completeness'] == 'complete'
        assert status['guests'][0]['verification_status'] == 'needs_review'
        assert status['registration_status'] == 'pending'
        with db() as con:
            assert con.execute("SELECT COUNT(*) c FROM government_outbox WHERE reservation_id=?", (rid,)).fetchone()['c'] == 0
        approved = client.post(f'/api/reservations/{rid}/guests/{status["guests"][0]["id"]}/verify', headers={'X-Rosa-CSRF':csrf}, json={'decision':'verify','verification_method':'in_person','review_note':'Checked on arrival'})
        assert approved.status_code == 200
        assert approved.json()['verification_status'] == 'verified'
        assert approved.json()['registration_status'] == 'complete'
        assert approved.json()['government_submission_queued'] is True
        with db() as con:
            event = con.execute("SELECT source,payload_json FROM government_scan_events WHERE reservation_id=? ORDER BY created_at DESC LIMIT 1", (rid,)).fetchone()
            assert event['source'] == 'guest_self_checkin'
            assert 'AA123456' not in event['payload_json']
            assert '.jpg' not in event['payload_json'].lower()
