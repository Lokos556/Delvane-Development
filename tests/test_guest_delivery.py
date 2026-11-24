from concurrent.futures import ThreadPoolExecutor
from datetime import timedelta
import hashlib
import hmac
import json
from threading import Lock
import time

from fastapi.testclient import TestClient
import pytest

import app
import guest_delivery as delivery
from test_flutter_reservation_reception import body, client, login
from testing_clock import FixedDatetime


ORIGIN = 'https://guest.example.com'
RECIPIENT = 'fictional-guest@pilot.invalid'
SECRET = 'synthetic-receipt-secret-for-tests-only'


class FakeProvider:
    name = 'pilot-fake'
    test_mode = True

    def __init__(self):
        self.calls = []
        self.messages = {}
        self.failure = None
        self.lock = Lock()

    def send(self, *, key, sender, recipient, links):
        assert recipient.endswith('@pilot.invalid')
        with self.lock:
            self.calls.append(key)
            if self.failure:
                error, self.failure = self.failure, None
                raise error
            self.messages.setdefault(key, (recipient, links))
        return 'mock-' + key


@pytest.fixture
def provider(client, monkeypatch):
    for key, value in {
        'DELVANE_GUEST_EMAIL_ENABLED': '1',
        'DELVANE_GUEST_PUBLIC_ORIGIN': ORIGIN,
        'DELVANE_GUEST_EMAIL_FROM': 'fictional-sender@pilot.invalid',
        'DELVANE_GUEST_RECEIPT_SECRET': SECRET,
        'DELVANE_GUEST_RETRY_BASE_SECONDS': '300',
    }.items():
        monkeypatch.setenv(key, value)
    fake = FakeProvider()
    monkeypatch.setattr(app.app.state, 'guest_email_provider', fake, raising=False)
    return fake


def booking(client, *, days=0, recipient=RECIPIENT):
    document = body()
    for field in ('arrival_date', 'departure_date'):
        document[field] = str(app.date.fromisoformat(document[field]) + timedelta(days=days))
    document.update(guest_count=1, invitation_email=recipient)
    result = client.post('/api/reservations', json=document)
    assert result.status_code == 200, result.text
    path = '/api/reservations/' + result.json()['id']
    outbox = client.get(path + '/detail').json()['precheckin_invitation']['id']
    return path, outbox, '/api/communications/outbox/' + outbox


def owner_state(client, reservation):
    return client.get(reservation + '/detail').json()['precheckin_invitation']['delivery']


def signed(public, outbox, event, state, *, message=None, signed_with=SECRET, seconds_ago=0):
    raw = json.dumps(dict(event_id=event, outbox_id=outbox, message_id=message or 'mock-' + outbox,
                          state=state)).encode()
    timestamp = str(int(time.time()) - seconds_ago)
    signature = hmac.new(signed_with.encode(), timestamp.encode() + b'.' + raw, hashlib.sha256).hexdigest()
    return public.post(delivery.RECEIPT_PATH, content=raw,
                       headers={'X-Delvane-Timestamp': timestamp, 'X-Delvane-Signature': signature})


