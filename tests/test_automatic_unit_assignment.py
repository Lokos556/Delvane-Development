from concurrent.futures import ThreadPoolExecutor
from datetime import timedelta
from zoneinfo import ZoneInfo

from fastapi.testclient import TestClient

import app
from test_actual_stays import act
from test_flutter_reservation_reception import body, client, login
from test_reservation_allocations import BASE, setup


def booking(client, data):
    result = client.post('/api/reservations', json=data)
    assert result.status_code == 200, result.text
    return result.json()['id']


def path(rid):
    return f'/api/reservations/{rid}/allocations'


def options(client, rid):
    result = client.get(path(rid), params={'include_options': True})
    assert result.status_code == 200
    return result.json()


def select(client, rid, expected=(), unit=None):
    return client.put(path(rid), json={
        'mode': 'specific' if unit else 'automatic',
        **({'unit_id': unit} if unit else {}),
        'expected_active_ids': list(expected),
    })


def test_create_assigns_best_fit_respects_periods_and_keeps_unrelated_edits(client):
    room, units = setup(client)
    stay = {**body(), 'room_type_id': room}
    first = booking(client, stay)
    first_plan = options(client, first)
    assert first_plan['active'][0]['unit_id'] == units[1][0]
    assert first_plan['active'][0]['label'] == 'Fictional building · 102'
    assert client.post(f'{BASE}/{units[0][0]}/periods', json={
        'state': 'OOS', 'date_from': stay['departure_date'],
        'date_to': stay['departure_date'], 'reason': 'Fictional plumbing maintenance',
    }).status_code == 200
    assert client.post(f'{BASE}/{units[0][0]}/periods', json={
        'state': 'OOO', 'date_from': stay['arrival_date'], 'date_to': stay['arrival_date'],
        'reason': 'Fictional overnight restriction',
    }).status_code == 200
    second = booking(client, stay)
    second_plan = options(client, second)
    assert second_plan['active'][0]['unit_id'] == units[2][0]
    assert client.patch(f'/api/reservations/{second}', json={'arrival_time': '19:00'}).status_code == 200
    assert options(client, second)['active'] == second_plan['active']
    detail = client.get(f'/api/reservations/{second}/detail').json()
    assert detail['planned_allocations'][0]['label'] == 'Fictional building · 103'
    assert select(client, second, second_plan['expected_active_ids'], units[3][0]).status_code == 200
    assert select(client, second, second_plan['expected_active_ids'], units[2][0]).status_code == 409
    with app.db() as con:
        assert app._reservation_availability(con, 'org_casa_rosa', 'prop_flora',
                                             app.date.fromisoformat(stay['arrival_date']), room) == 2


def test_explicit_unit_and_candidate_preview_use_whole_stay(client):
    room, units = setup(client)
    stay = {**body(), 'room_type_id': room}
    last_night = str(app.date.fromisoformat(stay['departure_date']) - timedelta(days=1))
    assert client.post(f'{BASE}/{units[0][0]}/periods', json={
        'state': 'OOS', 'date_from': last_night, 'date_to': last_night, 'reason': 'Fictional service outage',
    }).status_code == 200
    preview = client.get(f'{BASE}/assignment-options', params={
        key: stay[key] for key in ('room_type_id', 'arrival_date', 'departure_date', 'guest_count')
    })
    assert preview.status_code == 200
    choices = [unit['unit_id'] for unit in preview.json()['options']]
    assert choices == [unit[0] for unit in units[1:]]
    selected = units[3][0]
    rid = booking(client, {**stay, 'selected_unit_id': selected})
    assert options(client, rid)['active'][0]['unit_id'] == selected
    assert client.get(f'/api/reservations/res_other_secret/allocations', params={'include_options': True}).status_code == 404
    login(client, 'cleaner')
    assert client.get(path(rid), params={'include_options': True}).status_code == 403


def test_single_compatible_unit_and_wrong_room_type(client):
    room, units = setup(client)
    with app.db() as con:
        con.execute('''INSERT INTO room_types(id,organization_id,property_id,name,code,inventory_count,max_guests,active,created_at,updated_at)
            VALUES ('solo-room-type','org_casa_rosa','prop_flora','Fictional single apartment','solo',1,3,1,?,?)''',
            (app.now_iso(), app.now_iso()))
    solo = units[-1]
    assert client.put(f'{BASE}/{solo[0]}', json={
        **solo[1], 'room_type_id': 'solo-room-type', 'effective_from': str(app.date.today()),
    }).status_code == 200
    stay = {**body(), 'room_type_id': 'solo-room-type'}
    rejected = client.post('/api/reservations', json={**stay, 'selected_unit_id': units[1][0]})
    assert rejected.status_code == 409
    rid = booking(client, stay)
    assert options(client, rid)['active'][0]['unit_id'] == solo[0]
    assert select(client, rid, options(client, rid)['expected_active_ids'], units[1][0]).status_code == 409


