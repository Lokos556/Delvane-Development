"""Client workflow checks in the synthetic, isolated Pilot PostgreSQL lab."""

from datetime import date, timedelta
from http.client import HTTPConnection
from http.cookies import SimpleCookie
import json
import os

from uat_postgres_smoke import verify_isolation


class Client:
    def __init__(self):
        self.headers = {'Host': 'api.delvane.app', 'X-Forwarded-Proto': 'https',
                        'Content-Type': 'application/json'}
        body, response = self.request('POST', '/api/login', {
            'email': 'owner-a@uat.invalid', 'password': os.environ['PILOT_OWNER_PASSWORD'],
        })
        cookie = SimpleCookie(response.get('Set-Cookie'))['rosa_session']
        assert cookie['secure'] and cookie['httponly']
        self.headers.update(Cookie=f'rosa_session={cookie.value}', **{'X-Rosa-CSRF': body['csrf_token']})

    def request(self, method, path, body=None, status=200):
        connection = HTTPConnection('127.0.0.1', 8080, timeout=5)
        try:
            connection.request(method, path, json.dumps(body) if body is not None else None, self.headers)
            response = connection.getresponse()
            assert response.status == status, (method, path, response.status, status)
            return json.load(response), response.headers
        finally:
            connection.close()


def main():
    verify_isolation()
    android, windows = Client(), Client()
    arrival = date.today() + timedelta(days=200)
    created, _ = android.request('POST', '/api/reservations', {
        'property_id': 'prop_uat_a', 'room_type_id': 'room_uat', 'guest_name': 'Synthetic V2 primary guest',
        'source': 'Direct', 'arrival_date': str(arrival), 'departure_date': str(arrival + timedelta(days=1)),
        'guest_count': 2, 'external_ref': 'SYNTHETIC-V2-PG',
    })
    base = f"/api/reservations/{created['id']}"
    windows.request('GET', base + '/reporting-details')
    windows.request('GET', base + '/allocations')
    departure = str(arrival + timedelta(days=2))
    windows.request('PATCH', base, {'departure_date': departure})
    detail, _ = android.request('GET', base + '/detail')
    assert detail['reservation']['departure_date'] == departure
    records, _ = android.request('GET', base + '/guest-checkin-status')
    path = f"/api/registration/records/{records['guests'][1]['id']}/workspace"
    profile, _ = android.request('GET', path)
    android.request('PUT', path, {'revision': profile['revision'], 'identity': {
        'manual': {'csaladnev': 'Synthetic', 'utonev': 'Second Guest'},
    }})
    restored, _ = windows.request('GET', path)
    assert restored['identity']['utonev'] == 'Second Guest' and not restored['can_verify']
    assert restored['verification']['status'] == 'needs_review'
    windows.request('GET', '/api/properties/prop_uat_b/overview', status=404)
    print('Native ingress booking edit, encrypted second-guest draft and tenant isolation passed on PostgreSQL.')


if __name__ == '__main__':
    main()
