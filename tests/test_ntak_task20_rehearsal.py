"""Offline Task 20 rehearsals with normal PMS source capture."""

from datetime import datetime, timedelta, timezone
from decimal import Decimal
from hashlib import sha256
import json

import pytest

import app
import ntak_reporting
from ntak_rehearsal_support import Rehearsal
from ntak_contracts import NAMESPACE, validate
from test_actual_stays import act
from test_business_days import PROP, calendar, close, operating, party, post, setup, snapshot
from test_financial_ledger import charge
from test_flutter_reservation_reception import body, client
from test_guest_reporting_profile import PROFILE
from test_ntak_evidence import ResendMock, package
from test_ntak_reporting import BASE, CONFIG, get
from test_normal_reporting import FACTS


def booking_reports(reservation):
    with app.db() as con:
        return [dict(row) for row in con.execute('''SELECT j.* FROM ntak_jobs j
            JOIN government_outbox o ON o.id=j.id WHERE o.reservation_id=? AND j.operation='reservation'
            ORDER BY j.created_at, j.id''', (reservation,))]


def test_elo_booking_revisions_and_country_gate(client):
    _, units = setup(client)
    assert client.put(BASE, json=CONFIG).status_code == 200
    rehearsal = Rehearsal(client)
    tx = ntak_reporting.datetime.now(timezone.utc).date() + timedelta(days=2)
    start, end = str(tx + timedelta(days=1)), str(tx + timedelta(days=2))
    first = {**body(), 'guest_name': 'Fictional ELO first booking', 'guest_count': 1,
             'arrival_date': start, 'departure_date': end, 'total_huf': 20000, 'reporting': FACTS,
             'allocations': [{'unit_id': units[0][0], 'date_from': start, 'date_to': end}]}
    created = client.post('/api/reservations', json=first)
    assert created.status_code == 200, created.text
    rid = created.json()['id']
    original, = booking_reports(rid)
    fact = json.loads(original['payload_json'])['foglalasEsemeny']
    assert (fact['erkezes'], fact['tavozas'], fact['foglalasBruttoOsszege'], fact['vendegszam']) == (start, end, 20000, 1)
    assert all(fact[key] == FACTS[key] for key in ('garantaltFoglalas', 'vendegKuldoOrszaga', 'ertekesitesiCsatorna', 'piaciSzegmens'))
    [allocation] = client.get(f'/api/reservations/{rid}/allocations').json()['active']
    assert allocation['unit_id'] == units[0][0]
    rehearsal.finish(original['id'])

    changed = client.patch(f'/api/reservations/{rid}', json={
        'arrival_date': str(tx), 'total_huf': 40000, 'reporting': {'garantaltFoglalas': False},
        'allocations': [{'unit_id': units[0][0], 'date_from': str(tx), 'date_to': end}],
    })
    assert changed.status_code == 200, changed.text
    _, revised = booking_reports(rid)
    newer = json.loads(revised['payload_json'])['foglalasEsemeny']
    assert newer['erkezes'] == str(tx) and newer['foglalasBruttoOsszege'] == 40000
    assert newer['garantaltFoglalas'] is False
    assert newer['foglalasiSzam'] == fact['foglalasiSzam'] == rid
    assert newer['foglalasIdopont'] == fact['foglalasIdopont']
    evidence = rehearsal.finish(revised['id'])
    assert any(edge['parent_id'] == original['id'] and edge['child_id'] == revised['id'] for edge in evidence['lineage'])
    assert get(original['id'])['payload_json'] == original['payload_json']
    wrong_property = BASE.replace('prop_flora', 'prop_luna')
    denied = client.post(f'{wrong_property}/jobs/{revised["id"]}/evidence-export', json={'reason': 'Fictional scope probe'})
    assert denied.status_code == 404

    second = {**first, 'guest_name': 'Fictional other foreign guest', 'external_ref': 'TASK20-ELO-05',
              'guest_count': 2, 'total_huf': 28000,
              'allocations': [{'unit_id': units[2][0], 'date_from': start, 'date_to': end}],
              'reporting': {'garantaltFoglalas': False, 'vendegKuldoOrszaga': 'EGYEBKULFOLDI',
                            'ertekesitesiCsatorna': 'KOZVETITO_HAGYOMANYOS', 'piaciSzegmens': 'UZLETI_CSOPORTOS',
                            'expected_guest_count': 2}}
    blocked = client.post('/api/reservations', json=second)
    assert blocked.status_code == 200, blocked.text
    foreign = blocked.json()['id']
    [foreign_original] = booking_reports(foreign)
    assert client.delete(f'/api/reservations/{foreign}').status_code == 200
    assert client.get(f'/api/reservations/{foreign}/allocations').json()['active'] == []
    _, foreign_cancelled = booking_reports(foreign)
    assert get(foreign_original['id'])['payload_json'] == foreign_original['payload_json']
    original_facts = json.loads(foreign_original['payload_json'])
    cancelled_facts = json.loads(foreign_cancelled['payload_json'])
    assert original_facts['source']['status'] == 'confirmed'
    assert cancelled_facts['source'] == {**original_facts['source'], 'status': 'cancelled'}
    assert original_facts['facts']['foglaltLakoegysegek']['foglaltLakoegyseg'] == [
        {'ferohelyKapacitas': 3, 'tipus': 'ECONOMY'}
    ]
    assert cancelled_facts['source']['id'] == foreign
    assert cancelled_facts['facts']['vendegKuldoOrszaga'] == 'EGYEBKULFOLDI'
    assert foreign_original['message_id'] != foreign_cancelled['message_id']

    # Exercise the same cancellation path with an independently reportable
    # booking while preserving the other-foreign booking and its blocker.
    assert client.delete(f'/api/reservations/{rid}').status_code == 200
    assert client.get(f'/api/reservations/{rid}/allocations').json()['active'] == []
    _, _, cancelled = booking_reports(rid)
    cancellation = json.loads(cancelled['payload_json'])['foglalasEsemeny']
    assert cancellation['lemondva'] is True and cancellation['foglalasiSzam'] == rid
    rehearsal.finish(cancelled['id'])

    # A working mock worker leaves both versions of the specified booking gated.
    blocked_export = package(client, foreign_cancelled['id'])
    assert blocked_export.status_code == 200, blocked_export.text
    evidence = blocked_export.json()
    assert {(edge['parent_id'], edge['child_id'], edge['relation']) for edge in evidence['lineage']} == {
        (foreign_original['id'], foreign_cancelled['id'], 'reservation_revision')
    }
    assert {v['job_id'] for v in evidence['versions']} == {foreign_original['id'], foreign_cancelled['id']}
    for version in evidence['versions']:
        assert version['state'] == 'blocked' and version['attempt_count'] == 0
        assert version['error_code'] == 'local_reporting_blocker'
        assert get(version['job_id'])['error_code'] == 'sending_country_contract_unresolved'
        assert version['current_processing_id'] is None and version['message_id'] not in rehearsal.requests
    assert evidence['attempts'] == evidence['events'] == []
    assert not evidence['transmission_enabled'] and not evidence['official_acceptance_confirmed']
    # Room 103 can be sold for the same dates after the cancellation.
    replacement = client.post('/api/reservations', json={**second, 'external_ref': 'TASK20-ELO-REUSE'})
    assert replacement.status_code == 200, replacement.text


