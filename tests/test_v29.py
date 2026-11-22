import json
import sqlite3
import sys
from pathlib import Path

from fastapi.testclient import TestClient

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import app as rosa


def fresh(tmp_path, monkeypatch):
    db_file=tmp_path/'v29.db'
    monkeypatch.setattr(rosa,'DB_PATH',db_file)
    rosa.init_db(reset=True)
    client=TestClient(rosa.app)
    login=client.post('/api/login',json={'email':'owner@demo.rosa','password':'rosa-owner'})
    assert login.status_code==200,login.text
    client.headers.update({'X-Rosa-CSRF':login.json()['csrf_token']})
    return client,db_file


def booking_integration(client):
    return next(x for x in client.get('/api/integrations').json() if x['provider']=='Booking.com' and x['property_name']=='Aqua')


def test_v29_schema_and_existing_data_survive_init(tmp_path,monkeypatch):
    client,db_file=fresh(tmp_path,monkeypatch)
    before=client.get('/api/reservations').json()
    with rosa.db() as con:
        con.execute("UPDATE organizations SET name='Casa Rosa preserved' WHERE id='org_casa_rosa'")
    rosa.init_db(reset=False)
    with sqlite3.connect(db_file) as con:
        assert con.execute("SELECT name FROM organizations WHERE id='org_casa_rosa'").fetchone()[0]=='Casa Rosa preserved'
        assert con.execute("SELECT name FROM schema_migrations WHERE version=2900").fetchone()[0]=='persistent_data_and_provider_connector_core'
        assert con.execute("SELECT COUNT(*) FROM reservations").fetchone()[0]>=len(before)


def test_connector_config_encrypts_secrets_and_never_returns_them(tmp_path,monkeypatch):
    client,db_file=fresh(tmp_path,monkeypatch); integration=booking_integration(client)
    body={'adapter':'booking_connectivity','provider_property_id':'1234567','poll_interval_seconds':20,'credentials':{'client_id':'rosa-client','client_secret':'TOP-SECRET','machine_account_id':'machine-1'}}
    response=client.patch(f"/api/integrations/{integration['id']}/technical-config",json=body)
    assert response.status_code==200,response.text
    status=client.get(f"/api/integrations/{integration['id']}/technical-status").json()
    assert status['transport_ready'] is True
    assert status['credential_fields']==['client_id','client_secret','machine_account_id']
    assert 'TOP-SECRET' not in json.dumps(status)
    with sqlite3.connect(db_file) as con:
        encrypted=con.execute('SELECT encrypted_payload FROM integration_credentials WHERE integration_id=?',(integration['id'],)).fetchone()[0]
    assert 'TOP-SECRET' not in encrypted


def test_provider_event_is_idempotently_staged_then_previewed(tmp_path,monkeypatch):
    client,_=fresh(tmp_path,monkeypatch); integration=booking_integration(client)
    event={'provider_event_id':'evt-100','event_type':'reservation.created','external_ref':'BKG-LIVE-100','guest_name':'Provider Guest','arrival_date':'2027-02-10','departure_date':'2027-02-13','guest_count':2,'status':'active','payload':{'source':'test-provider'}}
    first=client.post(f"/api/integrations/{integration['id']}/provider-events",json=event)
    second=client.post(f"/api/integrations/{integration['id']}/provider-events",json=event)
    assert first.status_code==200 and first.json()['duplicate'] is False
    assert second.status_code==200 and second.json()['duplicate'] is True and second.json()['same_payload'] is True
    feed=client.get(f"/api/integrations/{integration['id']}/feed").json()['items']
    assert len([x for x in feed if x['external_ref']=='BKG-LIVE-100'])==1
    preview=client.post(f"/api/integrations/{integration['id']}/sync/preview").json()
    assert next(x for x in preview['changes'] if x['external_ref']=='BKG-LIVE-100')['kind']=='new'


