"""Connected overnight turnover tests through normal PMS endpoints."""

from datetime import datetime, time, timedelta
from zoneinfo import ZoneInfo

from fastapi.testclient import TestClient

import app
from test_actual_stays import act
from test_flutter_reservation_reception import body, client, login
from test_reservation_allocations import setup

PROPERTY = '/api/properties/prop_flora/overview'


def booking(client, start, end):
    room_type, configured = setup(client)
    units = [room[0] for room in configured[:2]]
    data = {**body(), 'room_type_id': room_type, 'arrival_date': str(start),
            'departure_date': str(end), 'total_huf': 14000,
            'allocations': [{'unit_id': unit, 'date_from': str(start), 'date_to': str(end)}
                            for unit in units]}
    created = client.post('/api/reservations', json=data)
    assert created.status_code == 200, created.text
    return created.json()['id'], units


def states(client):
    payload = client.get(PROPERTY)
    assert payload.status_code == 200
    return {unit['unit_id']: unit['state'] for unit in payload.json()['unit_readiness']}


def tasks(client, rid):
    result = client.get(f'/api/reservations/{rid}/detail')
    assert result.status_code == 200
    return [row for row in result.json()['cleaning'] if row['previous_reservation_id'] == rid]


def complete(client, path):
    assert client.post(path + '/start').status_code == 200
    assert client.post(path + '/finish', json={}).status_code == 409
    for item in client.get(path + '/checklist').json():
        assert client.patch(path + '/checklist/' + item['id'], json={'completed': True}).status_code == 200
    assert client.post(path + '/finish', json={'note': 'Synthetic room ready'}).status_code == 200


def test_booking_to_independent_room_readiness_with_checkout_correction(client):
    tz = ZoneInfo('Europe/Budapest')
    yesterday = datetime.now(tz).date() - timedelta(days=1)
    rid, units = booking(client, yesterday, yesterday + timedelta(days=2))
    path = f'/api/reservations/{rid}'
    detail = client.get(path + '/detail').json()
    invite = '/api/communications/outbox/' + detail['precheckin_invitation']['id']
    assert client.post(invite + '/approve').status_code == 200
    simulated = client.post(invite + '/simulate-send').json()
    assert simulated['external_send'] is False
    guests = []
    with TestClient(app.app) as guest:
        for index, link in enumerate(simulated['links']):
            gid = link['guest_record_id']
            guests.append(gid)
            token = link['url'].rsplit('/', 1)[-1]
            submitted = guest.post('/api/public/checkin/' + token, json={
                'full_name': f'Fictional Guest {index}', 'date_of_birth': '1986-01-02',
                'nationality': 'HU', 'document_type': 'passport', 'document_number': f'FAKE-{index}',
                'guest_confirmed': True, 'scan_method': 'manual',
            })
            assert submitted.status_code == 200
            assert client.post(f'{path}/guests/{gid}/verify', json={'verification_method': 'in_person'}).status_code == 200
    assert client.get(path + '/detail').json()['reservation']['registration_status'] == 'complete'
    first, second = sorted(tasks(client, rid), key=lambda t: t['unit_label'])
    assert '101' in first['unit_label'] and '102' in second['unit_label']
    for gid, unit in zip(guests, units):
        assert act(client, rid, [gid], datetime.combine(yesterday, time(14), tz), uid=unit)[0].status_code == 200
    assert set(states(client)[u] for u in units) == {'occupied'}
    first_work, second_work = ['/api/work-tasks/' + item['id'] for item in (first, second)]
    login(client, 'cleaner')
    assert client.get(PROPERTY).status_code == 403
    assert client.post(first_work + '/start').status_code == 409
    login(client)

    left, command = act(client, rid, guests[:1], datetime.combine(yesterday, time(15), tz), kind='depart')
    assert left.status_code == 200
    assert client.post(path + '/actual-stay', json=command).json()['duplicate']
    assert {row['id'] for row in tasks(client, rid)} == {first['id'], second['id']}
    state = states(client)
    assert [state[u] for u in units] == ['cleaning', 'occupied']
    login(client, 'cleaner')
    worker_tasks = {row['id']: row for row in client.get('/api/worker/dashboard').json()['tasks']}
    assert worker_tasks[first['id']]['checkout_observed'] is True
    assert worker_tasks[second['id']]['waiting_for_checkout'] is True
    assert client.post(second_work + '/start').status_code == 409
    complete(client, first_work)
    login(client)
    state = states(client)
    assert [state[u] for u in units] == ['ready', 'occupied']

    corrected, _ = act(client, rid, guests[:1], datetime.combine(yesterday, time(16), tz),
                       kind='undo_departure', correction_of=left.json()['id'])
    assert corrected.status_code == 200, corrected.text
    assert states(client)[units[0]] == 'occupied'
    assert act(client, rid, guests[:1], datetime.combine(yesterday, time(17), tz), kind='depart')[0].status_code == 200
    assert states(client)[units[0]] == 'cleaning'
    for gid in guests[1:]:
        assert act(client, rid, [gid], datetime.combine(yesterday, time(18), tz), kind='depart')[0].status_code == 200
    all_tasks = tasks(client, rid)
    assert len(all_tasks) == 3
    assert next(row for row in all_tasks if row['id'] == first['id'])['status'] == 'complete'
    new_first = next(row for row in all_tasks if '101' in row['unit_label'] and row['status'] == 'open')
    login(client, 'cleaner')
    complete(client, '/api/work-tasks/' + new_first['id'])
    complete(client, second_work)
    login(client)
    assert set(states(client)[u] for u in units) == {'ready'}
    dashboard = client.get('/api/owner/dashboard').json()['properties']
    assert next(p for p in dashboard if p['id'] == 'prop_flora')['unit_readiness'] == client.get(PROPERTY).json()['unit_readiness']


def test_date_changes_keep_task_and_cancellation_retires_only_planned_work(client):
    start = app.date.today() + timedelta(days=5)
    end = start + timedelta(days=2)
    rid, _ = booking(client, start, end)
    original = tasks(client, rid)
    assert len(original) == 2
    changed = client.patch(f'/api/reservations/{rid}', json={'departure_date': str(end + timedelta(days=1))})
    assert changed.status_code == 200, changed.text
    moved = tasks(client, rid)
    assert {row['id'] for row in moved} == {row['id'] for row in original}
    assert {row['scheduled_date'] for row in moved} == {str(end + timedelta(days=1))}
    # Retire the fixture's unrelated work so only this booking grants access.
    with app.db() as con:
        con.execute("""UPDATE work_tasks SET status='complete' WHERE property_id='prop_flora'
            AND COALESCE(previous_reservation_id,'')!=?""", (rid,))
    login(client, 'cleaner')
    assert any(row['id'] == 'prop_flora' for row in client.get('/api/operations/properties').json())
    login(client)
    assert client.delete(f'/api/reservations/{rid}').status_code == 200
    assert not tasks(client, rid)
    login(client, 'cleaner')
    assert not any(row['id'] == 'prop_flora' for row in client.get('/api/operations/properties').json())
    assert client.post('/api/work-tasks/' + moved[0]['id'] + '/start').status_code == 409