@pytest.mark.parametrize('mistaken_arrival', [True, False], ids=['ES_02', 'ES_05'])
def test_mistaken_stay_event_reaches_corrected_daily_close(client, mistaken_arrival):
    _, units = setup(client)
    room = '101' if mistaken_arrival else '103'
    destination = units[0 if mistaken_arrival else 2][0]
    origin = destination if mistaken_arrival else units[1][0]
    day = app.date.today() - timedelta(days=2)
    start = day if mistaken_arrival else day - timedelta(days=2)
    calendar(client, day)
    operating(client, day)
    rate = client.put(f'{PROP}/ifa-rates', json={'effective_from': str(day), 'tax_type': 'TETELES',
                                             'rate': '400', 'reason': 'Fictional rehearsal tax rate'})
    assert rate.status_code == 200, rate.text
    assert client.put(BASE, json=CONFIG).status_code == 200
    rehearsal = Rehearsal(client)
    rid, guests = party(client, start, day + timedelta(days=1), 3 if mistaken_arrival else 2,
                        origin, 'Fictional stay correction party')
    at = datetime.fromisoformat(f'{day}T14:00:00+01:00')
    url = f'/api/reservations/{rid}/actual-stay'

    def report(response, kind, room_number):
        assert response.status_code == 200, response.text
        event_id = response.json()['id']
        with app.db() as con:
            event = con.execute('SELECT * FROM stay_events WHERE id=?', (event_id,)).fetchone()
        job = get(event['reporting_job_id'])
        [payload] = json.loads(job['payload_json'])['esemenyek'][kind]
        assert payload['idopont'] == event['occurred_at']
        assert payload['foglalasiSzam'] == rid
        room_field = 'elfoglaltLakoegyseg' if kind == 'lakoegysegetCserelt' else 'lakoegyseg'
        assert payload[room_field]['szobaszam'] == room_number
        return dict(event), job, {guest['vendegId'] for guest in payload['vendegek']}

    if mistaken_arrival:
        # The group includes one mistakenly arrived guest, as in ES_01A and ES_02.
        wrong_response, _ = act(client, rid, guests, at, uid=origin)
        wrong_kind, opposite, correction = 'erkezett', 'tavozott', 'undo_arrival'
        expected_before = 3
    else:
        # The first guest moves from 102 to 103 on T03, then the second joins on T04.
        for action, at_time, unit, kind, number in (
            ('arrive', at - timedelta(days=2), origin, 'erkezett', '102'),
            ('transfer', at - timedelta(days=1), destination, 'lakoegysegetCserelt', '103'),
        ):
            staged, _ = act(client, rid, guests[:1], at_time, kind=action, uid=unit)
            _, job, _ = report(staged, kind, number)
            rehearsal.finish(job['id'])
        joined, _ = act(client, rid, guests[1:], at, uid=destination)
        _, job, _ = report(joined, 'erkezett', room)
        rehearsal.finish(job['id'])
        at += timedelta(hours=1)
        wrong_response, _ = act(client, rid, guests[:1], at, kind='depart')
        wrong_kind, opposite, correction = 'tavozott', 'erkezett', 'undo_departure'
        expected_before = 1

    wrong, wrong_job, wrong_ids = report(wrong_response, wrong_kind, room)
    rehearsal.finish(wrong_job['id'])
    night = {**charge(in_package=True), 'category': 'SZALLASDIJ', 'subcategory': None,
             'unit_price': '20000', 'vat': '5'}
    post(client, rid, night, day, destination)
    first_close = close(client, day)
    assert first_close.status_code == 200, first_close.text
    original, before, original_payload = snapshot(client, day)
    assert (original['classification'], before['guest_nights'], before['sold_units']) == ('UJ', expected_before, 1)
    rehearsal.finish(original['job_id'])

    affected = guests[-1:] if mistaken_arrival else guests[:1]
    corrected, repeat = act(client, rid, affected, at + timedelta(minutes=1), kind=correction, correction_of=wrong['id'])
    counter, counter_job, counter_ids = report(corrected, opposite, room)
    assert counter['correction_of'] == wrong['id']
    assert counter['business_date'] == wrong['business_date'] == str(day)
    assert len(counter_ids) == 1 and counter_ids <= wrong_ids
    assert (counter_ids < wrong_ids) == mistaken_arrival
    assert get(counter_job['id'])['predecessor_job_id'] == wrong_job['id']
    repeated = client.post(url, json=repeat)
    assert repeated.status_code == 200, repeated.text
    assert repeated.json()['duplicate'] and repeated.json()['id'] == counter['id']
    counter_export = rehearsal.finish(counter_job['id'])
    assert any(e['parent_id'] == wrong_job['id'] and e['child_id'] == counter_job['id']
               for e in counter_export['lineage'])
    versions = {v['job_id']: v for v in counter_export['versions']}
    assert versions[wrong_job['id']]['current_processing_id'] != versions[counter_job['id']]['current_processing_id']
    wrong_property = BASE.replace('prop_flora', 'prop_luna')
    denied = client.post(f'{wrong_property}/jobs/{counter_job["id"]}/evidence-export',
                         json={'reason': 'Fictional scope probe'})
    assert denied.status_code == 404

    overview = client.get(url).json()
    assert [e['id'] for e in overview['events'][-2:]] == [wrong['id'], counter['id']]
    assert overview['actual_occupants'] == 2
    stays = {g['id']: g for g in overview['guests']}
    assert stays[affected[0]]['actual_state'] == ('expected' if mistaken_arrival else 'arrived')
    assert all(stays[g]['occupancy']['unit_id'] == destination for g in guests if g not in affected or not mistaken_arrival)

    assert close(client, day).json()['detail']['code'] == 'closing_correction_reason_required'
    reviewed = close(client, day, 'VENDEG_VAGY_IFA_JAVITAS')
    assert reviewed.status_code == 200, reviewed.text
    revised, after, revised_payload = snapshot(client, day)
    assert (revised['classification'], revised['revision'], after['guest_nights'], after['sold_units']) == ('MODOSITO', 2, 2, 1)
    assert revised['correction_reason'] == 'VENDEG_VAGY_IFA_JAVITAS'

    def daily_ids(payload):
        [night] = payload['napiFeltoltes']['lakoegysegEjszakak']['lakoegysegEjszaka']
        assert night['ertekesitettLakoegyseg']['lakoegyseg']['szobaszam'] == room
        return {g['vendegId'] for g in night['vendegek']['vendeg']}

    old_ids, revised_ids = daily_ids(original_payload), daily_ids(revised_payload)
    assert revised_ids == (old_ids - counter_ids if mistaken_arrival else old_ids | counter_ids)
    daily_export = rehearsal.finish(revised['job_id'])
    assert any(e['parent_id'] == original['job_id'] and e['child_id'] == revised['job_id']
               for e in daily_export['lineage'])
    exported = json.dumps([counter_export, daily_export])
    assert not any(g in exported for g in old_ids | revised_ids)
    assert 'Fictional stay correction party' not in exported
    assert close(client, day).json()['duplicate']
    assert json.loads(get(original['job_id'])['payload_json']) == original_payload
    assert get(wrong_job['id'])['payload_json'] == wrong_job['payload_json']
    with app.db() as con:
        assert con.execute('SELECT encrypted_facts FROM daily_snapshots WHERE id=?', (original['id'],)).fetchone()[0] == original['encrypted_facts']
        assert con.execute('SELECT encrypted_facts FROM stay_events WHERE id=?', (wrong['id'],)).fetchone()[0] == wrong['encrypted_facts']

    if not mistaken_arrival:
        # The room guide has both guests actually depart on T05.
        checkout_at = datetime.fromisoformat(f'{day + timedelta(days=1)}T09:00:00+01:00')
        checkout, _ = act(client, rid, guests, checkout_at, kind='depart')
        final_departure, final_job, final_ids = report(checkout, 'tavozott', room)
        assert final_departure['business_date'] == str(day + timedelta(days=1))
        assert final_departure['correction_of'] is None and final_ids == revised_ids
        rehearsal.finish(final_job['id'])
        assert client.get(url).json()['actual_occupants'] == 0


