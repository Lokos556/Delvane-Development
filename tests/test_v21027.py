import json
import sqlite3
import sys
from datetime import date, timedelta
from pathlib import Path
from fastapi.testclient import TestClient

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import app as rosa


def cert_fixture(tmp_path, monkeypatch):
    db_file = tmp_path / "v21027.db"
    monkeypatch.setattr(rosa, "DB_PATH", db_file)
    monkeypatch.setattr(rosa, "CHANNEX_API_KEY", "shared-test-key")
    rosa.init_db(reset=True)
    client = TestClient(rosa.app)
    login = client.post('/api/login', json={'email': 'owner@demo.rosa', 'password': 'rosa-owner'})
    assert login.status_code == 200, login.text
    client.headers.update({'X-Rosa-CSRF': login.json()['csrf_token']})
    with sqlite3.connect(db_file) as con:
        con.row_factory = sqlite3.Row
        org = 'org_casa_rosa'
        prop = rosa.new_id('prop')
        now = rosa.now_iso()
        con.execute("INSERT INTO properties(id,organization_id,name,slug,address,checkin_time,checkout_time,max_guests) VALUES (?,?,?,?,?,?,?,?)",
                     (prop, org, 'Test Property - Rosa AI', 'channex-certification-test-property', 'test', '15:00', '10:00', 2))
        rooms = []
        for name, remote, count in (('Twin Room', 'remote-twin', 8), ('Double Room', 'remote-double', 4)):
            rid = rosa.new_id('roomtype')
            con.execute("INSERT INTO room_types(id,organization_id,property_id,name,code,inventory_count,max_guests,active,created_at,updated_at) VALUES (?,?,?,?,?,?,?,1,?,?)",
                         (rid, org, prop, name, name.lower().replace(' ', '-'), count, 2, now, now))
            rooms.append((rid, remote, name))
        iid = rosa.new_id('int')
        cfg = {'adapter':'channex_channel_manager','provider_property_id':'remote-cert','channex_room_type_id':'remote-twin',
               'channex_rate_plan_id':'remote-twin-bar','channex_currency':'USD','channex_rate_multiplier':100,
               'commercial':False,'certification_workspace':True}
        con.execute("INSERT INTO integrations(id,organization_id,property_id,provider,connection_type,status,public_config_json,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?,?)",
                     (iid, org, prop, 'Booking.com', 'Channex certification staging', 'connected', json.dumps(cfg), now, now))
        for rid, remote, _ in rooms:
            con.execute("INSERT INTO channex_room_type_mappings(id,organization_id,integration_id,room_type_id,channex_room_type_id,active,created_at,updated_at) VALUES (?,?,?,?,?,1,?,?)",
                         (rosa.new_id('crtm'), org, iid, rid, remote, now, now))
        plans = []
        for rid, remote_room, room_name in rooms:
            for title, remote_plan in (('Best Available Rate', f'{remote_room}-bar'), ('Bed & Breakfast Rate', f'{remote_room}-bb')):
                pid = rosa.new_id('rateplan')
                con.execute("INSERT INTO rate_plans(id,organization_id,property_id,room_type_id,name,code,meal_type,cancellation_policy,base_rate_huf,active,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?,?,1,?,?)",
                             (pid, org, prop, rid, title, f'{room_name.lower()}-{title.lower().replace(" ", "-")}', 'breakfast' if 'Breakfast' in title else 'none', 'flexible', 100, now, now))
                con.execute("INSERT INTO channex_rate_mappings(id,organization_id,integration_id,rate_plan_id,channex_room_type_id,channex_rate_plan_id,active,created_at,updated_at) VALUES (?,?,?,?,?,?,1,?,?)",
                             (rosa.new_id('crm'), org, iid, pid, remote_room, remote_plan, now, now))
                plans.append((pid, remote_plan, room_name, title))
        con.execute("INSERT INTO channel_rate_defaults(integration_id,organization_id,base_nightly_rate_huf,horizon_days,published_through,updated_at) VALUES (?,?,?,?,?,?)",
                     (iid, org, 100, 500, None, now))
    return client, db_file, iid, rooms, plans