def test_legacy_booking_assignment_unlocks_actual_checkin_and_cleaning(client):
    room, units = setup(client)
    now = app.datetime.now(ZoneInfo('Europe/Budapest'))
    stay = {
        **body(), 'room_type_id': room, 'allocations': [],
        'arrival_date': str(now.date() - timedelta(days=1)),
        'departure_date': str(now.date() + timedelta(days=1)),
    }
    rid = booking(client, stay)
    actual = f'/api/reservations/{rid}/actual-stay'
    guests = [guest['id'] for guest in client.get(actual).json()['guests']]
    first, _ = act(client, rid, guests, now - timedelta(minutes=3))
    assert first.status_code == 409 and first.json()['detail']['code'] == 'stay_allocation_required'
    assert select(client, rid).status_code == 200
    plan = options(client, rid)
    unit = plan['active'][0]['unit_id']
    entered, _ = act(client, rid, guests, now - timedelta(minutes=2), uid=unit)
    assert entered.status_code == 200
    assert options(client, rid)['blocker'] == 'unit_assignment_has_actual_stay'
    assert select(client, rid, plan['expected_active_ids'], units[3][0]).status_code == 409
    departed, _ = act(client, rid, guests, now - timedelta(minutes=1), kind='depart')
    assert departed.status_code == 200
    detail = client.get(f'/api/reservations/{rid}/detail').json()
    assert detail['reservation']['actual_occupants'] == 0
    assert any(task.get('unit_label') == plan['active'][0]['label']
               and task['checkout_observed'] for task in detail['cleaning'])


def test_concurrent_operator_claims_and_automatic_creates(client):
    room, units = setup(client)
    stay = {**body(), 'room_type_id': room}
    first, second = [booking(client, {**stay, 'allocations': []}) for _ in range(2)]

    def claim(rid):
        with TestClient(app.app) as independent:
            login(independent, 'manager')
            return select(independent, rid, unit=units[1][0]).status_code

    with ThreadPoolExecutor(max_workers=2) as pool:
        assert sorted(pool.map(claim, (first, second))) == [200, 409]

    later = {**stay, 'arrival_date': str(app.date.today() + timedelta(days=220)),
             'departure_date': str(app.date.today() + timedelta(days=223))}

    def create(number):
        with TestClient(app.app) as independent:
            login(independent, 'manager')
            return booking(independent, {**later, 'guest_name': f'Synthetic guest {number}'})

    with ThreadPoolExecutor(max_workers=2) as pool:
        ids = list(pool.map(create, (1, 2)))
    assert len({options(client, rid)['active'][0]['unit_id'] for rid in ids}) == 2


def test_channex_mapped_import_allocates_and_preserves_or_releases_unit(client):
    room, units = setup(client)
    with app.db() as con:
        integration = con.execute('''SELECT i.*, p.name property_name FROM integrations i
            JOIN properties p ON p.id=i.property_id WHERE i.property_id='prop_flora'
            AND i.organization_id='org_casa_rosa' AND lower(i.provider) LIKE '%booking%' LIMIT 1''').fetchone()
        assert integration
        stay = body()
        event = {**stay, 'external_ref': 'SYNTHETIC-UNIT-CHANNEX', 'provider_event_id': 'synthetic-unit-1',
                 'status': 'active', 'payload': {}}
        app._stage_provider_event(con, integration, event)
        rid = app._apply_channex_event(con, integration, event, room)['reservation_id']
        assigned = app.reservation_allocations.active(con, rid)[0]
        assert assigned['unit_id'] == units[1][0]
        revised = {**event, 'provider_event_id': 'synthetic-unit-2', 'guest_name': 'Fictional updated guest'}
        app._stage_provider_event(con, integration, revised)
        app._apply_channex_event(con, integration, revised, room)
        assert app.reservation_allocations.active(con, rid)[0]['id'] == assigned['id']
        cancelled = {**revised, 'provider_event_id': 'synthetic-unit-3', 'status': 'cancelled'}
        app._stage_provider_event(con, integration, cancelled)
        app._apply_channex_event(con, integration, cancelled, room)
        assert not app.reservation_allocations.active(con, rid)
