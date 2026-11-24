"""Synthetic API journey against the isolated Pilot PostgreSQL lab."""

import hashlib
import hmac
from http.client import HTTPConnection
import json
import os
import sys
import time
from datetime import timedelta

import app
import guest_delivery as delivery
from uat_postgres_smoke import LocalAPI, seed, verify_isolation, verify_migrations


class LabProvider:
    name = 'isolated-pilot'
    test_mode = True

    def send(self, *, key, sender, recipient, links):
        assert sender.endswith('@pilot.invalid') and recipient.endswith('@pilot.invalid')
        assert len(links) == 1 and links[0].startswith('https://guest.example.com/guest/checkin/')
        with app.db() as con:
            if delivery.get(con, key)['attempts'] == 1:
                raise delivery.SendFailure('provider_unavailable', retryable=True)
        return 'mock-' + key


if __name__ != '__main__':
    verify_isolation()
    app.app.state.guest_email_provider = LabProvider()
    service = app.app


def login(owner):
    client = LocalAPI()
    client.request('POST', '/api/login', {'email': f'owner-{owner}@uat.invalid',
                   'password': os.environ['PILOT_OWNER_PASSWORD']})
    return client.request


def create(owner, days, recipient):
    start = app.date.today() + timedelta(days=days)
    rid = owner('POST', '/api/reservations', {
        'property_id': 'prop_uat_a', 'room_type_id': 'room_uat', 'guest_name': 'Fictional mail guest',
        'arrival_date': str(start), 'departure_date': str(start + timedelta(days=2)),
        'guest_count': 1, 'source': 'Direct', 'invitation_email': recipient,
    })[0]['id']
    path = '/api/reservations/' + rid
    return path, owner('GET', path + '/detail')[0]['precheckin_invitation']['id']


def wait_state(owner, path, state):
    for _ in range(30):
        last = owner('GET', path + '/detail')[0]['precheckin_invitation']['delivery']
        if last and last['state'] == state:
            return last
        time.sleep(1)
    raise AssertionError(('Waited for', state, last['state'] if last else None))


def fake_receipt(oid):
    raw = json.dumps({'event_id': 'synthetic-' + oid, 'outbox_id': oid,
                      'message_id': 'mock-' + oid, 'state': 'delivered'}).encode()
    timestamp = str(int(time.time()))
    secret = os.environ['DELVANE_GUEST_RECEIPT_SECRET'].encode()
    signature = hmac.new(secret, timestamp.encode() + b'.' + raw, hashlib.sha256).hexdigest()
    connection = HTTPConnection('127.0.0.1', 8080, timeout=5)
    try:
        connection.request('POST', delivery.RECEIPT_PATH, raw,
                           {'Host': 'guest.example.com', 'X-Delvane-Timestamp': timestamp,
                            'X-Delvane-Signature': signature})
        response = connection.getresponse()
        assert response.status == 200
        return json.loads(response.read())
    finally:
        connection.close()


def approve_and_wait():
    with app.db() as con:
        seed(app, con, os.environ['PILOT_OWNER_PASSWORD'])
    owner = login('a')
    path, oid = create(owner, 7, 'retry@pilot.invalid')
    invite = '/api/communications/outbox/' + oid
    login('b')('POST', invite + '/approve', status=404)
    owner('POST', invite + '/approve')
    owner('POST', invite + '/approve')
    retry = wait_state(owner, path, 'retry_scheduled')
    assert retry['attempts'] == 1 and retry['can_retry']
    print('Authorized invitation queued once; temporary provider failure scheduled a durable retry.')


def after_restart():
    with app.db() as con:
        row = con.execute('''SELECT o.id,o.reservation_id,d.encrypted_envelope
            FROM communication_outbox o JOIN guest_invitation_delivery d ON o.id=d.outbox_id
            WHERE d.state='retry_scheduled' AND d.attempts=1''').fetchone()
        assert row
        [link] = app.decrypt_json(row['encrypted_envelope'])['links']
    owner = login('a')
    invite = '/api/communications/outbox/' + row['id']
    path = '/api/reservations/' + row['reservation_id']
    login('b')('POST', invite + '/retry', status=404)
    owner('POST', invite + '/retry')
    accepted = wait_state(owner, path, 'provider_accepted')
    assert accepted['attempts'] == 2 and accepted['delivered_at'] is None
    assert fake_receipt(row['id']) == {'ok': True, 'duplicate': False}
    assert fake_receipt(row['id']) == {'ok': True, 'duplicate': True}
    assert wait_state(owner, path, 'delivered')['delivered_at']
    public = LocalAPI().request
    guest = '/api/public/checkin/' + link.rsplit('/', 1)[1]
    public('GET', guest)
    result = public('POST', guest, {'full_name': 'Fictional Mail Guest', 'date_of_birth': '1986-01-02',
                    'nationality': 'HU', 'document_type': 'passport', 'document_number': 'PILOT-SYNTHETIC',
                    'guest_confirmed': True, 'scan_method': 'manual', 'address': 'Fictional address'})[0]
    assert result['verification_status'] == 'needs_review'
    assert owner('GET', path + '/guest-checkin-status')[0]['registration_status'] == 'pending'

    cancellation, cid = create(owner, 14, 'cancel@pilot.invalid')
    second = '/api/communications/outbox/' + cid
    owner('POST', second + '/approve')
    wait_state(owner, cancellation, 'retry_scheduled')
    with app.db() as con:
        [cancelled_link] = app.decrypt_json(delivery.get(con, cid)['encrypted_envelope'])['links']
    owner('POST', second + '/retry')
    wait_state(owner, cancellation, 'provider_accepted')
    cancelled_guest = '/api/public/checkin/' + cancelled_link.rsplit('/', 1)[1]
    public('GET', cancelled_guest)
    owner('DELETE', cancellation)
    public('GET', cancelled_guest, status=410)
    with app.db() as con:
        assert delivery.get(con, cid)['state'] == 'cancelled'
        assert delivery.get(con, row['id'])['encrypted_envelope'] is None
        assert not con.execute('SELECT 1 FROM ntak_jobs WHERE attempts>0').fetchone()
        assert not con.execute('SELECT 1 FROM viza_jobs WHERE attempts>0').fetchone()
    print('Same invitation survived a backend process restart; retry, authenticated receipt, guest submission and cancellation passed.')


if __name__ == '__main__':
    database = verify_isolation()
    verify_migrations(app, database, latest=delivery.VERSION)
    if sys.argv[1:] == ['--restart']:
        after_restart()
    else:
        approve_and_wait()
