import json
import sqlite3
import sys
from datetime import date, timedelta
from pathlib import Path

from fastapi import HTTPException
from fastapi.testclient import TestClient

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import app as rosa


def fresh(tmp_path, monkeypatch):
    db_file=tmp_path/'v293.db'
    monkeypatch.setattr(rosa,'DB_PATH',db_file)
    monkeypatch.setattr(rosa,'CHANNEX_API_KEY','shared-test-key')
    rosa.init_db(reset=True)
    client=TestClient(rosa.app)
    login=client.post('/api/login',json={'email':'owner@demo.rosa','password':'rosa-owner'})
    assert login.status_code==200,login.text
    client.headers.update({'X-Rosa-CSRF':login.json()['csrf_token']})
    return client,db_file


def map_property(property_name, room_type_id, db_file, secret=False):
    with sqlite3.connect(db_file) as con:
        con.row_factory=sqlite3.Row
        row=con.execute("""SELECT i.id,i.organization_id FROM integrations i JOIN properties p ON p.id=i.property_id
                           WHERE p.name=? AND i.provider='Booking.com'""",(property_name,)).fetchone()
        cfg={'adapter':'channex_channel_manager','provider_property_id':'bridge-casa','channex_room_type_id':room_type_id,'channex_rate_plan_id':f'rate-{room_type_id}','commercial':True,'customer_handles_api_keys':False,'connector_core_version':'2.9.3'}
        con.execute("UPDATE integrations SET public_config_json=?,status='connected',connection_type='Channex staging API' WHERE id=?",(json.dumps(cfg),row['id']))
        if secret:
            con.execute("INSERT INTO integration_credentials(integration_id,organization_id,encrypted_payload,updated_at) VALUES (?,?,?,?)",(row['id'],row['organization_id'],rosa.encrypt_json({'webhook_secret':'hook-secret'}),rosa.now_iso()))
        return row['id']


def revision(revision_id, external_ref, room_type_id, *, status='new', guest='Anna', surname='Nagy', arrival=None, departure=None, amount='123000'):
    arrival=arrival or str(date.today()+timedelta(days=5))
    departure=departure or str(date.today()+timedelta(days=8))
    return {'type':'booking_revision','id':revision_id,'attributes':{
        'id':revision_id,'property_id':'bridge-casa','booking_id':f'booking-{external_ref}','unique_id':f'BDC-{external_ref}',
        'ota_reservation_code':external_ref,'ota_name':'Booking.com','status':status,
        'arrival_date':arrival,'departure_date':departure,'arrival_hour':'18:30','amount':amount,'currency':'HUF','notes':'Quiet room',
        'customer':{'name':guest,'surname':surname,'mail':'guest@example.com','phone':'+3612345','language':'hu'},
        'occupancy':{'adults':2,'children':1,'infants':0},
        'rooms':[{'room_type_id':room_type_id,'rate_plan_id':f'rate-{room_type_id}','checkin_date':arrival,'checkout_date':departure,'occupancy':{'adults':2,'children':1,'infants':0}}],
    }}


def test_receive_routes_shared_channex_property_by_room_and_acks_after_commit(tmp_path,monkeypatch):
    client,db_file=fresh(tmp_path,monkeypatch)
    aqua=map_property('Aqua','room-aqua',db_file)
    map_property('Flora','room-flora',db_file)
    feed=[revision('rev-aqua','LIVE-AQUA','room-aqua'),revision('rev-flora','LIVE-FLORA','room-flora',guest='Bela',surname='Kiss')]
    acked=[]
    def fake_request(path,method='GET',payload=None):
        if '/booking_revisions/feed?' in path:
            return {'data':feed}
        if path.endswith('/ack'):
            ref='LIVE-AQUA' if 'rev-aqua' in path else 'LIVE-FLORA'
            with sqlite3.connect(db_file) as check:
                assert check.execute("SELECT 1 FROM reservations WHERE external_ref=?",(ref,)).fetchone(), 'ack happened before durable save'
            acked.append(path)
            return {'meta':{'message':'Success'}}
        raise AssertionError((path,method,payload))
    monkeypatch.setattr(rosa,'_channex_request',fake_request)
    response=client.post(f'/api/integrations/{aqua}/channex/receive')
    assert response.status_code==200,response.text
    assert response.json()['counts']['new']==2
    assert response.json()['counts']['acknowledged']==2
    assert len(acked)==2
    with sqlite3.connect(db_file) as con:
        assert con.execute("SELECT property_id FROM reservations WHERE external_ref='LIVE-AQUA'").fetchone()[0]=='prop_aqua'
        assert con.execute("SELECT property_id FROM reservations WHERE external_ref='LIVE-FLORA'").fetchone()[0]=='prop_flora'
        assert con.execute("SELECT total_huf FROM reservations WHERE external_ref='LIVE-AQUA'").fetchone()[0]==123000
        assert con.execute("SELECT COUNT(*) FROM integration_inbox WHERE ack_status='acknowledged'").fetchone()[0]==2
        assert con.execute("SELECT email FROM guests WHERE full_name='Anna Nagy'").fetchone()[0]=='guest@example.com'
        assert con.execute("SELECT COUNT(*) FROM government_outbox WHERE reservation_id IN (SELECT id FROM reservations WHERE external_ref LIKE 'LIVE-%')").fetchone()[0]==4