def test_cert_full_sync_has_one_complete_500_day_state_per_endpoint(tmp_path, monkeypatch):
    client, db_file, iid, rooms, plans = cert_fixture(tmp_path, monkeypatch)
    calls = []
    monkeypatch.setattr(rosa, '_channex_request', lambda path, method='GET', payload=None: calls.append((path, method, payload)) or {'data':[{'id':'task'}]})
    response = client.post(f'/api/integrations/{iid}/channex/full-sync')
    assert response.status_code == 200, response.text
    availability = next(p for path, _, p in calls if path == '/api/v1/availability')
    restrictions = next(p for path, _, p in calls if path == '/api/v1/restrictions')
    assert len(availability['values']) == 1000
    assert len(restrictions['values']) == 2000
    assert {x['room_type_id'] for x in availability['values']} == {'remote-twin', 'remote-double'}
    assert {x['rate_plan_id'] for x in restrictions['values']} == {p[1] for p in plans}
    expected_dates = [str(date.today() + timedelta(days=i)) for i in range(1, 501)]
    assert sorted({x['date'] for x in availability['values']}) == expected_dates
    assert sorted({x['date'] for x in restrictions['values']}) == expected_dates
    required = {'min_stay_arrival','min_stay_through','max_stay','closed_to_arrival','closed_to_departure','stop_sell'}
    assert all(required.issubset(x) for x in restrictions['values'])
    assert all(x['min_stay_arrival'] == x['min_stay_through'] for x in restrictions['values'])


def test_single_rate_update_can_target_exact_rate_plan_date_and_cert_usd(tmp_path, monkeypatch):
    client, db_file, iid, rooms, plans = cert_fixture(tmp_path, monkeypatch)
    target = str(date.today() + timedelta(days=66))
    chosen_local, chosen_remote, _, _ = plans[-1]
    calls = []
    monkeypatch.setattr(rosa, '_channex_request', lambda path, method='GET', payload=None: calls.append((path, method, payload)) or {'data':[{'id':'task'}]})
    response = client.put(f'/api/integrations/{iid}/channex/ari', json={
        'date_from': target, 'date_to': target, 'rate_plan_id': chosen_local,
        'rate_huf': 456.23, 'min_stay_arrival': 2, 'min_stay_through': 2,
        'max_stay': 14, 'stop_sell': True, 'closed_to_arrival': True, 'closed_to_departure': False,
    })
    assert response.status_code == 200, response.text
    payload = next(p for path, _, p in calls if path == '/api/v1/restrictions')
    item = payload['values'][0]
    assert item['rate_plan_id'] == chosen_remote
    assert item['date_from'] == target and item['date_to'] == target
    assert item['rate'] == 45623
    assert item['min_stay_arrival'] == item['min_stay_through'] == 2
    assert item['max_stay'] == 14 and item['stop_sell'] is True
    with sqlite3.connect(db_file) as con:
        row = con.execute("SELECT nightly_rate_huf,min_stay_arrival,min_stay_through,max_stay,stop_sell,closed_to_arrival,closed_to_departure FROM channex_rate_plan_values WHERE integration_id=? AND rate_plan_id=? AND stay_date=?", (iid, chosen_local, target)).fetchone()
    assert row == (45623, 2, 2, 14, 1, 1, 0)


