"""Verify the room-assignment release in the disposable UAT PostgreSQL lab."""
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta
import json
from urllib.request import urlopen
from uuid import uuid4
from zoneinfo import ZoneInfo

from uat_postgres_smoke import verify_isolation
from uat_v2_postgres import Client


def main():
    verify_isolation()
    for route, expected in (
        ('live', {'version': '2.10.61'}),
        ('ready', {'database': 'postgresql', 'schema_version': 3091}),
    ):
        with urlopen(f'http://127.0.0.1:8080/health/{route}', timeout=4) as response:
            data = json.load(response)
        assert all(data.get(key) == value for key, value in expected.items()), data

    owner, second = Client(), Client()
    assert owner.headers['Cookie'] != second.headers['Cookie']
    property_path = '/api/properties/prop_uat_a'
    room = owner.request('POST', property_path + '/room-types', {
        'name': 'Synthetic rooms', 'code': 'synthetic-room-assignment',
        'inventory_count': 2, 'max_guests': 2,
    })[0]['room_type_id']
    now = datetime.now(ZoneInfo('Europe/Budapest'))
    for number in ('201', '202'):
        owner.request('POST', property_path + '/physical-units', {
            'effective_from': str(now.date() - timedelta(days=3)),
            'room_type_id': room, 'building': 'Synthetic wing', 'unit_number': number,
            'classification': 'STANDARD', 'single_beds': 0, 'double_beds': 1,
            'extra_beds': 0, 'reason': 'Disposable test unit',
        })
    base = {'source': 'Direct', 'property_id': 'prop_uat_a', 'room_type_id': room,
            'guest_count': 1}
    future = now.date() + timedelta(days=120)

    def book(user, name, arrival, departure, **extra):
        return user.request('POST', '/api/reservations', {
            **base, **extra, 'guest_name': name,
            'arrival_date': str(arrival), 'departure_date': str(departure),
        })[0]['id']

    def create(user):
        return book(user, 'Synthetic future booking', future, future + timedelta(days=2))

    with ThreadPoolExecutor(max_workers=2) as workers:
        concurrent = list(workers.map(create, (owner, second)))
    occupied = {
        owner.request('GET', f'/api/reservations/{rid}/detail')[0]['planned_allocations'][0]['unit_id']
        for rid in concurrent
    }
    assert len(occupied) == 2

    rid = book(owner, 'Synthetic legacy booking', now.date() - timedelta(days=1),
               now.date() + timedelta(days=1), allocations=[])
    stay = f'/api/reservations/{rid}'
    proposal = second.request('GET', stay + '/allocations?include_options=true')[0]
    assert proposal['options'] and proposal['active'] == []
    second.request('PUT', stay + '/allocations', {
        'mode': 'automatic', 'expected_active_ids': proposal['expected_active_ids'],
    })
    actual = owner.request('GET', stay + '/actual-stay')[0]
    unit = actual['planned_allocations'][0]['unit_id']
    guest = actual['guests'][0]['id']
    for kind, minutes in (('arrive', 2), ('depart', 1)):
        owner.request('POST', stay + '/actual-stay', {
            'kind': kind, 'occurred_at': (now - timedelta(minutes=minutes)).isoformat(),
            'reason': 'Synthetic observed stay', 'request_id': str(uuid4()),
            'guest_ids': [guest], **({'unit_id': unit} if kind == 'arrive' else {}),
        })
    detail = second.request('GET', stay + '/detail')[0]
    assert detail['reservation']['actual_occupants'] == 0
    assert any(task.get('checkout_observed') for task in detail['cleaning'])
    owner.request('GET', '/api/properties/prop_uat_b/overview', status=404)
    print('Room release passed PostgreSQL readiness, split-session concurrent assignment, actual stay, cleaning and tenant isolation.')


if __name__ == '__main__':
    main()
