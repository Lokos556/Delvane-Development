"""Native V3 regressions with distinct authenticated sessions on a disposable database."""
from collections import Counter
from datetime import timedelta
from time import perf_counter

from fastapi.testclient import TestClient
import pytest

import app
from test_flutter_reservation_reception import body, client, login


def test_second_operator_sees_contact_and_edits_without_overwrite(client):
    login(client)
    first = 'synthetic-invitation@example.invalid'
    second = 'updated-invitation@example.invalid'
    booking = body()
    made = client.post('/api/reservations', json={**booking, 'invitation_email': first})
    assert made.status_code == 200
    rid = made.json()['id']
    path = f'/api/reservations/{rid}'
    with TestClient(app.app) as other:
        login(other, 'manager')
        assert other.cookies['rosa_session'] != client.cookies['rosa_session']
        assert next(row for row in other.get('/api/reservations').json() if row['id'] == rid).get('invitation_email') is None
        assert 'invitation_email' not in other.get(path + '/detail').json()['reservation']
        opened = other.get(path + '/booking-contact')
        assert 'no-store' in opened.headers.get('Cache-Control', '')
        assert opened.json()['invitation_email'] == first
        assert other.patch(path, json={'invitation_email': second}).status_code == 200
        assert client.patch(path, json={'arrival_time': '18:30'}).status_code == 200
        saved = other.get(path + '/detail').json()['reservation']
        assert other.get(path + '/booking-contact').json()['invitation_email'] == second
        assert saved['arrival_time'] == '18:30'
        assert saved['guest_count'] == booking['guest_count']
        departure = str(app.date.fromisoformat(booking['departure_date']) + timedelta(days=1))
        assert other.patch(path, json={'departure_date': departure}).status_code == 200
        assert next(row for row in client.get('/api/reservations').json() if row['id'] == rid)['departure_date'] == departure
        with app.db() as con:
            encrypted = con.execute('SELECT encrypted_email FROM guest_invitation_contacts WHERE reservation_id=?', (rid,)).fetchone()
            assert second not in encrypted['encrypted_email']
        assert client.delete(path).status_code == 200
        assert other.get(path + '/detail').json()['reservation']['status'] == 'cancelled'

    with TestClient(app.app) as worker:
        login(worker, 'cleaner')
        assert worker.get(path + '/detail').status_code == 403
        assert worker.get(path + '/booking-contact').status_code == 403
        assert worker.get(path + '/actual-stay').status_code == 403
    assert client.get('/api/reservations/res_other_secret/booking-contact').status_code == 404


def test_reception_guest_context_is_batched_and_keeps_preferences(client, monkeypatch):
    login(client)
    rid = 'res_terra_next'
    for number in range(12):
        response = client.post('/api/inbox', json={
            'reservation_id': rid, 'subject': f'Synthetic message {number}',
            'body': 'Fictional Reception message.', 'sender_name': 'Synthetic contact',
        })
        assert response.status_code == 200
    with app.db() as con:
        row = con.execute('SELECT guest_id FROM guest_reservations WHERE reservation_id=? AND is_primary=1', (rid,)).fetchone()
        assert row is not None
        for number in range(7):
            con.execute('INSERT INTO guest_preferences VALUES (?,?,?,?,?,?,?)', (
                f'v3-preference-{number}', 'org_casa_rosa', row['guest_id'], f'000-{number}',
                'Synthetic preference', 'owner', app.now_iso()))

    calls = Counter()
    execute = app.DBConnection.execute

    def measure(self, sql, params=()):
        if 'FROM inbox_messages m' in sql:
            calls['inbox'] += 1
        if 'FROM guest_preferences' in sql:
            calls['preferences'] += 1
        if 'SELECT g.* FROM guest_reservations' in sql:
            calls['per_message'] += 1
        return execute(self, sql, params)

    monkeypatch.setattr(app.DBConnection, 'execute', measure)
    start = perf_counter()
    result = client.get('/api/inbox')
    elapsed_ms = (perf_counter() - start) * 1000
    assert result.status_code == 200
    linked = [message for message in result.json() if message.get('reservation_id') == rid]
    assert len(linked) >= 12
    assert all(len(message['guest_context']['preferences']) == 5 for message in linked)
    assert all(message['guest_context']['id'] == row['guest_id'] for message in linked)
    assert all('linked_guest_id' not in message for message in linked)
    assert calls == {'inbox': 1, 'preferences': 1}
    print(f'Local Reception API returned {len(result.json())} messages in {elapsed_ms:.1f} ms using two inbox data statements.')