def test_modification_preserves_manual_fields_and_cancellation_updates_cleaning(tmp_path,monkeypatch):
    client,db_file=fresh(tmp_path,monkeypatch)
    aqua=map_property('Aqua','room-aqua',db_file)
    current={'item':revision('rev-new','LIVE-CHANGE','room-aqua')}
    def fake_request(path,method='GET',payload=None):
        if '/booking_revisions/feed?' in path: return {'data':[current['item']]}
        if path.endswith('/ack'): return {'meta':{'message':'Success'}}
        raise AssertionError(path)
    monkeypatch.setattr(rosa,'_channex_request',fake_request)
    assert client.post(f'/api/integrations/{aqua}/channex/receive').json()['counts']['new']==1
    with sqlite3.connect(db_file) as con:
        con.execute("UPDATE reservations SET arrival_time='22:15',special_requests='[\"Manual note\"]',registration_status='complete' WHERE external_ref='LIVE-CHANGE'")
    new_departure=str(date.today()+timedelta(days=9))
    current['item']=revision('rev-mod','LIVE-CHANGE','room-aqua',status='modified',guest='Anna Maria',departure=new_departure,amount='60000')
    changed=client.post(f'/api/integrations/{aqua}/channex/receive').json()
    assert changed['counts']['changed']==1
    with sqlite3.connect(db_file) as con:
        row=con.execute("SELECT guest_name,departure_date,total_huf,arrival_time,special_requests,registration_status FROM reservations WHERE external_ref='LIVE-CHANGE'").fetchone()
        assert row==('Anna Maria Nagy',new_departure,60000,'22:15','["Manual note"]','complete')
    with rosa.db() as con:
        con.execute("UPDATE reservations SET total_huf=960000 WHERE external_ref='LIVE-CHANGE'")
        con.execute("DELETE FROM schema_migrations WHERE version=2940")
        rosa.ensure_v294_schema(con)
        assert con.execute("SELECT total_huf FROM reservations WHERE external_ref='LIVE-CHANGE'").fetchone()[0]==60000
    current['item']=revision('rev-cancel','LIVE-CHANGE','room-aqua',status='cancelled',guest='Anna Maria',departure=new_departure)
    cancelled=client.post(f'/api/integrations/{aqua}/channex/receive').json()
    assert cancelled['counts']['cancelled']==1
    with sqlite3.connect(db_file) as con:
        assert con.execute("SELECT status FROM reservations WHERE external_ref='LIVE-CHANGE'").fetchone()[0]=='cancelled'
        assert not con.execute("SELECT 1 FROM work_tasks WHERE previous_reservation_id=(SELECT id FROM reservations WHERE external_ref='LIVE-CHANGE')").fetchone()


