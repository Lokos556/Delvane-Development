"""Focused regressions for the new booking-to-invitation and checkout rules."""

from concurrent.futures import ThreadPoolExecutor
from datetime import date, datetime, time, timedelta
from zoneinfo import ZoneInfo

import pytest
import app
from test_actual_stays import act
from test_flutter_reservation_reception import body, client, login
from test_reservation_allocations import assign, setup


def invitation(client, rid):
    return client.get(f'/api/reservations/{rid}/detail').json()['precheckin_invitation']


def dispatch_url(invitation):
    return '/api/communications/outbox/' + invitation['id']


def test_invitation_retry_rollback_and_concurrent_duplicate(client, monkeypatch):
    login(client)
    rid = client.post('/api/reservations', json=body()).json()['id']
    url = dispatch_url(invitation(client, rid))
    assert client.patch(url, json={'status': 'simulated_sent'}).status_code == 409
    assert client.post(url + '/approve').status_code == 200
    issue = app._create_guest_checkin_token
    seen = []

    def fail_after_one(con, reservation, guest):
        if seen:
            raise RuntimeError('Fictional local delivery preparation failure')
        seen.append(guest['id'])
        return issue(con, reservation, guest)

    with monkeypatch.context() as m:
        m.setattr(app, '_create_guest_checkin_token', fail_after_one)
        with pytest.raises(RuntimeError, match='Fictional local'):
            client.post(url + '/simulate-send')
    assert invitation(client, rid)['status'] == 'ready'
    with app.db() as con:
        assert not con.execute('SELECT 1 FROM guest_checkin_tokens WHERE reservation_id=?', (rid,)).fetchone()
    with ThreadPoolExecutor(max_workers=2) as pool:
        results = list(pool.map(lambda _: client.post(url + '/simulate-send'), range(2)))
    assert [x.status_code for x in results] == [200, 200]
    docs = [x.json() for x in results]
    assert sum('links' in document for document in docs) == 1
    assert sum(document.get('duplicate', False) for document in docs) == 1
    with app.db() as con:
        assert con.execute('SELECT COUNT(*) n FROM guest_checkin_tokens WHERE reservation_id=?', (rid,)).fetchone()['n'] == 2
    assert client.post(url + '/approve').json()['status'] == 'simulated_sent'


def test_booking_date_change_and_cancellation_invalidate_invitation(client):
    login(client)
    booking = body()
    rid = client.post('/api/reservations', json=booking).json()['id']
    path = '/api/reservations/' + rid
    initial = invitation(client, rid)
    url = dispatch_url(initial)
    # Arrival preference and folio edits are not an invitation version change.
    assert client.patch(path, json={'arrival_time': '20:30'}).status_code == 200
    assert invitation(client, rid) == initial
    assert client.post(url + '/approve').status_code == 200
    link = client.post(url + '/simulate-send').json()['links'][0]['url']
    public = '/api/public/checkin/' + link.rsplit('/', 1)[1]
    changed = str(app.date.fromisoformat(booking['departure_date']) + timedelta(days=1))
    assert client.patch(path, json={'departure_date': changed}).status_code == 200
    assert client.get(public).status_code == 410
    assert client.post(url + '/simulate-send').status_code == 409
    replacement = invitation(client, rid)
    assert replacement['id'] != initial['id'] and replacement['status'] == 'awaiting_approval'
    assert client.delete(path).status_code == 200
    assert invitation(client, rid) is None
    assert client.post(dispatch_url(replacement) + '/approve').status_code == 409


def test_partial_departure_then_late_checkout_moves_same_turnover(client, monkeypatch):
    room_type, units = setup(client)
    tz = ZoneInfo('Europe/Budapest')
    now = datetime.now(tz)
    today = now.date()
    arrival_day, scheduled_day = today - timedelta(days=3), today - timedelta(days=1)
    data = {**body(), 'room_type_id': room_type, 'arrival_date': str(arrival_day),
            'departure_date': str(scheduled_day)}
    booking = client.post('/api/reservations', json=data)
    assert booking.status_code == 200, booking.text
    rid = booking.json()['id']
    path = f'/api/reservations/{rid}'
    assert assign(client, rid, data, [units[0][0]]).status_code == 200

    def task():
        tasks = client.get(path + '/detail').json()['cleaning']
        return next(row for row in tasks if row['previous_reservation_id'] == rid)

    original = task()
    gids = [g['id'] for g in client.get(path + '/actual-stay').json()['guests']]
    started = datetime.combine(arrival_day, time(15), tz)
    first_departure = datetime.combine(scheduled_day, time(11), tz)
    late = now - timedelta(seconds=1)
    if late.date() != today:
        late = datetime.combine(today, time(), tz)
    assert act(client, rid, gids, started, uid=units[0][0])[0].status_code == 200
    assert act(client, rid, gids[:1], first_departure, kind='depart')[0].status_code == 200
    assert task()['scheduled_date'] == str(scheduled_day)
    assert act(client, rid, gids[1:], late, kind='depart')[0].status_code == 200
    moved = task()
    assert moved['id'] == original['id'] and moved['assigned_to'] == original['assigned_to']
    assert moved['scheduled_date'] == str(today) and moved['earliest_time'] == late.strftime('%H:%M')

    class AfterMissedCleaning(date):
        @classmethod
        def today(cls):
            return today + timedelta(days=3)

    monkeypatch.setattr(app, 'date', AfterMissedCleaning)
    assert next(p for p in client.get('/api/owner/dashboard').json()['properties']
                if p['id'] == 'prop_flora')['state'] == 'cleaning'
    login(client, 'cleaner')
    [overdue] = [t for t in client.get('/api/worker/dashboard').json()['tasks'] if t['id'] == moved['id']]
    assert overdue['status'] == 'open' and not overdue['waiting_for_checkout']
