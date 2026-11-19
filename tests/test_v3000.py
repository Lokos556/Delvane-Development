import json
from datetime import date, timedelta
import sqlite3
import sys
from pathlib import Path
from fastapi.testclient import TestClient

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import app as rosa


def fresh(tmp_path, monkeypatch):
    db_file=tmp_path/'v3000.db'
    monkeypatch.setattr(rosa,'DB_PATH',db_file)
    monkeypatch.setattr(rosa,'CHANNEX_API_KEY','shared-test-key')
    rosa.init_db(reset=True)
    client=TestClient(rosa.app)
    login=client.post('/api/login',json={'email':'owner@demo.rosa','password':'rosa-owner'})
    assert login.status_code==200,login.text
    client.headers.update({'X-Rosa-CSRF':login.json()['csrf_token']})
    with sqlite3.connect(db_file) as con:
        con.row_factory=sqlite3.Row
        prop=con.execute("SELECT id FROM properties WHERE name='Aqua'").fetchone()
        integration=con.execute("SELECT id FROM integrations WHERE property_id=? AND provider='Booking.com'",(prop['id'],)).fetchone()
        cfg={'adapter':'channex_channel_manager','provider_property_id':'bridge-casa','channex_room_type_id':'room-aqua','channex_rate_plan_id':'rate-aqua','commercial':True}
        con.execute("UPDATE integrations SET public_config_json=?,status='staging_ready' WHERE id=?",(json.dumps(cfg),integration['id']))
    return client,db_file,prop['id'],integration['id']


def test_rate_plan_creation_and_mapping(tmp_path,monkeypatch):
    client,db_file,property_id,integration_id=fresh(tmp_path,monkeypatch)
    r=client.post(f'/api/properties/{property_id}/rate-plans',json={'name':'Non-refundable','code':'nonref','base_rate_huf':38000})
    assert r.status_code==200,r.text
    rate_plan_id=r.json()['rate_plan_id']
    r=client.post(f'/api/integrations/{integration_id}/channex/rate-mappings',json={'rate_plan_id':rate_plan_id,'channex_room_type_id':'room-aqua','channex_rate_plan_id':'rate-nonref'})
    assert r.status_code==200,r.text
    mappings=client.get(f'/api/integrations/{integration_id}/channex/rate-mappings').json()
    assert any(x['channex_rate_plan_id']=='rate-nonref' for x in mappings)


def test_viza_id_scan_requires_owner_verification_before_queueing(tmp_path,monkeypatch):
    client,db_file,property_id,_=fresh(tmp_path,monkeypatch)
    # This test exercises completion of a single-guest stay. A seeded booking
    # may contain several guests; scanning one must not complete those stays.
    arrival=date.today()+timedelta(days=300)
    made=client.post('/api/reservations',json={'property_id':property_id,
        'guest_name':'Fictional scanner guest','arrival_date':str(arrival),
        'departure_date':str(arrival+timedelta(days=2)),'guest_count':1})
    assert made.status_code==200,made.text
    res={'id':made.json()['id']}
    with sqlite3.connect(db_file) as con:
        con.row_factory=sqlite3.Row
        rec=con.execute("SELECT id FROM guest_records WHERE reservation_id=?",(res['id'],)).fetchone()
        assert con.execute("SELECT COUNT(*) FROM guest_records WHERE reservation_id=?",(res['id'],)).fetchone()[0]==1
    r=client.post('/api/government/viza/id-scan',json={'reservation_id':res['id'],'guest_record_id':rec['id'],'full_name':'Test Guest','date_of_birth':'1990-01-02','nationality':'HUN','document_type':'ID','document_number':'TEST123','address':'Eger'})
    assert r.status_code==200,r.text
    assert r.json()['registration_status']=='pending'
    with sqlite3.connect(db_file) as con:
        assert con.execute("SELECT status,verified_by,verified_at FROM guest_identity_verifications WHERE guest_record_id=?", (rec['id'],)).fetchone() == ('needs_review', None, None)
        assert con.execute("SELECT COUNT(*) FROM government_outbox WHERE reservation_id=?", (res['id'],)).fetchone()[0] == 0
    verified = client.post(f"/api/reservations/{res['id']}/guests/{rec['id']}/verify",
                           json={'decision':'verify','verification_method':'in_person'})
    assert verified.status_code == 200, verified.text
    assert verified.json()['registration_status'] == 'complete'
    assert verified.json()['verification_status'] == 'verified'
    assert verified.json()['government_submission_queued'] is True
    with sqlite3.connect(db_file) as con:
        out=con.execute("SELECT system,event_type,status FROM government_outbox WHERE reservation_id=?", (res['id'],)).fetchall()
        identity=con.execute("SELECT status,verification_method,verified_by,verified_at FROM guest_identity_verifications WHERE guest_record_id=?", (rec['id'],)).fetchone()
    assert identity[0:2] == ('verified', 'in_person')
    assert identity[2] and identity[3]
    assert sorted((row[0], row[1]) for row in out) == [
        ('NTAK', 'guest.registration_verified'), ('VIZA', 'guest.registration_verified')]
    assert all(row[2] != 'sent' for row in out)


def test_government_status_reports_missing_official_transport(tmp_path,monkeypatch):
    client,db_file,property_id,_=fresh(tmp_path,monkeypatch)
    r=client.put('/api/government/connections',json={'property_id':property_id,'system':'NTAK','registration_id':'TEST-REG','environment':'test'})
    assert r.status_code==200,r.text
    status=client.get('/api/government/status').json()
    item=next(x for x in status['connections'] if x['property_id']==property_id and x['system']=='NTAK')
    assert item['transport_state']['state']=='awaiting_credentials'


def test_full_sync_includes_multiple_rate_plans_in_one_restrictions_call(tmp_path,monkeypatch):
    client,db_file,property_id,integration_id=fresh(tmp_path,monkeypatch)
    r=client.post(f'/api/properties/{property_id}/rate-plans',json={'name':'Non-refundable','code':'nonref','base_rate_huf':38000})
    rate_plan_id=r.json()['rate_plan_id']
    r=client.post(f'/api/integrations/{integration_id}/channex/rate-mappings',json={'rate_plan_id':rate_plan_id,'channex_room_type_id':'room-aqua','channex_rate_plan_id':'rate-nonref'})
    assert r.status_code==200,r.text
    with sqlite3.connect(db_file) as con:
        con.execute("UPDATE rate_plans SET base_rate_huf=42000 WHERE property_id=? AND code LIKE 'standard-%'",(property_id,))
        standard=con.execute("SELECT id FROM rate_plans WHERE property_id=? AND code LIKE 'standard-%' LIMIT 1",(property_id,)).fetchone()[0]
        con.execute("INSERT INTO channex_rate_mappings(id,organization_id,integration_id,rate_plan_id,channex_room_type_id,channex_rate_plan_id,active,created_at,updated_at) VALUES (?,?,?,?,?,?,1,?,?)",('standard-map','org_casa_rosa',integration_id,standard,'room-aqua','rate-aqua',rosa.now_iso(),rosa.now_iso()))
    calls=[]
    monkeypatch.setattr(rosa,'_channex_request',lambda path,method='GET',payload=None:(calls.append((path,payload)) or {'data':[{'id':f'task-{len(calls)}'}]}))
    response=client.post(f'/api/integrations/{integration_id}/channex/full-sync')
    assert response.status_code==200,response.text
    restrictions=next(payload for path,payload in calls if path=='/api/v1/restrictions')
    assert len(restrictions['values'])==1000
    assert {x['rate_plan_id'] for x in restrictions['values']}=={'rate-aqua','rate-nonref'}
