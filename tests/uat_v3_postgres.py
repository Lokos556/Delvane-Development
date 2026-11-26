"""Exercise the packaged V3 native ingress with no external transport."""
from datetime import date, timedelta
from urllib.request import urlopen
import json

from uat_v2_postgres import Client
from uat_postgres_smoke import verify_isolation


def main():
    verify_isolation()
    for route, expected in (
        ('live', {'version': '2.10.60'}),
        ('ready', {'schema_version': 3091, 'database': 'postgresql'}),
        ('workers', {'operations_running': True, 'delivery_running': True}),
    ):
        with urlopen(f'http://127.0.0.1:8080/health/{route}', timeout=4) as response:
            actual = json.load(response)
        assert all(actual.get(key) == value for key, value in expected.items()), actual

    android, windows = Client(), Client()
    assert android.headers['Cookie'] != windows.headers['Cookie']
    arrival = date.today() + timedelta(days=230)
    booking, _ = windows.request('POST', '/api/reservations', {
        'property_id': 'prop_uat_a', 'room_type_id': 'room_uat', 'guest_name': 'Synthetic V3 booking',
        'source': 'Direct', 'arrival_date': str(arrival), 'departure_date': str(arrival + timedelta(days=2)),
        'guest_count': 1, 'invitation_email': 'fictional-v3@pilot.invalid',
    })
    rid = booking['id']
    base = f'/api/reservations/{rid}'
    reservations, _ = android.request('GET', '/api/reservations')
    assert any(row['id'] == rid and 'invitation_email' not in row for row in reservations)
    detail, _ = android.request('GET', base + '/detail')
    assert 'invitation_email' not in detail['reservation']
    contact, headers = android.request('GET', base + '/booking-contact')
    assert contact == {'invitation_email': 'fictional-v3@pilot.invalid'}
    assert headers['Cache-Control'] == 'no-store'
    android.request('PATCH', base, {'arrival_time': '20:00'})
    saved, _ = windows.request('GET', base + '/booking-contact')
    assert saved == contact
    stay, _ = windows.request('GET', base + '/actual-stay')
    assert stay['reservation_status'] == 'confirmed' and stay['actual_occupants'] == 0
    assert 'unit_readiness' in stay and 'business_date' in stay
    android.request('GET', base + '/reporting-details')
    windows.request('GET', '/api/properties/prop_uat_b/overview', status=404)
    windows.request('POST', '/api/inbox', {
        'reservation_id': rid, 'sender_name': 'Synthetic contact', 'subject': 'Synthetic V3 message',
        'body': 'We expect to arrive in the evening.',
    })
    inbox, _ = android.request('GET', '/api/inbox')
    assert any(row['reservation_id'] == rid and row['subject'] == 'Synthetic V3 message' for row in inbox)
    print('V3 image, schema 3091, workers, independent sessions, encrypted contact read, inbox and isolation passed.')


if __name__ == '__main__':
    main()
