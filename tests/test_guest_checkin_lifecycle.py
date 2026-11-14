"""Guest links follow the current booking state, using disposable API records."""
import pytest
from test_flutter_reservation_reception import client, login, body
import app


@pytest.mark.parametrize('status', ['cancelled', 'inquiry'])
def test_nonconfirmed_booking_cannot_issue_or_use_guest_links(client, status):
    login(client)
    rid = client.post('/api/reservations', json=body()).json()['id']
    url = client.get(f'/api/reservations/{rid}/guest-checkin-links').json()['links'][0]['url']
    token = url.rsplit('/', 1)[-1]
    public = f'/api/public/checkin/{token}'
    assert client.get(public).status_code == 200
    if status == 'cancelled':
        assert client.delete(f'/api/reservations/{rid}').status_code == 200
    else:
        assert client.patch(f'/api/reservations/{rid}', json={'status':status}).status_code == 200
    with app.db() as con:
        before = con.execute('SELECT COUNT(*) c FROM government_scan_events WHERE reservation_id=?', (rid,)).fetchone()['c']
    assert client.get(f'/api/reservations/{rid}/guest-checkin-links').status_code == 409
    # A separate unauthenticated guest must be refused on both read and submit.
    client.cookies.clear()
    client.headers.pop('X-Rosa-CSRF', None)
    assert client.get(public).status_code == 410
    response = client.post(public, json={
        'full_name':'Synthetic Guest', 'date_of_birth':'2000-01-02',
        'nationality':'HUN', 'document_type':'passport', 'document_number':'SYNTHETIC',
        'guest_confirmed':True, 'scan_method':'manual',
    })
    assert response.status_code == 410
    with app.db() as con:
        assert con.execute('SELECT COUNT(*) c FROM government_scan_events WHERE reservation_id=?', (rid,)).fetchone()['c'] == before
        assert not con.execute('SELECT 1 FROM sensitive_guest_data WHERE guest_record_id IN (SELECT id FROM guest_records WHERE reservation_id=?)', (rid,)).fetchone()