def test_normal_operator_delivery_receipts_and_registration(client, provider):
    login(client)
    reservation, oid, invite = booking(client)
    assert client.get('/api/reception/summary').json()['guest_email_available']
    assert client.post(invite + '/approve').json()['delivery']['state'] == 'queued'
    assert client.post(invite + '/approve').json()['delivery']['attempts'] == 0
    with app.db() as con:
        row = delivery.get(con, oid)
        encrypted = row['encrypted_envelope']
        assert RECIPIENT not in encrypted and ORIGIN not in encrypted
        assert app.decrypt_json(encrypted)['recipient'] == RECIPIENT
        assert con.execute('SELECT COUNT(*) n FROM guest_invitation_delivery_events WHERE outbox_id=?',
                           (oid,)).fetchone()['n'] == 1
    assert client.post(invite + '/simulate-send').status_code == 409

    provider.failure = delivery.SendFailure('provider_unavailable', retryable=True)
    driver = delivery.active(app)
    with ThreadPoolExecutor(max_workers=2) as workers:
        assert sorted(workers.map(lambda _: delivery.worker_once(app, driver), range(2))) == [False, True]
    retry = owner_state(client, reservation)
    assert retry['state'] == 'retry_scheduled' and retry['attempts'] == 1
    assert retry['next_attempt_at'] > retry['last_attempt_at'] and retry['can_retry']
    assert not delivery.worker_once(app, driver)
    csrf = client.headers.pop('X-Rosa-CSRF')
    assert client.post(invite + '/retry').status_code == 403
    client.headers['X-Rosa-CSRF'] = csrf
    assert client.post(invite + '/retry').status_code == 200
    assert delivery.worker_once(app, delivery.active(app))
    assert provider.calls == [oid, oid]
    accepted = owner_state(client, reservation)
    assert accepted['state'] == 'provider_accepted' and accepted['delivered_at'] is None
    [link] = provider.messages[oid][1]
    token = link.rsplit('/', 1)[1]
    assert link.startswith(ORIGIN + '/guest/checkin/')
    for path in ('/api/communications/outbox', reservation + '/detail'):
        document = client.get(path).text
        assert all(fragment not in document for fragment in (token, RECIPIENT, 'mock-' + oid))

    public = TestClient(app.app, base_url=ORIGIN)
    try:
        assert public.get('/health/live').status_code == 404
        assert public.post('/api/login', json={}).status_code == 404
        assert public.get('/docs').status_code == 404
        assert public.get('/static/index.html').status_code == 404
        page = public.get('/guest/checkin/' + token)
        assert page.status_code == 200
        assert 'https://cdn.jsdelivr.net' not in page.headers['content-security-policy']
        assert signed(public, oid, 'one', 'delivered', signed_with='wrong-secret').status_code == 401
        assert signed(public, oid, 'one', 'delivered', seconds_ago=600).status_code == 401
        assert signed(public, oid, 'one', 'delivered', message='wrong-message').status_code == 409
        assert signed(public, oid, 'one', 'delivered').json() == {'ok': True, 'duplicate': False}
        assert signed(public, oid, 'one', 'delivered').json() == {'ok': True, 'duplicate': True}
        assert signed(public, oid, 'one', 'accepted').status_code == 409
        assert signed(public, oid, 'two', 'accepted').status_code == 200
        assert signed(public, oid, 'three', 'bounced').status_code == 200
        confirmed = owner_state(client, reservation)
        assert confirmed['state'] == 'delivered' and confirmed['delivered_at']
        assert confirmed['attempts'] == 2 and not confirmed['can_retry']
        guest = '/api/public/checkin/' + token
        response = public.get(guest)
        assert response.status_code == 200
        assert response.headers['cache-control'] == 'no-store'
        assert response.headers['referrer-policy'] == 'no-referrer'
        details = {'full_name': 'Fictional Delivery Guest', 'date_of_birth': '1986-01-02',
                   'nationality': 'HU', 'document_type': 'passport', 'document_number': 'FAKE-INVITE',
                   'guest_confirmed': True, 'scan_method': 'manual', 'address': 'Fictional address'}
        assert public.post(guest, json=details).json()['verification_status'] == 'needs_review'
        assert public.post(guest, json=details).status_code == 410
    finally:
        public.close()
    with app.db() as con:
        assert delivery.get(con, oid)['encrypted_envelope'] is None
        assert con.execute('SELECT COUNT(*) n FROM guest_invitation_delivery_events WHERE provider_event_id IS NOT NULL',
                           ()).fetchone()['n'] == 3