@pytest.mark.parametrize('warning_case', [False, True], ids=['EU_01', 'EU_02'])
def test_daily_error_reply_and_normal_source_correction(client, warning_case):
    room_type, units = setup(client)
    unit = units[0][0]
    day = app.date.today() - timedelta(days=2)
    calendar(client, day)
    operating(client, day)
    initial_rate = ('SZAZALEKOS', '5') if warning_case else ('TETELES', '400')
    stock_url = f'{PROP}/physical-units/historical-stock/{room_type}'

    def record_stock(count):
        result = client.put(stock_url, json={'business_date': str(day), 'inventory_count': count,
                                             'reason': 'Reconciled fictional room stock for the business date'})
        assert result.status_code == 200, result.text
        return result.json()['revision']

    def rate(kind, value):
        result = client.put(f'{PROP}/ifa-rates', json={'effective_from': str(day), 'tax_type': kind,
                                                       'rate': value, 'reason': 'Fictional rehearsal tax review'})
        assert result.status_code == 200, result.text

    rate(*initial_rate)
    if warning_case:
        # Match the group 4 physical totals and record that day's stock.
        extra_unit = {**units[1][1], 'unit_number': '105', 'reason': 'Fictional capacity discrepancy'}
        extra = client.post(f'{PROP}/physical-units', json=extra_unit)
        assert extra.status_code == 200, extra.text
        extra_id = extra.json()['id']
        assert record_stock(5) == 1
    rid, guests = party(client, day, day + timedelta(days=1), 1, unit, 'Fictional technical correction')

    def profile(postcode, source):
        result = client.put(f'/api/registration/records/{guests[0]}/reporting-profile', json={
            **PROFILE, 'postal_code': postcode, 'ifa_status': 'KOTELES', 'effective_from': str(day),
            'source': source, 'reason': 'Fictional postcode review',
        })
        assert result.status_code == 200, result.text

    profile('1116101' if warning_case else '1116', 'correction')
    arrival = datetime.fromisoformat(f'{day}T14:00:00+01:00')
    assert act(client, rid, guests, arrival, uid=unit)[0].status_code == 200
    night = {**charge(in_package=True), 'category': 'SZALLASDIJ', 'subcategory': None,
             'unit_price': '63000', 'vat': '5'}
    post(client, rid, night, day, unit)
    category, subcategory, before, after = (
        ('ALKOHOLOSITAL', 'PEZSGO', '200001', '2000') if warning_case else ('ETEL', 'REGGELI', '3000000', '3000')
    )
    service = {'category': category, 'subcategory': subcategory, 'vat': '27'}
    service_id = post(client, rid, {**charge(), **service, 'unit_price': before}, day, unit)
    tax = {'category': 'IFA', 'subcategory': None, 'vat': '0'}
    tax_id = post(client, rid, {**charge(), **tax, 'unit_price': '3000' if warning_case else '400'}, day, unit)
    assert client.put(BASE, json=CONFIG).status_code == 200
    closed = close(client, day)
    assert closed.status_code == 200, closed.text
    original, facts, original_payload = snapshot(client, day)
    assert original['classification'] == 'UJ'
    assert Decimal(facts['ifa_obligation_huf']) == (3000 if warning_case else 400)
    assert before in json.dumps(original_payload)
    if warning_case:
        assert original_payload['napiFeltoltes']['szobaAdatok']['osszesSzoba'] == 5
        assert original_payload['napiFeltoltes']['ferohelyAdatok']['osszesFerohelyKapacitas'] == 12
        [comparison] = facts['capacity']['aggregate_comparison']
        assert comparison['historical_stock']['revision'] == 1

    severity = 'warning' if warning_case else 'error'
    diagnostics = [(severity, 'GLOBAL', 'MasodlagosMax' if warning_case else 'ElsodlegesMax', before)]
    if warning_case:
        diagnostics.append(('warning', 'napiFeltoltes.lakoegysegEjszakak[0].vendegek[0].lakohelyIranyitoszam',
                            'IrszHiba', '1116101'))
        diagnostics.append(('warning', 'napiFeltoltes.szobaAdatok.osszesSzoba', 'ElteresRegisztraltAdatokban', '5'))
    rehearsal = Rehearsal(client)
    evidence = rehearsal.finish(original['job_id'], 'review_required' if warning_case else 'rejected',
                                pending=True, diagnostics=diagnostics)
    reported = [issue for attempt in evidence['diagnostics'] for issue in attempt['diagnostics']]
    assert [issue['severity'] for issue in reported] == [severity] * len(diagnostics)
    assert {issue['code'] for issue in reported} == {entry[2] for entry in diagnostics}

    post(client, rid, {**charge(supersedes=service_id), **service, 'unit_price': after}, day, unit)
    if warning_case:
        version = client.put(f'{PROP}/physical-units/{extra_id}', json={
            **extra_unit, 'active': False, 'effective_from': str(day), 'reason': 'Correct fictional inventory',
        })
        assert version.status_code == 200, version.text
        rate('TETELES', '400')
        post(client, rid, {**charge(supersedes=tax_id), **tax, 'unit_price': '400'}, day, unit)
        profile('1116', 'correction')
        mismatch = close(client, day, 'TECH_HIBA_ADATJAVITAS')
        assert mismatch.status_code == 409, mismatch.text
        assert 'physical_inventory_reconciliation_required' in mismatch.json()['detail']['blockers']
        assert record_stock(4) == 2
    result = close(client, day, 'TECH_HIBA_ADATJAVITAS')
    assert result.status_code == 200, result.text
    revised, facts, payload = snapshot(client, day)
    expected = 'MODOSITO' if warning_case else 'UJ'
    assert revised['revision'] == 2 and revised['classification'] == expected
    assert Decimal(facts['ifa_obligation_huf']) == 400
    closing = payload['napiFeltoltes']
    assert closing['napiZarasBesorolas']['besorolas'] == expected
    if warning_case:
        assert closing['napiZarasBesorolas']['indoklas'] == 'TECH_HIBA_ADATJAVITAS'
        assert closing['szobaAdatok']['osszesSzoba'] == 4
        assert closing['ferohelyAdatok']['osszesFerohelyKapacitas'] == 10
        assert closing['lakoegysegEjszakak']['lakoegysegEjszaka'][0]['vendegek']['vendeg'][0]['lakohelyIranyitoszam'] == '1116'
        [comparison] = facts['capacity']['aggregate_comparison']
        assert comparison['historical_stock']['revision'] == 2
        assert comparison['selling_inventory_count'] == 4
    assert after in json.dumps(payload) and before not in json.dumps(payload)
    evidence = rehearsal.finish(revised['job_id'])
    assert any(edge['parent_id'] == original['job_id'] and edge['child_id'] == revised['job_id'] for edge in evidence['lineage'])
    with app.db() as con:
        retained = con.execute('SELECT encrypted_facts FROM daily_snapshots WHERE id=?', (original['id'],)).fetchone()
        assert retained['encrypted_facts'] == original['encrypted_facts']
    assert get(original['job_id'])['payload_json'] == ntak_reporting.dump(original_payload)


