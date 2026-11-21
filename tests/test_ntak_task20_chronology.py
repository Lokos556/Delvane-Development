"""Shared-property offline rehearsal of the v1.07 NTAK validation calendar."""

from datetime import timedelta, timezone
from decimal import Decimal
from pathlib import Path
import json

import app
import financial_ledger
import guest_reporting
import ntak_reporting
import testing_clock
from ntak_contracts import NAMESPACE, validate
from ntak_rehearsal_support import Rehearsal
from test_actual_stays import act
from test_business_days import PROP, calendar, close, operating, party, post, setup, snapshot
from test_day_use import make
from test_financial_ledger import charge, payment
from test_flutter_reservation_reception import body, client, login
from test_guest_reporting_profile import PROFILE
from test_ntak_evidence import ResendMock, package
from test_ntak_reporting import BASE, CONFIG, get
from test_ntak_task20_rehearsal import booking_reports
from test_normal_reporting import FACTS


def ok(response):
    assert response.status_code == 200, response.text
    return response.json()


def rate(client, day, kind='TETELES', amount='400'):
    ok(client.put(f'{PROP}/ifa-rates', json={
        'effective_from': str(day), 'tax_type': kind, 'rate': amount, 'reason': 'Synthetic tax review',
    }))


def profile(client, guest, day, **fields):
    ok(client.put(f'/api/registration/records/{guest}/reporting-profile', json={
        **PROFILE, 'effective_from': str(day), 'reason': 'Synthetic guest review', **fields,
    }))


def guest_records(reservation):
    with app.db() as con:
        return [row['id'] for row in con.execute(
            'SELECT id FROM guest_records WHERE reservation_id=? ORDER BY id', (reservation,)
        )]


def freeze(guest):
    with app.db() as con:
        guest_reporting.identity_for_submission(
            app, con, 'org_casa_rosa', 'prop_flora', guest,
            canonical_identity='Synthetic ' + guest + ' Budapest 1986.01.01.',
        )


def lodging(client, reservation, day, unit, value):
    return post(client, reservation, {
        **charge(in_package=True), 'category': 'SZALLASDIJ', 'subcategory': None, 'vat': '5', 'unit_price': value,
    }, day, unit)


def ntak_guests(payload):
    return {
        guest['vendegId']: guest
        for unit_night in payload['lakoegysegEjszakak']['lakoegysegEjszaka']
        for guest in unit_night['vendegek']['vendeg']
    }