def test_two_guest_workspace_keeps_submission_verification_and_delivery_separate(client, provider):
    login(client)
    document = body()
    document.update(guest_count=2, invitation_email=RECIPIENT)
    created = client.post('/api/reservations', json=document)
    assert created.status_code == 200, created.text
    reservation = '/api/reservations/' + created.json()['id']
    detail = client.get(reservation + '/detail').json()
    oid = detail['precheckin_invitation']['id']
    invite = '/api/communications/outbox/' + oid
    status = reservation + '/guest-checkin-status'
    assert {g['registration_stage'] for g in client.get(status).json()['guests']} == {'awaiting_invitation'}

    assert client.post(invite + '/approve').status_code == 200
    assert delivery.worker_once(app, delivery.active(app))
    links = provider.messages[oid][1]
    assert len(links) == len(set(links)) == 2
    assert {g['registration_stage'] for g in client.get(status).json()['guests']} == {'awaiting_registration'}
    public = TestClient(app.app, base_url=ORIGIN)
    try:
        guest_endpoints = ['/api/public/checkin/' + link.rsplit('/', 1)[1] for link in links]
        first, second = [public.get(path).json()['guest']['id'] for path in guest_endpoints]
        assert first != second
        assert signed(public, oid, 'fictional-confirmation', 'delivered').status_code == 200
        submitted = {
            'full_name': 'de la Cruz Anna Mária', 'date_of_birth': '1988-02-29',
            'birth_place': 'Szeged', 'sex': 'F', 'nationality': 'Dutch', 'document_type': 'passport',
            'document_number': 'FAKE-WORKSPACE-01', 'address': 'Fictional residence address',
            'guest_confirmed': True, 'manual_fields': {'allampolgarsagKod': 'NLD'},
        }
        response = public.post(guest_endpoints[0], json=submitted)
        assert response.status_code == 200, response.text
        assert response.json()['verification_status'] == 'needs_review'
        assert public.get(guest_endpoints[0]).status_code == 410
        assert public.get(guest_endpoints[1]).status_code == 200
        path = f'/api/registration/records/{first}/workspace'
        assert public.get(path).status_code == 404
    finally:
        public.close()

    guests = {g['id']: g for g in client.get(status).json()['guests']}
    assert guests[first]['registration_stage'] == 'submitted'
    assert guests[second]['registration_stage'] == 'awaiting_registration'
    view = client.get(path).json()
    assert view['submitted_snapshot'] and view['submitted']['full_name'] == submitted['full_name']
    assert view['submitted']['nationality'] == 'Dutch' and view['submitted']['address'] == submitted['address']
    assert view['identity']['szuletesiDatum'] == submitted['date_of_birth']
    assert view['identity']['szuletesiHely'] == 'Szeged' and view['identity']['nem'] == 'NO'
    assert view['identity']['okmanyTipus'] == 'UTLEVEL'
    assert view['identity']['okmanyAzonositoSzam'] == submitted['document_number']
    assert 'csaladnev' not in view['identity'] and 'utonev' not in view['identity']
    assert view['identity']['allampolgarsagKod'] is None and view['raw_nationality'] == 'NLD'
    assert view['reporting_profile'] == {} and 'missing_guest_reporting_profile' in view['readiness']['ntak_blockers']
    assert 'owner_verification_required' in view['readiness']['viza_blockers']
    assert 'country_mapping_requires_review' in view['readiness']['viza_blockers']
    assert not view['readiness']['actual_arrival_recorded'] and not view['readiness']['transmission_enabled']

    edit = {
        'revision': view['revision'], 'reason': 'Fictional passport and residence reviewed',
        'identity': {
            'manual': {'csaladnev': 'de la Cruz', 'utonev': 'Anna Mária', 'allampolgarsagKod': 'NL'},
            'third_country_applicable': False,
        },
        'reporting': {
            'full_name': submitted['full_name'], 'country_of_residence': 'ZZ', 'postal_code': '1011',
            'ifa_status': 'KOTELES', 'effective_from': view['business_date'],
        },
    }
    assert client.put(path, json=edit).status_code == 422
    after_failure = client.get(path).json()
    assert after_failure['revision'] == view['revision'] and after_failure['identity'] == view['identity']
    edit['reporting']['country_of_residence'] = 'NL'
    csrf = client.headers.pop('X-Rosa-CSRF')
    assert client.put(path, json=edit).status_code == 403
    client.headers['X-Rosa-CSRF'] = csrf
    saved = client.put(path, json=edit)
    assert saved.status_code == 200, saved.text
    profile = saved.json()
    assert profile['reporting_profile']['date_of_birth'] == submitted['date_of_birth']
    assert profile['reporting_profile']['nationality_country'] == 'NL'
    assert profile['reporting_profile']['sex'] == 'NO' and profile['reporting_profile']['birth_place'] == 'Szeged'
    assert profile['submitted'] == view['submitted']
    assert profile['registration_stage'] == 'submitted'
    assert profile['readiness']['viza_blockers'] == ['owner_verification_required']
    assert 'identity_normalization_unresolved' in profile['readiness']['ntak_blockers']
    assert client.put(path, json=edit).status_code == 409

    verified = client.post(reservation + '/guests/' + first + '/verify', json={
        'decision': 'verify', 'verification_method': 'in_person', 'review_note': 'Synthetic identity checked',
    })
    assert verified.status_code == 200
    assert client.get(path).json()['registration_stage'] == 'verified'
    guests = {g['id']: g for g in client.get(status).json()['guests']}
    assert guests[second]['registration_stage'] == 'awaiting_registration'
    invitation = owner_state(client, reservation)
    assert invitation['state'] == 'delivered'
    assert any(event['kind'] == 'receipt_delivered' for event in invitation['history'])
    with app.db() as con:
        assert con.execute('SELECT document_number FROM guest_records WHERE id=?', (first,)).fetchone()['document_number'] is None
        encrypted = con.execute('SELECT encrypted_payload FROM guest_identity_sources WHERE guest_record_id=?', (first,)).fetchall()
        assert all(submitted['document_number'] not in row['encrypted_payload'] for row in encrypted)
        assert not con.execute('SELECT 1 FROM guest_occupancy WHERE guest_id=?', (first,)).fetchone()
    login(client, 'cleaner')
    assert client.get(path).status_code == 403