def test_failed_ack_keeps_booking_and_redelivery_is_idempotent(tmp_path,monkeypatch):
    client,db_file=fresh(tmp_path,monkeypatch)
    aqua=map_property('Aqua','room-aqua',db_file)
    item=revision('rev-retry','LIVE-RETRY','room-aqua')
    state={'fail':True}
    def fake_request(path,method='GET',payload=None):
        if '/booking_revisions/feed?' in path: return {'data':[item]}
        if path.endswith('/ack'):
            if state['fail']: raise HTTPException(503,'temporary ack outage')
            return {'meta':{'message':'Success'}}
        raise AssertionError(path)
    monkeypatch.setattr(rosa,'_channex_request',fake_request)
    first=client.post(f'/api/integrations/{aqua}/channex/receive').json()
    assert first['counts']['new']==1 and first['counts']['ack_failed']==1 and not first['ok']
    with sqlite3.connect(db_file) as con:
        assert con.execute("SELECT COUNT(*) FROM reservations WHERE external_ref='LIVE-RETRY'").fetchone()[0]==1
        assert con.execute("SELECT ack_status FROM integration_inbox WHERE provider_event_id='rev-retry'").fetchone()[0]=='failed'
    state['fail']=False
    second=client.post(f'/api/integrations/{aqua}/channex/receive').json()
    assert second['counts']['unchanged']==1 and second['counts']['acknowledged']==1
    with sqlite3.connect(db_file) as con:
        assert con.execute("SELECT COUNT(*) FROM reservations WHERE external_ref='LIVE-RETRY'").fetchone()[0]==1
        assert con.execute("SELECT ack_status FROM integration_inbox WHERE provider_event_id='rev-retry'").fetchone()[0]=='acknowledged'


def test_channex_notification_pulls_full_revision_then_imports(tmp_path,monkeypatch):
    client,db_file=fresh(tmp_path,monkeypatch)
    aqua=map_property('Aqua','room-aqua',db_file,secret=True)
    item=revision('rev-hook','LIVE-HOOK','room-aqua')
    calls=[]
    def fake_request(path,method='GET',payload=None):
        calls.append((path,method))
        if path=='/api/v1/booking_revisions/rev-hook': return {'data':item}
        if path=='/api/v1/booking_revisions/rev-hook/ack' and method=='POST': return {'meta':{'message':'Success'}}
        raise AssertionError((path,method))
    monkeypatch.setattr(rosa,'_channex_request',fake_request)
    notification={'event':'booking','payload':{'revision_id':'rev-hook','property_id':'bridge-casa'},'property_id':'bridge-casa'}
    response=client.post(f'/api/channel-bridge/webhooks/{aqua}',json=notification,headers={'X-Channex-Webhook-Secret':'hook-secret'})
    assert response.status_code==200,response.text
    assert response.json()['acknowledged'] is True and response.json()['property_name']=='Aqua'
    assert calls==[('/api/v1/booking_revisions/rev-hook','GET'),('/api/v1/booking_revisions/rev-hook/ack','POST'),('/api/v1/availability','POST')]
    with sqlite3.connect(db_file) as con:
        assert con.execute("SELECT 1 FROM reservations WHERE external_ref='LIVE-HOOK' AND property_id='prop_aqua'").fetchone()


def test_ambiguous_multi_apartment_revision_is_not_acked(tmp_path,monkeypatch):
    client,db_file=fresh(tmp_path,monkeypatch)
    aqua=map_property('Aqua','room-aqua',db_file)
    map_property('Flora','room-flora',db_file)
    item=revision('rev-multi','LIVE-MULTI','room-aqua')
    item['attributes']['rooms'].append({'room_type_id':'room-flora','rate_plan_id':'rate-room-flora','checkin_date':item['attributes']['arrival_date'],'checkout_date':item['attributes']['departure_date'],'occupancy':{'adults':1,'children':0,'infants':0}})
    acked=[]
    def fake_request(path,method='GET',payload=None):
        if '/booking_revisions/feed?' in path: return {'data':[item]}
        if path.endswith('/ack'): acked.append(path); return {}
        if path=='/api/v1/availability': return {'data':[{'id':'availability-task'}]}
        raise AssertionError(path)
    monkeypatch.setattr(rosa,'_channex_request',fake_request)
    result=client.post(f'/api/integrations/{aqua}/channex/receive').json()
    assert result['ok'] is False and result['errors'] and 'more than one Rosa apartment' in result['errors'][0]['error']
    assert acked==[]
    with sqlite3.connect(db_file) as con:
        assert not con.execute("SELECT 1 FROM reservations WHERE external_ref='LIVE-MULTI'").fetchone()