def test_task20_shared_validation_calendar(client, monkeypatch):
    room_type, units = setup(client)
    room101, room102, room103, room104 = [unit[0] for unit in units]
    tx = app.date.today()
    original_clock = testing_clock.TEST_NOW
    t01, t02, t03, t04, t05 = [tx - timedelta(days=days) for days in (5, 4, 3, 2, 1)]
    tx1, tx2, ty = [tx + timedelta(days=days) for days in (1, 2, 3)]
    monkeypatch.setattr(ntak_reporting, 'datetime', app.datetime)
    ok(client.put(BASE, json=CONFIG))
    # Model the existing local side of a mapped channel without provider access.
    channel_id = 'task20-fictional-channel'
    with app.db() as con:
        con.execute('''INSERT INTO integrations(id,organization_id,property_id,provider,connection_type,
            status,public_config_json,created_at,updated_at) VALUES (?,'org_casa_rosa','prop_flora',
            'Booking.com','Synthetic channel','connected',?,?,?)''', (channel_id, json.dumps({
            'adapter': 'channex_channel_manager', 'provider_property_id': 'synthetic-property',
            'channex_room_type_id': 'synthetic-room',
        }), app.now_iso(), app.now_iso()))
    rehearsal = Rehearsal(client)
    calendar(client, t01)
    operating(client, t01, False)
    rate(client, t02)
    for day in (t02, t03, t04, t05):
        operating(client, day)

    def event(reservation, guests, day, hour, kind='arrive', unit=None, correction=None):
        timestamp = app.datetime.fromisoformat(f'{day}T{hour}:00+01:00')
        response, _ = act(client, reservation, guests, timestamp, kind=kind, uid=unit, correction_of=correction)
        event_id = ok(response)['id']
        with app.db() as con:
            saved = con.execute('SELECT * FROM stay_events WHERE id=?', (event_id,)).fetchone()
        assert saved['business_date'] == str(day) and saved['correction_of'] == correction
        job = get(saved['reporting_job_id'])
        [(report_kind, [fact])] = json.loads(job['payload_json'])['esemenyek'].items()
        assert report_kind == {
            'arrive': 'erkezett', 'depart': 'tavozott', 'transfer': 'lakoegysegetCserelt',
            'undo_arrival': 'tavozott', 'undo_departure': 'erkezett',
        }[kind]
        assert fact['foglalasiSzam'] == reservation
        rehearsal.finish(job['id'])
        return event_id, fact

    def closed(day, nights, sold, *, reason=None, state='succeeded', diagnostics=()):
        result = ok(close(client, day, reason))
        version, facts, payload = snapshot(client, day)
        assert result['job_id'] == version['job_id']
        assert (facts['guest_nights'], facts['sold_units']) == (nights, sold), facts['groups']
        evidence = rehearsal.finish(version['job_id'], state, pending=bool(diagnostics), diagnostics=diagnostics)
        return version, facts, payload['napiFeltoltes'], evidence

    def immutable(version, revised, evidence):
        assert any(edge['parent_id'] == version['job_id'] and edge['child_id'] == revised['job_id']
                   for edge in evidence['lineage'])
        with app.db() as con:
            original = con.execute('SELECT encrypted_facts FROM daily_snapshots WHERE id=?', (version['id'],)).fetchone()
        assert original['encrypted_facts'] == version['encrypted_facts']

    # The advance-booking cases and the later error cases share FOGL_04.
    def advance(label, unit, amount, count, facts):
        result = ok(client.post('/api/reservations', json={
            **body(), 'guest_name': 'Synthetic ' + label, 'external_ref': label,
            'arrival_date': str(tx1), 'departure_date': str(tx2), 'guest_count': count,
            'total_huf': amount, 'reporting': facts,
            'allocations': [{'unit_id': unit, 'date_from': str(tx1), 'date_to': str(tx2)}],
        }))
        return result['id'], booking_reports(result['id'])[0]

    fourth, advance_report = advance('FOGL_04', room101, 20000, 1, FACTS)
    rehearsal.finish(advance_report['id'])
    fifth, blocked_report = advance('FOGL_05', room103, 28000, 2, {
        'garantaltFoglalas': False, 'vendegKuldoOrszaga': 'EGYEBKULFOLDI',
        'ertekesitesiCsatorna': 'KOZVETITO_HAGYOMANYOS', 'piaciSzegmens': 'UZLETI_CSOPORTOS',
    })
    ok(client.patch(f'/api/reservations/{fourth}', json={
        'arrival_date': str(tx), 'total_huf': 40000, 'reporting': {'garantaltFoglalas': False},
        'allocations': [{'unit_id': room101, 'date_from': str(tx), 'date_to': str(tx2)}],
    }))
    _, revised_booking = booking_reports(fourth)
    booking_proof = rehearsal.finish(revised_booking['id'])
    assert {entry['job_id'] for entry in booking_proof['versions']} == {advance_report['id'], revised_booking['id']}
    revised = json.loads(revised_booking['payload_json'])['foglalasEsemeny']
    assert (revised['foglalasiSzam'], revised['erkezes'], revised['foglalasBruttoOsszege']) == (fourth, str(tx), 40000)
    ok(client.delete(f'/api/reservations/{fifth}'))
    assert ok(client.get(f'/api/reservations/{fifth}/allocations'))['active'] == []
    _, blocked_cancel = booking_reports(fifth)
    for job in (blocked_report, blocked_cancel):
        assert job['error_code'] == 'sending_country_contract_unresolved' and job['attempts'] == 0

    # T01–T05 are consecutive and have shared bookings and actual occupancy.
    _, _, closed_property, _ = closed(t01, 0, 0)
    assert closed_property['szobaAdatok']['oooSzobak'] == 4
    for unit, state in ((room103, 'OOO'), (room104, 'OOS')):
        ok(client.post(f'{PROP}/physical-units/{unit}/periods', json={
            'state': state, 'date_from': str(t02), 'date_to': str(t02), 'reason': 'Synthetic maintenance',
        }))
    first, first_party = party(client, t02, t04, 3, room101, 'Synthetic FOGL_01')
    second, (first_arrival, later_arrival) = party(client, t02, t05, 2, room102, 'Synthetic FOGL_02')
    initial, group = event(first, first_party, t02, '14:00', unit=room101)
    _, counter = event(first, first_party[-1:], t02, '14:01', 'undo_arrival', correction=initial)
    _, arrival = event(second, [first_arrival], t02, '14:02', unit=room102)
    group_ids = {guest['vendegId'] for guest in group['vendegek']}
    withdrawn = counter['vendegek'][0]['vendegId']
    continuing = arrival['vendegek'][0]['vendegId']
    assert withdrawn in group_ids and len(group_ids) == 3
    lodging(client, first, t02, room101, '20000')
    lodging(client, second, t02, room102, '25000')
    for category, subcategory, vat, value in (
        ('KOZFURDO', 'FURDO_PROGRAM', '18', '5800'), ('ETEL', 'FOETEL', '5', '4600'),
        ('EGYEB', 'EGYEB_VENDEGLATAS', '27', '1000'), ('ALKOHOLOSITAL', 'ITALCSOMAG', '27', '10000'),
    ):
        ok(client.post(f'{PROP}/financial-entries', json={
            **charge(), 'category': category, 'subcategory': subcategory, 'vat': vat,
            'unit_price': value, 'business_date': str(t02),
        }))
    ok(client.post(f'{PROP}/financial-entries', json={**payment('BANKKARTYA', '21400'), 'business_date': str(t02)}))
    _, _, report02, _ = closed(t02, 3, 2)
    expected_ids = (group_ids - {withdrawn}) | {continuing}
    assert set(ntak_guests(report02)) == expected_ids
    assert report02['szobaAdatok']['oooSzobak'] == report02['szobaAdatok']['oosSzobak'] == 1
    assert sum(Decimal(line['osszeg']) for line in report02['egyebTerhelesek']['egyebTerheles']) == 21400

    _, moved = event(second, [first_arrival], t03, '14:00', 'transfer', room103)
    assert (moved['elhagyottLakoegyseg']['szobaszam'], moved['elfoglaltLakoegyseg']['szobaszam']) == ('102', '103')
    assert moved['vendegek'][0]['vendegId'] == continuing
    workbook_lines = json.loads((Path(__file__).parent / 'fixtures/ntak_official_charge_lines.json').read_text(encoding='utf8'))
    for line in workbook_lines:
        post(client, second, {**charge(), 'category': line['category'], 'subcategory': line['subcategory'],
                              'vat': line['vat'], 'in_package': line['in_package'], 'unit_price': line['amount']}, t03, room103)
    for method in financial_ledger.enum('KoltesTipusType'):
        post(client, second, payment(method, '4066' if method in ('UTOLAGOS', 'EGYEB') else '4067'), t03, room103)
    _, day03, report03, _ = closed(t03, 3, 2)
    assert set(ntak_guests(report03)) == expected_ids
    assert day03['totals']['charges'] == day03['totals']['payments'] == '28467.00'
    assert len(day03['entries']) == 76

    _, departed = event(first, first_party[:2], t04, '09:30', 'depart')
    assert {guest['vendegId'] for guest in departed['vendegek']} == group_ids - {withdrawn}
    profile(client, later_arrival, t04, date_of_birth='1986-01-01', ifa_status='KOTELES')
    _, joined = event(second, [later_arrival], t04, '14:00', unit=room103)
    joined_id = joined['vendegek'][0]['vendegId']
    mistaken, _ = event(second, [first_arrival], t04, '15:00', 'depart')
    _, returned = event(second, [first_arrival], t04, '15:01', 'undo_departure', correction=mistaken)
    assert returned['vendegek'][0]['vendegId'] == continuing
    lodging(client, second, t04, room103, '28000')
    tax = {'category': 'IFA', 'subcategory': None, 'vat': '0', 'unit_price': '400', 'guest_id': later_arrival}
    tax_id = post(client, second, {**charge(), **tax}, t04, room103)
    old04, before04, report04, _ = closed(t04, 2, 1)
    assert before04['ifa_obligation_huf'] == '400.00'
    assert ntak_guests(report04)[joined_id]['szuletesiEv'] == 1986
    profile(client, later_arrival, t04, date_of_birth='1987-02-11', ifa_status='im5', source='correction')
    post(client, second, {**charge(supersedes=tax_id, voided=True), **tax}, t04, room103)
    new04, after04, revised04, evidence04 = closed(t04, 2, 1, reason='VENDEG_VAGY_IFA_JAVITAS')
    assert new04['classification'] == 'MODOSITO' and after04['ifa_obligation_huf'] == '0.00'
    corrected = ntak_guests(revised04)
    assert set(corrected) == {joined_id, continuing} and corrected[joined_id]['szuletesiEv'] == 1987
    immutable(old04, new04, evidence04)

    _, checkout = event(second, [first_arrival, later_arrival], t05, '09:00', 'depart')
    assert {guest['vendegId'] for guest in checkout['vendegek']} == {joined_id, continuing}
    created, _ = make(client, units[2:], offset=-1)
    third = ok(created)['id']
    ok(client.patch(f'/api/reservations/{third}', json={'reporting': {
        'piaciSzegmens': 'ISMERETLEN', 'ertekesitesiCsatorna': 'KOZVETITO_ONLINE',
    }}))
    for guest, unit, value, method in zip(guest_records(third), (room103, room104), ('28000', '34500'), ('KESZPENZ', 'BANKKARTYA'), strict=True):
        profile(client, guest, t05, nationality_country='HU', ifa_status='im1')
        freeze(guest)
        _, day_arrival = event(third, [guest], t05, '10:30', unit=unit)
        _, day_departure = event(third, [guest], t05, '11:30', 'depart')
        assert day_arrival['vendegek'] == day_departure['vendegek']
        lodging(client, third, t05, unit, value)
        post(client, third, payment(method, value), t05, unit)
    post(client, first, {**charge(), 'category': 'EGYEB', 'subcategory': 'EGYEB', 'unit_price': '10000'}, t05)
    post(client, first, payment('BANKKARTYA', '10000', document_date=str(t05)), t05)
    _, day05, report05, _ = closed(t05, 0, 0)
    assert day05['totals']['charges'] == day05['totals']['payments'] == '72500.00'
    for block in ('tartozkodastKovetoTerhelesek', 'tartozkodastKovetoKoltesek'):
        assert first in json.dumps(report05[block])

    # Workbook Adatok has one more physical guest than the advance estimate.
    ok(client.patch(f'/api/reservations/{fourth}', json={'guest_count': 2}))
    booked, warned = guest_records(fourth)
    profile(client, booked, tx, nationality_country='HU', ifa_status='KOTELES')
    profile(client, warned, tx1, nationality_country='HU', ifa_status='KOTELES', postal_code='1116101')
    freeze(booked)
    freeze(warned)
    if (updated := booking_reports(fourth)[-1])['id'] != revised_booking['id']:
        rehearsal.finish(updated['id'])

    monkeypatch.setattr(testing_clock, 'TEST_NOW', original_clock + timedelta(days=1))
    operating(client, tx)
    event(fourth, [booked], tx, '14:00', unit=room101)
    lodging(client, fourth, tx, room101, '20000')
    breakfast = {'category': 'ETEL', 'subcategory': 'REGGELI', 'vat': '27'}
    overcharge = post(client, fourth, {**charge(), **breakfast, 'unit_price': '3000000'}, tx, room101)
    post(client, fourth, {**charge(), **tax, 'guest_id': booked}, tx, room101)
    old_tx, _, _, _ = closed(tx, 1, 1, state='rejected', diagnostics=[
        ('error', 'GLOBAL', 'ElsodlegesMax', '3000000'),
    ])
    post(client, fourth, {**charge(supersedes=overcharge), **breakfast, 'unit_price': '3000'}, tx, room101)
    new_tx, _, _, proof_tx = closed(tx, 1, 1, reason='TECH_HIBA_ADATJAVITAS')
    assert old_tx['classification'] == new_tx['classification'] == 'UJ'
    immutable(old_tx, new_tx, proof_tx)

    monkeypatch.setattr(testing_clock, 'TEST_NOW', original_clock + timedelta(days=2))
    operating(client, tx1)
    event(fourth, [warned], tx1, '14:00', unit=room101)
    rate(client, tx1, 'SZAZALEKOS', '5')
    extra = {**units[1][1], 'unit_number': '105', 'effective_from': str(tx), 'reason': 'Synthetic stock discrepancy'}
    extra_id = ok(client.post(f'{PROP}/physical-units', json=extra))['id']
    stock_url = f'{PROP}/physical-units/historical-stock/{room_type}'

    def stock(count):
        return ok(client.put(stock_url, json={
            'business_date': str(tx1), 'inventory_count': count, 'reason': 'Synthetic stock correction',
        }))['revision']

    assert stock(5) == 1
    lodging(client, fourth, tx1, room101, '60000')
    champagne = {'category': 'ALKOHOLOSITAL', 'subcategory': 'PEZSGO', 'vat': '27'}
    excess = post(client, fourth, {**charge(), **champagne, 'unit_price': '200001'}, tx1, room101)
    shown_tax = post(client, fourth, {**charge(), **tax, 'unit_price': '3000', 'guest_id': warned}, tx1, room101)
    old_tx1, _, report_tx1, _ = closed(tx1, 2, 1, state='review_required', diagnostics=[
        ('warning', 'GLOBAL', 'MasodlagosMax', '200001'),
        ('warning', 'napiFeltoltes.lakoegysegEjszakak[0].vendegek[0].lakohelyIranyitoszam', 'IrszHiba', '1116101'),
        ('warning', 'napiFeltoltes.szobaAdatok.osszesSzoba', 'ElteresRegisztraltAdatokban', '5'),
    ])
    assert report_tx1['szobaAdatok']['osszesSzoba'] == 5
    assert report_tx1['ferohelyAdatok']['osszesFerohelyKapacitas'] == 12
    ok(client.put(f'{PROP}/physical-units/{extra_id}', json={**extra, 'active': False, 'effective_from': str(tx1)}))

    def selling_stock():
        with app.db() as con:
            published = con.execute('''SELECT reservation_availability,availability FROM channex_room_type_values
                WHERE integration_id=? AND room_type_id=? AND stay_date=?''', (channel_id, room_type, str(tx1))).fetchone()
            return (
                app._reservation_availability(con, 'org_casa_rosa', 'prop_flora', tx1, room_type),
                tuple(published),
                con.execute('SELECT COUNT(*) FROM channel_ari_outbox WHERE integration_id=?', (channel_id,)).fetchone()[0],
            )

    before_stock = selling_stock()
    assert before_stock[:2] == (3, (3, 3)) and before_stock[2] > 0
    assert stock(4) == 2
    assert selling_stock() == before_stock
    rate(client, tx1)
    post(client, fourth, {**charge(supersedes=excess), **champagne, 'unit_price': '2000'}, tx1, room101)
    post(client, fourth, {**charge(supersedes=shown_tax), **tax, 'guest_id': warned}, tx1, room101)
    profile(client, warned, tx1, nationality_country='HU', ifa_status='KOTELES', postal_code='1116', source='correction')
    new_tx1, _, revised_tx1, proof_tx1 = closed(tx1, 2, 1, reason='TECH_HIBA_ADATJAVITAS')
    assert new_tx1['classification'] == 'MODOSITO'
    assert revised_tx1['szobaAdatok']['osszesSzoba'] == 4
    assert revised_tx1['ferohelyAdatok']['osszesFerohelyKapacitas'] == 10
    assert selling_stock() == before_stock
    immutable(old_tx1, new_tx1, proof_tx1)
    assert snapshot(client, tx)[0]['encrypted_facts'] == new_tx['encrypted_facts']

    # TX+2 bridges the PMS's calendar to an otherwise unused TY.
    monkeypatch.setattr(testing_clock, 'TEST_NOW', original_clock + timedelta(days=4))
    operating(client, tx2)
    event(fourth, [booked, warned], tx2, '09:00', 'depart')
    closed(tx2, 0, 0)
    operating(client, ty)
    marker = '__UJRAKULDENDO_VALIDACIO__'
    resend_booking, resend_guests = party(client, ty, ty + timedelta(days=1), 1, room103, 'Synthetic TY')
    # Group 4's literal marker is fixture-only. The normal stay report still uses
    # its native booking ID before the marker is applied to the closing fixture.
    event(resend_booking, resend_guests, ty, '14:00', unit=room103)
    with app.db() as con:
        con.execute('UPDATE reservations SET ntak_booking_id=? WHERE id=?', (marker, resend_booking))
    lodging(client, resend_booking, ty, room103, '12000')
    ty_job = ok(close(client, ty))['job_id']
    ty_snapshot = snapshot(client, ty)[0]
    mock = ResendMock()
    step = rehearsal.now + timedelta(minutes=6)
    message = get(ty_job)['message_id']
    receipts = []
    for interval, state in ((0, 'accepted'), (6, 'retry'), (12, 'accepted'), (18, 'succeeded')):
        assert ntak_reporting.worker_once(app.db, transport=mock, now=step + timedelta(minutes=interval)) == 1
        current = get(ty_job)
        assert current['state'] == state and current['message_id'] == message
        if state == 'accepted':
            receipts.append(current['processing_id'])
        if state == 'retry':
            app.init_db()
    assert len(set(receipts)) == 2 and mock.calls[0][1] == mock.calls[2][1]
    ty_request = validate('daily_close', mock.calls[0][1])
    assert [node.text for node in ty_request.findall(f'.//{{{NAMESPACE}}}foglalasiSzam')] == [marker]
    proof = ok(package(client, ty_job))
    assert {attempt['processing_id'] for attempt in proof['events'] if attempt.get('processing_id')} == set(receipts)
    assert snapshot(client, ty)[0]['encrypted_facts'] == ty_snapshot['encrypted_facts']
    assert not proof['official_acceptance_confirmed'] and not proof['transmission_enabled']
    preview = ok(client.post(f'/api/government/ntak/preview/{fourth}'))
    validate('information', preview['ntak_xml'].encode())
    assert preview['transport'] == 'awaiting_official_test_package' and not preview['readiness']['ready']
    assert not any(operation == 'information' for calls in rehearsal.requests.values() for operation, _ in calls)
    assert client.post(BASE.replace('prop_flora', 'prop_luna') + f'/jobs/{ty_job}/evidence-export',
                       json={'reason': 'Synthetic scope probe'}).status_code == 404
    login(client, 'cleaner')
    assert package(client, ty_job).status_code == 403
    for job in (blocked_report, blocked_cancel):
        assert get(job['id'])['state'] == 'blocked' and get(job['id'])['attempts'] == 0