def test_booking_xml_normalizes_into_existing_pipeline(tmp_path,monkeypatch):
    client,_=fresh(tmp_path,monkeypatch); integration=booking_integration(client)
    xml='''<reservations><reservation><id>778899</id><customer><first_name>Anna</first_name><last_name>Nagy</last_name></customer><room><arrival_date>2027-03-04</arrival_date><departure_date>2027-03-07</departure_date><guest_counts><guest_count count="2" type="adult"/></guest_counts></room></reservation></reservations>'''
    response=client.post(f"/api/integrations/{integration['id']}/booking/xml",json={'xml_text':xml,'message_type':'reservation.created'})
    assert response.status_code==200,response.text
    assert response.json()=={'ok':True,'count':1,'duplicates':0,'events':[{'external_ref':'778899','status':'active'}]}
    preview=client.post(f"/api/integrations/{integration['id']}/sync/preview").json()
    item=next(x for x in preview['changes'] if x['external_ref']=='778899')
    assert item['guest_name']=='Anna Nagy' and item['guest_count']==2 and item['kind']=='new'


def test_legacy_database_is_copied_only_when_stable_database_missing(tmp_path,monkeypatch):
    legacy=tmp_path/'old'/'rosa.db'; legacy.parent.mkdir(); legacy.write_bytes(b'legacy-data')
    stable=tmp_path/'stable'/'rosa.db'
    monkeypatch.setattr(rosa,'LEGACY_DB_PATH',legacy)
    monkeypatch.setattr(rosa,'DB_PATH',stable)
    assert rosa.migrate_legacy_database()==legacy
    assert stable.read_bytes()==b'legacy-data'
    legacy.write_bytes(b'changed')
    assert rosa.migrate_legacy_database() is None
    assert stable.read_bytes()==b'legacy-data'


def test_commercial_owner_connects_booking_without_api_keys(tmp_path,monkeypatch):
    client,db_file=fresh(tmp_path,monkeypatch); integration=booking_integration(client)
    response=client.post(f"/api/integrations/{integration['id']}/commercial-connect",json={'booking_hotel_id':'1234567','bridge_property_id':'channex-prop-aqua'})
    assert response.status_code==200,response.text
    assert response.json()['state']=='connected'
    assert response.json()['booking_extranet_url']=='https://account.booking.com/'
    assert 'api_key' not in json.dumps(response.json()).lower()
    status=client.get(f"/api/integrations/{integration['id']}/technical-status").json()
    assert status['adapter']=='channex_channel_manager'
    with sqlite3.connect(db_file) as con:
        token=con.execute('SELECT encrypted_payload FROM integration_credentials WHERE integration_id=?',(integration['id'],)).fetchone()[0]
    assert rosa.decrypt_json(token)['webhook_secret']


def test_channex_staging_link_creates_inventory_once_and_never_exposes_key(tmp_path,monkeypatch):
    client,db_file=fresh(tmp_path,monkeypatch); integration=booking_integration(client)
    monkeypatch.setattr(rosa,'CHANNEX_API_KEY','hidden-developer-key')
    state={'rooms':[],'rates':[],'posts':[]}
    def fake_request(path,method='GET',payload=None):
        if path.startswith('/api/v1/properties'):
            return {'data':[{'id':'channex-casa','attributes':{'title':'Casa Rosa - Staging'}}]}
        if path.startswith('/api/v1/room_types?'):
            return {'data':state['rooms']}
        if path.startswith('/api/v1/rate_plans/options?'):
            return {'data':state['rates']}
        if path=='/api/v1/room_types' and method=='POST':
            state['posts'].append(payload)
            room={'id':'room-aqua','attributes':{'title':payload['room_type']['title']}}
            state['rooms'].append(room)
            return {'data':room}
        if path=='/api/v1/rate_plans' and method=='POST':
            state['posts'].append(payload)
            rate={'id':'rate-aqua','attributes':{'title':'Standard Rate','room_type_id':'room-aqua'}}
            state['rates'].append(rate)
            return {'data':rate}
        raise AssertionError((path,method,payload))
    monkeypatch.setattr(rosa,'_channex_request',fake_request)
    status=client.get('/api/channex/status')
    assert status.status_code==200 and status.json()['properties'][0]['id']=='channex-casa'
    assert 'hidden-developer-key' not in json.dumps(status.json())
    first=client.post(f"/api/integrations/{integration['id']}/channex/link",json={'channex_property_id':'channex-casa','create_inventory':True})
    second=client.post(f"/api/integrations/{integration['id']}/channex/link",json={'channex_property_id':'channex-casa','create_inventory':True})
    assert first.status_code==200,first.text
    assert first.json()['created']==['room_type','rate_plan','staging_rate_plan:Non-refundable Rate']
    assert second.status_code==200 and second.json()['created']==[]
    assert len(state['posts'])==3
    with sqlite3.connect(db_file) as con:
        config=json.loads(con.execute('SELECT public_config_json FROM integrations WHERE id=?',(integration['id'],)).fetchone()[0])
    assert config['provider_property_id']=='channex-casa'
    assert config['channex_room_type_id']=='room-aqua'
    assert config['channex_rate_plan_id']=='rate-aqua'
    with sqlite3.connect(db_file) as con:
        con.execute("UPDATE integrations SET status='connected' WHERE id=?",(integration['id'],))
    listed=next(x for x in client.get('/api/integrations').json() if x['id']==integration['id'])
    assert listed['connection_stage']=='channex_ready'