def test_workspace_reads_legacy_registration_as_suggestions_without_rewriting_sources(client):
    login(client)
    reservation, _, _ = booking(client)
    guest = client.get(reservation + '/guest-checkin-status').json()['guests'][0]
    rid = reservation.rsplit('/', 1)[1]
    with app.db() as con:
        row = dict(con.execute('SELECT * FROM reservations WHERE id=?', (rid,)).fetchone())
        record = app.viza_identity.scope(con, row['organization_id'], guest['id'])
        con.execute("UPDATE guest_records SET full_name=?,nationality=?,document_type=?,completeness='complete' WHERE id=?",
                    ('Fictional Complex Name', 'Hungarian', 'id_card', guest['id']))
        app.viza_identity.vault_merge(app, con, guest['id'], row['organization_id'],
                                     {'sex': 'M', 'date_of_birth': '1983-04-05', 'document_number': 'FIXTURE-OLD',
                                      'address': 'Synthetic place'})
        app.viza_identity.ingest(app, con, record, {}, {'szuletesiDatum': '1983-04-05',
                                 'okmanyAzonositoSzam': 'FIXTURE-OLD'}, 'guest_token')
        con.execute("""INSERT INTO guest_checkin_events(id,organization_id,property_id,reservation_id,
            guest_record_id,event_type,metadata_json,created_at) VALUES (?,?,?,?,?,'guest_confirmed','{}',?)""",
            (app.new_id('gce'), row['organization_id'], row['property_id'], rid, guest['id'], app.now_iso()))
    path = '/api/registration/records/' + guest['id']
    view = client.get(path + '/workspace').json()
    assert view['registration_stage'] == 'submitted'
    assert view['submitted']['full_name'] == 'Fictional Complex Name' and not view['submitted_snapshot']
    assert view['identity']['okmanyTipus'] == 'SZEM_IG' and view['identity']['nem'] == 'FERFI'
    assert set(view['suggested_fields']) == {'okmanyTipus', 'nem'}
    assert view['identity']['allampolgarsagKod'] is None and 'csaladnev' not in view['identity']
    effective = client.get(path + '/viza-identity').json()['effective']
    assert effective == {'szuletesiDatum': '1983-04-05', 'okmanyAzonositoSzam': 'FIXTURE-OLD'}


