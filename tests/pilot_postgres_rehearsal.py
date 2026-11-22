"""One connected synthetic PMS stay against a disposable PostgreSQL deployment."""

from datetime import datetime, time, timedelta
import json
import secrets
import sys
from uuid import uuid4
from zoneinfo import ZoneInfo

from uat_postgres_smoke import LocalAPI, seed, verify_isolation, verify_migrations


def run(app):
    password = secrets.token_urlsafe(24)
    password_hash = app.hash_password(password)
    with app.db() as con:
        seed(app, con, password)
        for identifier, org in [('cleaner-a', 'org_uat_a'), ('other-cleaner-a', 'org_uat_a')]:
            con.execute("""INSERT INTO users(id,organization_id,full_name,email,password_hash,role)
                VALUES (?,?,?,?,?,'cleaner')""",
                (identifier, org, 'Fictional cleaner', identifier + '@uat.invalid', password_hash))

    def login(name):
        client = LocalAPI()
        client.request('POST', '/api/login', {'email': name + '@uat.invalid', 'password': password})
        return client.request

    owner = login('owner-a')
    other = login('owner-b')
    cleaner = login('cleaner-a')
    unassigned = login('other-cleaner-a')
    guest = LocalAPI().request
    property_api = '/api/properties/prop_uat_a'
    ntak = '/api/government/ntak/properties/prop_uat_a'
    viza = '/api/government/viza/properties/prop_uat_a'
    tz = ZoneInfo('Europe/Budapest')
    today = datetime.now(tz).date()
    arrival_day = today - timedelta(days=2)
    actual_checkout_day = today - timedelta(days=1)
    arrival = str(arrival_day)
    checkout = str(actual_checkout_day)
    planned = str(today)
    reason = {'reason': 'Fictional Pilot 01 rehearsal'}

    assert not owner('PUT', ntak, {'enabled': True, 'environment': 'test',
        'registration_id': 'MA99000001', 'provider_vat': '12345678-1-12',
        'software_id': 'FICTIONAL', 'software_version': '1.0'})[0]['transmission_enabled']
    owner('PUT', property_api + '/business-calendar', {'start_date': arrival, 'automatic': False, **reason})
    owner('PUT', property_api + '/ifa-rates', {'effective_from': arrival, 'tax_type': 'TETELES',
                                               'rate': '400', **reason})
    for day in (arrival, checkout):
        owner('PUT', property_api + '/business-days/' + day, {'operating': True, **reason})
    unit = owner('POST', property_api + '/physical-units', {
        'effective_from': arrival, 'room_type_id': 'room_uat', 'building': 'Fictional',
        'unit_number': '101', 'classification': 'APARTMAN',
        'single_beds': 0, 'double_beds': 1, 'extra_beds': 0, **reason,
    })[0]['id']
    booking = {
        'guest_name': 'Fictional Pilot Guest', 'property_id': 'prop_uat_a', 'room_type_id': 'room_uat',
        'source': 'Direct', 'arrival_date': arrival, 'departure_date': planned, 'guest_count': 1,
        'external_ref': 'PILOT-01-SYNTHETIC', 'total_huf': 12400,
        'allocations': [{'unit_id': unit, 'date_from': arrival, 'date_to': planned}],
        'reporting': {'garantaltFoglalas': True, 'vendegKuldoOrszaga': 'HU',
                      'ertekesitesiCsatorna': 'DIREKT_ONLINE', 'piaciSzegmens': 'SZABADIDOS_EGYENI',
                      'expected_guest_count': 1},
    }
    rid = owner('POST', '/api/reservations', booking)[0]['id']
    owner('POST', '/api/reservations', booking, status=409)
    reservation = '/api/reservations/' + rid
    initial = owner('GET', reservation + '/detail')[0]
    assert initial['reservation']['status'] == 'confirmed'
    assert initial['precheckin_invitation']['status'] == 'awaiting_approval'
    oid = initial['precheckin_invitation']['id']
    invite = '/api/communications/outbox/' + oid
    other('POST', invite + '/approve', status=404)
    cleaner('GET', '/api/communications/outbox', status=403)
    owner('POST', invite + '/simulate-send', status=409)
    owner('POST', invite + '/approve', status=403, csrf=False)
    owner('POST', invite + '/approve')
    delivery, headers, _ = owner('POST', invite + '/simulate-send')
    assert not delivery['external_send'] and headers['Cache-Control'] == 'no-store'
    [link] = delivery['links']
    gid = link['guest_record_id']
    token = link['url'].rsplit('/', 1)[1]
    repeated = owner('POST', invite + '/simulate-send')[0]
    assert repeated['duplicate'] and 'links' not in repeated
    assert token.encode() not in owner('GET', '/api/communications/outbox')[2]
    public = '/api/public/checkin/' + token
    guest('GET', public)
    identity = {'full_name': 'Fictional Pilot Guest', 'date_of_birth': '1986-01-02',
                'nationality': 'HU', 'document_type': 'passport', 'document_number': 'PILOT-SYNTHETIC',
                'guest_confirmed': True, 'scan_method': 'manual', 'address': 'Fictional guest address',
                'manual_fields': {'csaladnev': 'Fictional', 'utonev': 'Pilot Guest', 'nem': 'NO',
                                  'allampolgarsagKod': 'HU', 'okmanyTipus': 'UTLEVEL'}}
    guest('POST', public, {**identity, 'document_number': ''}, status=400)
    assert guest('POST', public, identity)[0]['verification_status'] == 'needs_review'
    guest('POST', public, identity, status=410)
    owner('PUT', f'/api/registration/records/{gid}/reporting-profile', {
        'effective_from': arrival, 'country_of_residence': 'HU', 'postal_code': '1011',
        'full_name': identity['full_name'], 'date_of_birth': identity['date_of_birth'], 'birth_place': 'Fictional town',
        'sex': 'NO', 'ifa_status': 'KOTELES', 'nationality_country': 'HU', **reason,
    })
    owner('POST', f'{reservation}/guests/{gid}/verify', {'verification_method': 'in_person'})
    assert owner('PUT', f'/api/registration/records/{gid}/sensitive', {'address': identity['address']})[0]['duplicate']
    assert owner('GET', reservation + '/detail')[0]['reservation']['registration_status'] == 'complete'

    def stay(kind, day, hour):
        return {'request_id': str(uuid4()), 'kind': kind, 'guest_ids': [gid],
                'occurred_at': datetime.combine(day, time(hour), tz).isoformat(), **reason}

    stay_path = reservation + '/actual-stay'
    command = stay('arrive', arrival_day, 15)
    owner('POST', stay_path, command)
    assert owner('GET', stay_path)[0]['actual_occupants'] == 1
    assert next(r for r in owner('GET', '/api/guest-journeys')[0] if r['id'] == rid)['actual_stay_state'] == 'arrived'
    task, = initial['cleaning']
    task_path = '/api/work-tasks/' + task['id']
    cleaner('POST', task_path + '/start', status=409)
    assert next(p for p in owner('GET', '/api/owner/dashboard')[0]['properties']
                if p['id'] == 'prop_uat_a')['state'] == 'occupied'
    command = stay('depart', actual_checkout_day, 9)
    owner('POST', stay_path, command)
    assert owner('POST', stay_path, command)[0]['duplicate']
    assert owner('GET', stay_path)[0]['actual_occupants'] == 0
    assert next(r for r in owner('GET', '/api/guest-journeys')[0] if r['id'] == rid)['actual_stay_state'] == 'departed'
    [task] = owner('GET', reservation + '/detail')[0]['cleaning']
    assert task_path.endswith(task['id']) and (task['scheduled_date'], task['earliest_time']) == (checkout, '09:00')
    assert next(p for p in owner('GET', '/api/owner/dashboard')[0]['properties']
                if p['id'] == 'prop_uat_a')['state'] == 'cleaning'
    unassigned('GET', task_path + '/checklist', status=404)
    owner('PATCH', task_path + '/assignment', {'assigned_to': 'other-cleaner-a'})
    cleaner('POST', task_path + '/start', status=404)
    assert any(t['id'] == task['id'] for t in unassigned('GET', '/api/worker/dashboard')[0]['tasks'])
    unassigned('POST', task_path + '/start')
    unassigned('POST', task_path + '/finish', {'note': ''}, status=409)
    for item in unassigned('GET', task_path + '/checklist')[0]:
        unassigned('PATCH', task_path + '/checklist/' + item['id'], {'completed': True})
    unassigned('POST', task_path + '/finish', {'note': 'Fictional readiness confirmed'})
    unassigned('POST', task_path + '/finish', {'note': 'Replay does not overwrite history'})
    assert next(p for p in owner('GET', '/api/owner/dashboard')[0]['properties']
                if p['id'] == 'prop_uat_a')['state'] == 'ready'

    folio = reservation + '/folio'
    for kind, amount, description, extra in [
            ('charge', '12000', 'Fictional accommodation', {'category': 'SZALLASDIJ', 'vat': '5', 'in_package': True}),
            ('charge', '400', 'Fictional tourist tax', {'category': 'IFA', 'vat': '0', 'guest_id': gid}),
            ('payment', '12400', 'Recorded synthetic cash settlement', {'payment_method': 'KESZPENZ'})]:
        owner('POST', folio, {'request_id': str(uuid4()), 'kind': kind, 'business_date': arrival,
                              'unit_id': unit, 'unit_price': amount, 'description': description, **extra, **reason})
    assert owner('GET', folio)[0]['totals']['balance'] == '0.00'
    first_day = property_api + '/business-days/' + arrival
    assert owner('GET', first_day)[0]['ifa_obligation_huf'] == '400.00'
    for day in (arrival, checkout):
        assert owner('POST', property_api + '/business-days/' + day + '/close', reason)[0]['revision'] == 1

    assert owner('GET', ntak)[0]['transmission_enabled'] is False
    assert owner('GET', viza)[0]['official_transmission_enabled'] is False
    with app.db() as con:
        assert not con.execute('SELECT 1 FROM ntak_jobs WHERE attempts>0').fetchone()
        jobs = con.execute('SELECT blockers_json FROM viza_jobs WHERE property_id=?', ('prop_uat_a',)).fetchall()
        assert jobs and all('official_transmission_disabled' in json.loads(job['blockers_json']) for job in jobs)
        data = con.execute('SELECT document_number,date_of_birth FROM guest_records WHERE id=?', (gid,)).fetchone()
        assert data['document_number'] is None and data['date_of_birth'] is None
    print('PostgreSQL stay passed: invitation, pre-check-in, review, arrival, checkout, cleaning, folio, IFA and daily closes.')


def main():
    database = verify_isolation()
    import app
    verify_migrations(app, database)
    assert LocalAPI().request('GET', '/health/ready')[0] == {
        'status': 'ready', 'database': 'postgresql', 'schema_version': 3090,
    }
    if sys.argv[1:] == ['--restart']:
        with app.db() as con:
            assert con.execute("""SELECT 1 FROM communication_outbox
                WHERE message_type=? AND status='simulated_sent'""", (app.CHECKIN_INVITATION,)).fetchone()
            assert con.execute("""SELECT 1 FROM work_tasks
                WHERE status='complete' AND worker_note='Fictional readiness confirmed'""").fetchone()
            snapshots = con.execute('SELECT encrypted_facts FROM daily_snapshots').fetchall()
            assert len(snapshots) == 2 and all(app.decrypt_json(row['encrypted_facts']) for row in snapshots)
        print('Application restart preserved the simulated invitation, completed cleaning and both encrypted closings.')
    else:
        run(app)


if __name__ == '__main__':
    main()