def test_channel_bridge_receives_customer_booking_and_queues_government_reports(tmp_path,monkeypatch):
    client,db_file=fresh(tmp_path,monkeypatch); integration=booking_integration(client)
    client.post(f"/api/integrations/{integration['id']}/commercial-connect",json={'booking_hotel_id':'7654321','bridge_property_id':'bridge-aqua'})
    with sqlite3.connect(db_file) as con:
        token=con.execute('SELECT encrypted_payload FROM integration_credentials WHERE integration_id=?',(integration['id'],)).fetchone()[0]
    secret=rosa.decrypt_json(token)['webhook_secret']
    revision={'data':{'type':'booking_revision','id':'revision-101','attributes':{'property_id':'bridge-aqua','booking_id':'booking-101','ota_reservation_code':'BKG-101','ota_name':'Booking.com','status':'new','arrival_date':'2027-06-10','departure_date':'2027-06-13','occupancy':{'adults':2,'children':1,'infants':0},'customer':{'name':'Anna','surname':'Nagy'},'rooms':[]}}}
    received=client.post(f"/api/channel-bridge/webhooks/{integration['id']}",json=revision,headers={'X-Channex-Webhook-Secret':secret})
    assert received.status_code==200,received.text
    duplicate=client.post(f"/api/channel-bridge/webhooks/{integration['id']}",json=revision,headers={'X-Channex-Webhook-Secret':secret})
    assert duplicate.json()['duplicate'] is True
    preview=client.post(f"/api/integrations/{integration['id']}/sync/preview").json()
    item=next(x for x in preview['changes'] if x['external_ref']=='BKG-101')
    assert item['guest_name']=='Anna Nagy' and item['guest_count']==3
    applied=client.post(f"/api/integrations/{integration['id']}/sync/apply")
    assert applied.status_code==200,applied.text
    invitations = [row for row in client.get('/api/communications/outbox').json()
                   if row['message_type'] == 'guest_checkin_invitation'
                   and row['reservation_id'] == item['reservation_id']]
    assert len(invitations) == 1 and invitations[0]['status'] == 'awaiting_approval'
    government=client.get('/api/government/status').json()
    queued={(x['system'],x['status']):x['count'] for x in government['queue']}
    assert queued[('NTAK','waiting_for_certification')]==1
    assert queued[('VIZA','waiting_for_certification')]==1


def test_channel_bridge_rejects_wrong_secret_and_wrong_property(tmp_path,monkeypatch):
    client,db_file=fresh(tmp_path,monkeypatch); integration=booking_integration(client)
    client.post(f"/api/integrations/{integration['id']}/commercial-connect",json={'booking_hotel_id':'7654321','bridge_property_id':'bridge-aqua'})
    with sqlite3.connect(db_file) as con:
        token=con.execute('SELECT encrypted_payload FROM integration_credentials WHERE integration_id=?',(integration['id'],)).fetchone()[0]
    secret=rosa.decrypt_json(token)['webhook_secret']
    revision={'data':{'id':'revision-wrong','attributes':{'property_id':'someone-elses-property','ota_reservation_code':'BKG-X','status':'new','arrival_date':'2027-07-01','departure_date':'2027-07-02','customer':{'name':'Wrong'},'occupancy':{'adults':1}}}}
    assert client.post(f"/api/channel-bridge/webhooks/{integration['id']}",json=revision,headers={'X-Channex-Webhook-Secret':'wrong'}).status_code==401
    assert client.post(f"/api/channel-bridge/webhooks/{integration['id']}",json=revision,headers={'X-Channex-Webhook-Secret':secret}).status_code==403