def test_multiple_rate_update_merges_date_ranges_and_keeps_all_four_plans(tmp_path, monkeypatch):
    client, db_file, iid, rooms, plans = cert_fixture(tmp_path, monkeypatch)
    start = date.today() + timedelta(days=70)
    end = start + timedelta(days=6)
    calls = []
    monkeypatch.setattr(rosa, '_channex_request', lambda path, method='GET', payload=None: calls.append((path, method, payload)) or {'data':[{'id':'task'}]})
    updates = [{
        'rate_plan_id': local, 'date_from': str(start), 'date_to': str(end),
        'min_stay_arrival': 3, 'min_stay_through': 3, 'max_stay': 14,
        'stop_sell': False, 'closed_to_arrival': False, 'closed_to_departure': False,
    } for local, *_ in plans]
    response = client.put(f'/api/integrations/{iid}/channex/ari/batch', json={'updates': updates})
    assert response.status_code == 200, response.text
    calls = [x for x in calls if x[0] == '/api/v1/restrictions']
    assert len(calls) == 1
    values = calls[0][2]['values']
    assert len(values) == 4
    assert {x['rate_plan_id'] for x in values} == {p[1] for p in plans}
    assert all(x['date_from'] == str(start) and x['date_to'] == str(end) for x in values)
    assert all(x['min_stay_arrival'] == x['min_stay_through'] == 3 for x in values)


def test_multiple_date_availability_can_update_all_mapped_rooms_in_one_call(tmp_path, monkeypatch):
    client, db_file, iid, rooms, plans = cert_fixture(tmp_path, monkeypatch)
    start = date.today() + timedelta(days=75)
    end = start + timedelta(days=2)
    calls = []
    monkeypatch.setattr(rosa, '_channex_request', lambda path, method='GET', payload=None: calls.append((path, method, payload)) or {'data':[{'id':'task'}]})
    response = client.put(f'/api/integrations/{iid}/channex/ari', json={
        'date_from': str(start), 'date_to': str(end), 'room_type_id': '__all__', 'availability': 3,
    })
    assert response.status_code == 200, response.text
    calls = [x for x in calls if x[0] == '/api/v1/availability']
    assert len(calls) == 1
    values = calls[0][2]['values']
    assert len(values) == 2
    assert {x['room_type_id'] for x in values} == {'remote-twin', 'remote-double'}
    assert all(x['date_from'] == str(start) and x['date_to'] == str(end) and x['availability'] == 3 for x in values)


def test_booking_new_modified_cancelled_revisions_are_acknowledged(tmp_path, monkeypatch):
    client, db_file, iid, rooms, plans = cert_fixture(tmp_path, monkeypatch)
    room = rooms[0][1]
    def rev(revision_id, external_ref, status, departure):
        return {'type':'booking_revision','id':revision_id,'attributes':{
            'id':revision_id,'property_id':'remote-cert','booking_id':f'booking-{external_ref}','unique_id':f'BDC-{external_ref}',
            'ota_reservation_code':external_ref,'ota_name':'Booking.com','status':status,
            'arrival_date':str(date.today()+timedelta(days=80)),'departure_date':departure,'amount':'123.45','currency':'USD',
            'customer':{'name':'Cert','surname':'Guest'},'occupancy':{'adults':1,'children':0,'infants':0},
            'rooms':[{'room_type_id':room,'rate_plan_id':plans[0][1],'checkin_date':str(date.today()+timedelta(days=80)),'checkout_date':departure,'occupancy':{'adults':1,'children':0,'infants':0}}]}}
    feed = [rev('rev-new','CERT-NEW','new',str(date.today()+timedelta(days=82)))]
    acked = []
    state = {'feed': feed}
    def fake_request(path, method='GET', payload=None):
        if '/booking_revisions/feed?' in path: return {'data': state['feed']}
        if path.endswith('/ack'):
            acked.append(path)
            return {'meta':{'message':'Success'}}
        raise AssertionError((path, method, payload))
    monkeypatch.setattr(rosa, '_channex_request', fake_request)
    assert client.post(f'/api/integrations/{iid}/channex/receive').json()['counts']['acknowledged'] == 1
    state['feed'] = [rev('rev-mod','CERT-NEW','modified',str(date.today()+timedelta(days=83)))]
    assert client.post(f'/api/integrations/{iid}/channex/receive').json()['counts']['acknowledged'] == 1
    state['feed'] = [rev('rev-cancel','CERT-NEW','cancelled',str(date.today()+timedelta(days=83)))]
    assert client.post(f'/api/integrations/{iid}/channex/receive').json()['counts']['acknowledged'] == 1
    assert len(acked) == 3