def test_contact_change_cancellation_and_permanent_failure(client, provider):
    login(client)
    reservation, first, invite = booking(client, recipient=None)
    assert client.post(invite + '/approve').status_code == 409
    assert client.patch(reservation, json={'invitation_email': 'bad-address'}).status_code == 400
    assert client.patch(reservation, json={'invitation_email': RECIPIENT}).status_code == 200
    oid = client.get(reservation + '/detail').json()['precheckin_invitation']['id']
    assert oid != first
    invite = '/api/communications/outbox/' + oid
    assert client.post(invite + '/approve').status_code == 200
    assert delivery.worker_once(app, delivery.active(app))
    [link] = provider.messages[oid][1]
    guest = '/api/public/checkin/' + link.rsplit('/', 1)[1]
    assert client.get(guest).status_code == 200
    assert client.delete(reservation).status_code == 200
    assert client.get(guest).status_code == 410
    assert signed(client, oid, 'cancelled-receipt', 'delivered').status_code == 200
    with app.db() as con:
        assert delivery.get(con, oid)['state'] == 'cancelled'
    login(client, 'cleaner')
    assert client.post(invite + '/retry').status_code == 403
    login(client)

    next_res, next_id, next_invite = booking(client, days=8)
    assert client.post(next_invite + '/approve').status_code == 200
    provider.failure = delivery.SendFailure('invalid_recipient', retryable=True)
    assert delivery.worker_once(app, delivery.active(app))
    failed = owner_state(client, next_res)
    assert failed['state'] == 'permanent_failed' and failed['failure_code'] == 'invalid_recipient'
    assert failed['next_attempt_at'] is None and not failed['can_retry']
    assert client.post(next_invite + '/retry').status_code == 409
    assert provider.calls.count(next_id) == 1


def test_link_rate_limits_and_invalid_origins(client, provider, monkeypatch):
    monkeypatch.setattr(delivery, 'datetime', FixedDatetime)
    login(client)
    _, oid, invite = booking(client)
    assert client.post(invite + '/approve').status_code == 200
    assert delivery.worker_once(app, delivery.active(app))
    [link] = provider.messages[oid][1]
    token = link.rsplit('/', 1)[1]
    for _ in range(30):
        assert delivery.checkin_rate_allowed(app, 'synthetic-test-ip', token)
    assert not delivery.checkin_rate_allowed(app, 'other-synthetic-test-ip', token)
    for origin in ('http://guest.example.com', 'https://127.0.0.1', 'https://127.1',
                   'https://guest.example.com:80', 'https://user@guest.example.com', 'https://guest.example.com/a'):
        monkeypatch.setenv('DELVANE_GUEST_PUBLIC_ORIGIN', origin)
        with pytest.raises(RuntimeError, match='public HTTPS guest origin'):
            delivery.public_origin()


def test_expired_worker_lease_reuses_provider_key_after_unrecorded_acceptance(client, provider):
    login(client)
    reservation, oid, invite = booking(client)
    assert client.post(invite + '/approve').status_code == 200
    driver = delivery.active(app)
    _, _, encrypted = delivery.due(app, driver)
    assert provider.send(key=oid, **app.decrypt_json(encrypted)) == 'mock-' + oid
    assert not delivery.worker_once(app, driver)
    with app.db() as con:
        con.execute("UPDATE guest_invitation_delivery SET lease_until=? WHERE outbox_id=?",
                    ('2000-01-01T00:00:00+00:00', oid))
    assert delivery.worker_once(app, driver)
    assert provider.calls == [oid, oid] and list(provider.messages) == [oid]
    accepted = owner_state(client, reservation)
    assert accepted['state'] == 'provider_accepted' and accepted['attempts'] == 2

    later, later_id, later_invite = booking(client, days=8)
    assert client.post(later_invite + '/approve').status_code == 200
    provider.failure = TimeoutError('synthetic private provider exception')
    assert delivery.worker_once(app, driver)
    assert owner_state(client, later)['state'] == 'retry_scheduled'
    with app.db() as con:
        con.execute("UPDATE guest_invitation_delivery SET replay_until=?,next_attempt_at=? WHERE outbox_id=?",
                    ('2000-01-01T00:00:00+00:00', '2000-01-01T00:00:00+00:00', later_id))
    assert not delivery.worker_once(app, driver)
    result = owner_state(client, later)
    assert result['state'] == 'unconfirmed' and result['failure_code'] == 'outcome_unknown'
    assert not result['can_retry']
    assert 'synthetic private provider exception' not in client.get('/api/communications/outbox').text