def test_eu03_normal_closing_through_resend_and_evidence_export(client):
    _, units = setup(client)
    unit_id = units[2][0]
    day = app.date.today() - timedelta(days=2)
    calendar(client, day)
    operating(client, day)
    rate = client.put(f'{PROP}/ifa-rates', json={
        'effective_from': str(day), 'tax_type': 'TETELES', 'rate': '400',
        'reason': 'Fictional rehearsal tax rate',
    })
    assert rate.status_code == 200, rate.text

    # The fixture uses an already frozen synthetic identity. Task 5 still owns
    # the unconfirmed first-identity normalization rules.
    booking_id, guests = party(client, day, day + timedelta(days=1), 1, unit_id,
                               'Fictional Task 20 guest', frozen=True)
    # DOCX tables 176–177 specify this marker for group 4 only. Seed it in
    # the isolated fixture before any event or closing snapshots are captured.
    marker = '__UJRAKULDENDO_VALIDACIO__'
    with app.db() as con:
        con.execute('UPDATE reservations SET ntak_booking_id=? WHERE id=?', (marker, booking_id))
    profile = client.put(f'/api/registration/records/{guests[0]}/reporting-profile', json={
        **PROFILE, 'effective_from': str(day), 'ifa_status': 'KOTELES',
        'reason': 'Fictional rehearsal tax liability',
    })
    assert profile.status_code == 200, profile.text
    arrival = datetime.fromisoformat(f'{day}T14:00:00+01:00')
    arrived, _ = act(client, booking_id, guests, arrival, uid=unit_id)
    assert arrived.status_code == 200, arrived.text
    for category, amount, vat in [('SZALLASDIJ', '12000', '5'), ('IFA', '400', '0')]:
        entry = charge(in_package=category == 'SZALLASDIJ')
        entry.update(category=category, subcategory=None, unit_price=amount, vat=vat)
        post(client, booking_id, entry, day, unit_id)

    # Enable local preparation after source setup to isolate the closing job.
    settings = client.put(BASE, json=CONFIG)
    assert settings.status_code == 200, settings.text
    closed = close(client, day)
    assert closed.status_code == 200, closed.text
    assert close(client, day).json()['duplicate'] is True
    closed_snapshot, facts, payload = snapshot(client, day)
    assert closed_snapshot['revision'] == 1 and closed_snapshot['blocker'] is None
    assert facts['guest_nights'] == facts['sold_units'] == 1
    assert set(facts['reservations']) == {booking_id}
    assert len(facts['entries']) == 2
    assert Decimal(facts['ifa_obligation_huf']) == 400
    daily = payload['napiFeltoltes']
    assert daily['napiZarasBesorolas'] == {'besorolas': 'UJ'}
    assert Decimal(daily['ifaAdatok']['ifaMertek']) == 400
    assert 'egyebTerhelesek' not in daily

    job = closed_snapshot['job_id']
    original = get(job)
    assert original['state'] == 'ready'
    mock = ResendMock()
    now = ntak_reporting.datetime.now(timezone.utc) + timedelta(minutes=1)
    def run_worker(minutes, state):
        due = now + timedelta(minutes=minutes)
        assert ntak_reporting.worker_once(app.db, transport=mock, now=due) == 1
        assert get(job)['state'] == state

    run_worker(0, 'accepted')
    first_receipt = get(job)['processing_id']
    run_worker(6, 'retry')
    app.init_db()
    run_worker(12, 'accepted')
    run_worker(18, 'succeeded')
    second_receipt = get(job)['processing_id']
    assert first_receipt and second_receipt and first_receipt != second_receipt
    assert get(job)['message_id'] == original['message_id']
    assert [operation for operation, _, _ in mock.calls] == [
        'daily_close', 'verification', 'daily_close', 'verification',
    ]
    assert all(scope == {'property_id': 'prop_flora', 'environment': 'test'} for _, _, scope in mock.calls)
    assert mock.calls[0][1] == mock.calls[2][1]
    sent = validate('daily_close', mock.calls[0][1])
    assert sent.findtext(f'.//{{{NAMESPACE}}}lezartNap') == str(day)
    assert sent.findtext(f'.//{{{NAMESPACE}}}uzenetId') == original['message_id']
    assert [node.text for node in sent.findall(f'.//{{{NAMESPACE}}}foglalasiSzam')] == [marker]
    for index, receipt in [(1, first_receipt), (3, second_receipt)]:
        poll = validate('verification', mock.calls[index][1])
        assert poll.findtext(f'.//{{{NAMESPACE}}}feldolgozasAzonosito') == receipt
    assert snapshot(client, day)[0]['encrypted_facts'] == closed_snapshot['encrypted_facts']

    exported = package(client, job)
    assert exported.status_code == 200, exported.text
    evidence = exported.json()
    assert evidence['root_job_id'] == job
    assert evidence['official_acceptance_confirmed'] is False
    assert evidence['transmission_enabled'] is False
    assert len(evidence['attempts']) == 4
    assert len(evidence['events']) == 12
    for attempt, (_, request, _) in zip(evidence['attempts'], mock.calls, strict=True):
        assert attempt['request_hash'] == sha256(request).hexdigest()
        phases = {event['phase'] for event in evidence['events'] if event['attempt_id'] == attempt['id']}
        assert phases == {'request', 'response', 'outcome'}
    assert {event['processing_id'] for event in evidence['events'] if event.get('processing_id')} == {
        first_receipt, second_receipt,
    }
    assert 'wire_base64' not in exported.text
    assert 'Fictional Task 20 guest' not in exported.text
