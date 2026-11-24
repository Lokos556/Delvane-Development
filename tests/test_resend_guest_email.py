import base64
import hashlib
import hmac
import json
import secrets
import ssl
import time
from unittest.mock import MagicMock
from uuid import uuid4

from fastapi.testclient import TestClient
import pytest

import app
import guest_delivery as delivery
import resend_guest_email as resend
from test_flutter_reservation_reception import client, login
from test_guest_delivery import ORIGIN, RECIPIENT, booking, owner_state


class FakeResend:
    def __init__(self):
        self.calls = []
        self.ids = {}
        self.next_result = None

    def __call__(self, headers, payload, proxy):
        key = headers['Idempotency-Key']
        self.calls.append((headers, payload, proxy))
        if self.next_result:
            result, self.next_result = self.next_result, None
            if isinstance(result, Exception):
                raise result
            return result
        return 200, json.dumps({'id': self.ids.setdefault(key, str(uuid4()))}).encode()


@pytest.fixture
def configured(monkeypatch):
    api_key = secrets.token_urlsafe(32)
    webhook_key = secrets.token_bytes(32)
    for name, value in {
        'DELVANE_GUEST_EMAIL_PROVIDER': 'resend',
        'DELVANE_GUEST_EMAIL_ENABLED': '1',
        'DELVANE_GUEST_PUBLIC_ORIGIN': ORIGIN,
        'DELVANE_GUEST_RETRY_BASE_SECONDS': '300',
        'RESEND_API_KEY': api_key,
        'RESEND_WEBHOOK_SECRET': 'whsec_' + base64.b64encode(webhook_key).decode(),
        'RESEND_TEST_RECIPIENT': RECIPIENT,
        'RESEND_HTTPS_PROXY': 'http://internal-resend-egress:3128',
    }.items():
        monkeypatch.setenv(name, value)
    transport = FakeResend()
    monkeypatch.setattr(resend, 'request_resend', transport)
    return transport, api_key, webhook_key


def hook(client, key, kind, message, *, outbox_id=None, event_id=None, invalid=False, age=0):
    data = {'email_id': message, 'message_id': '<different-smtp-id@pilot.invalid>', 'to': [RECIPIENT],
            'subject': 'Fictional check-in · próba'}
    if outbox_id is not None:
        data['tags'] = {resend.TAG: outbox_id}
    raw = json.dumps({'type': kind, 'data': data}, ensure_ascii=False, indent=2).encode()
    identifier = event_id or 'msg_' + uuid4().hex
    timestamp = str(int(time.time()) - age)
    signature = base64.b64encode(hmac.new(key, f'{identifier}.{timestamp}.'.encode() + raw,
                                         hashlib.sha256).digest()).decode()
    return client.post(resend.WEBHOOK_PATH, content=raw + (b'\n' if invalid else b''),
                       headers={'svix-id': identifier, 'svix-timestamp': timestamp,
                                'svix-signature': 'v2,something v1,' + signature})


def test_resend_lifespan_default_pause_and_missing_credentials(client, configured, monkeypatch):
    transport, _, _ = configured
    monkeypatch.setenv('DELVANE_GUEST_EMAIL_ENABLED', '0')
    with TestClient(app.app) as paused:
        login(paused)
        assert not paused.get('/api/reception/summary').json()['guest_email_available']
        assert hook(paused, configured[2], 'email.opened', str(uuid4())).json()['ignored']
    monkeypatch.setenv('DELVANE_GUEST_EMAIL_ENABLED', '1')
    with TestClient(app.app) as enabled:
        login(enabled)
        assert enabled.get('/api/reception/summary').json()['external_sending_connected']
    monkeypatch.setenv('RESEND_WEBHOOK_SECRET', 'whsec_invalid')
    with pytest.raises(RuntimeError, match='RESEND_WEBHOOK_SECRET'):
        with TestClient(app.app):
            pass
    monkeypatch.setenv('RESEND_WEBHOOK_SECRET', 'whsec_' + base64.b64encode(configured[2]).decode())
    monkeypatch.delenv('RESEND_API_KEY')
    with pytest.raises(RuntimeError, match='Resend requires valid sending settings'):
        with TestClient(app.app):
            pass
    monkeypatch.setenv('DELVANE_GUEST_EMAIL_ENABLED', '0')
    monkeypatch.delenv('DELVANE_GUEST_EMAIL_PROVIDER')
    with TestClient(app.app) as disabled:
        assert disabled.post(resend.WEBHOOK_PATH, content=b'{}').status_code == 404
    assert not transport.calls


def test_resend_retry_preserves_approved_payload_and_records_real_receipt_shape(client, configured,
                                                                                monkeypatch, caplog):
    transport, api_key, webhook_key = configured
    provider = resend.ResendProvider.from_environment(sending=True)
    monkeypatch.setattr(app.app.state, 'resend_guest_provider', provider)
    login(client)
    other, _, invite = booking(client, recipient='unapproved@pilot.invalid')
    assert client.post(invite + '/approve').status_code == 409
    assert owner_state(client, other) is None

    reservation, oid, invite = booking(client, days=7)
    assert client.post(invite + '/approve').json()['delivery']['state'] == 'queued'
    transport.next_result = (429, b'{"name":"rate_limit_exceeded"}')
    driver = delivery.active(app)
    assert delivery.worker_once(app, driver)
    state = owner_state(client, reservation)
    assert state['state'] == 'retry_scheduled' and state['can_retry']
    assert state['failure_code'] == 'provider_throttled'
    assert not delivery.worker_once(app, driver)
    with app.db() as con:
        row = delivery.get(con, oid)
        assert api_key not in row['encrypted_envelope'] and RECIPIENT not in row['encrypted_envelope']
        assert 'Online bejelentkezés' in app.decrypt_json(row['encrypted_envelope'])['payload']

    def reject_new_render(*_):
        pytest.fail('Existing invitation must reuse its original rendered payload')

    monkeypatch.setattr(resend, 'render_invitation', reject_new_render)
    restarted = resend.ResendProvider.from_environment(sending=True)
    monkeypatch.setattr(app.app.state, 'resend_guest_provider', restarted)
    assert client.post(invite + '/retry').status_code == 200
    assert delivery.worker_once(app, delivery.active(app))
    assert len(transport.calls) == 2 and transport.calls[0] == transport.calls[1]
    headers, raw, proxy = transport.calls[0]
    assert hmac.compare_digest(headers['Authorization'], 'Bearer ' + api_key)
    assert headers['Idempotency-Key'] == f'guest-invitation/{oid}'
    assert proxy == ('internal-resend-egress', 3128)
    outbound = json.loads(raw)
    assert outbound['from'] == 'Delvane AI <checkin@mail.delvane.app>'
    assert outbound['to'] == [RECIPIENT] and outbound['tags'] == [{'name': resend.TAG, 'value': oid}]
    assert 'Online bejelentkezés' in outbound['html'] and 'Online check-in' in outbound['text']
    token = outbound['text'].split(ORIGIN + '/guest/checkin/')[1].split()[0]
    assert len(token) == 43 and token in outbound['html']
    message = transport.ids[headers['Idempotency-Key']]
    assert owner_state(client, reservation)['state'] == 'provider_accepted'
    assert owner_state(client, reservation)['delivered_at'] is None
    with app.db() as con:
        assert delivery.get(con, oid)['provider_message_id'] == message
        assert delivery.get(con, oid)['encrypted_envelope'] is None

    public = TestClient(app.app, base_url=ORIGIN)
    try:
        assert public.get('/api/communications/outbox').status_code == 404
        assert public.post(delivery.RECEIPT_PATH, content=b'{}').status_code == 404
        assert public.post(resend.WEBHOOK_PATH, content=b' ' * 65537).status_code == 413
        assert hook(public, webhook_key, 'email.delivered', message, invalid=True).status_code == 401
        assert hook(public, webhook_key, 'email.delivered', message, age=360).status_code == 401
        assert hook(public, secrets.token_bytes(32), 'email.delivered', message).status_code == 401
        assert hook(public, webhook_key, 'email.delivered', str(uuid4()), outbox_id=oid).status_code == 409
        assert hook(public, webhook_key, 'email.delivery_delayed', message).status_code == 200
        assert hook(public, webhook_key, 'email.sent', message).status_code == 200
        assert owner_state(client, reservation)['state'] == 'provider_delayed'
        assert client.post(invite + '/retry').status_code == 409

        event_id = 'msg_' + uuid4().hex
        assert hook(public, webhook_key, 'email.delivered', message, outbox_id=oid,
                    event_id=event_id).json() == {'ok': True, 'duplicate': False}
        assert hook(public, webhook_key, 'email.delivered', message, outbox_id=oid,
                    event_id=event_id).json() == {'ok': True, 'duplicate': True}
        assert hook(public, webhook_key, 'email.failed', message, event_id=event_id).status_code == 409
        assert hook(public, webhook_key, 'email.failed', message).status_code == 200
        confirmed = owner_state(client, reservation)
        assert confirmed['state'] == 'delivered' and confirmed['delivered_at'] and confirmed['attempts'] == 2

        guest = '/api/public/checkin/' + token
        assert public.get(guest).status_code == 200
        assert client.delete(reservation).status_code == 200
        assert public.get(guest).status_code == 410
        assert hook(public, webhook_key, 'email.delivered', message).status_code == 200
        assert owner_state(client, reservation)['state'] == 'cancelled'
    finally:
        public.close()
    visible = caplog.text + client.get('/api/communications/outbox').text
    for sensitive in (api_key, base64.b64encode(webhook_key).decode(), token, RECIPIENT):
        assert sensitive not in visible


@pytest.mark.parametrize(('kind', 'reason'), [
    ('email.bounced', 'provider_bounced'),
    ('email.failed', 'provider_rejected'),
    ('email.suppressed', 'provider_suppressed'),
])
def test_signed_terminal_receipt_before_api_response_is_correlated_by_outbox_tag(client, configured,
                                                                                  monkeypatch, kind, reason):
    provider = resend.ResendProvider.from_environment(sending=True)
    monkeypatch.setattr(app.app.state, 'resend_guest_provider', provider)
    login(client)
    reservation, oid, invite = booking(client)
    assert client.post(invite + '/approve').status_code == 200
    assert delivery.due(app, delivery.active(app))
    message = str(uuid4())
    assert hook(client, configured[2], kind, message, outbox_id=oid).status_code == 200
    assert hook(client, configured[2], 'email.sent', message).status_code == 200
    state = owner_state(client, reservation)
    assert state['state'] == 'permanent_failed' and not state['can_retry']
    assert state['failure_code'] == reason and state['delivered_at'] is None
    assert not delivery.worker_once(app, delivery.active(app))
    unrelated = hook(client, configured[2], 'email.delivered', str(uuid4()))
    assert unrelated.json() == {'ok': True, 'ignored': True}


@pytest.mark.parametrize(('result', 'reason', 'retryable'), [
    ((500, b'upstream gateway'), 'outcome_unknown', True),
    ((409, b'{"name":"concurrent_idempotent_requests"}'), 'outcome_unknown', True),
    ((409, b'{"name":"invalid_idempotent_request"}'), 'outcome_unknown', False),
    ((422, b'{"name":"validation_error"}'), 'provider_rejected', False),
    ((403, b'upstream forbidden'), 'provider_rejected', False),
    ((429, b'{"name":"monthly_quota_exceeded"}'), 'provider_rejected', False),
    ((200, b'{"id":"unexpected-id"}'), 'outcome_unknown', True),
])
def test_resend_response_classification(result, reason, retryable):
    transport = FakeResend()
    transport.next_result = result
    provider = resend.ResendProvider(secrets.token_urlsafe(32), resend.DEFAULT_SENDER,
                                     secrets.token_bytes(32), transport=transport)
    with pytest.raises(delivery.SendFailure) as error:
        provider.send(key='out_' + uuid4().hex[:12], recipient=RECIPIENT, payload='{}')
    assert (error.value.code, error.value.retryable) == (reason, retryable)


@pytest.mark.parametrize(('language', 'heading', 'other'), [
    ('hu', 'Online bejelentkezés', 'Online check-in'),
    ('en', 'Online check-in', 'Online bejelentkezés'),
])
def test_resend_single_language_templates(language, heading, other):
    links = [f'{ORIGIN}/guest/checkin/{secrets.token_urlsafe(32)}' for _ in range(2)]
    message = resend.render_invitation(links, language)
    assert f'lang="{language}"' in message['html'] and '#FFD500' in message['html']
    for part in (message['subject'], message['html'], message['text']):
        assert heading in part and other not in part
    for link in links:
        assert message['html'].count(link) == message['text'].count(link) == 1


@pytest.mark.parametrize('proxy', [None, ('internal-resend-egress', 3128)])
def test_resend_http_connection_uses_verified_tls_and_never_follows_redirect(proxy, monkeypatch):
    connect = MagicMock()
    monkeypatch.setattr(resend.http.client, 'HTTPSConnection', connect)
    connection = connect.return_value
    response = connection.getresponse.return_value.__enter__.return_value
    response.status, response.read.return_value = 307, b'{}'

    assert resend.request_resend({}, b'{}', proxy) == (307, b'{}')
    assert connect.call_args.args == (proxy or ('api.resend.com', 443))
    context = connect.call_args.kwargs['context']
    assert context.check_hostname and context.verify_mode == ssl.CERT_REQUIRED
    if proxy:
        connection.set_tunnel.assert_called_once_with('api.resend.com', 443)
    else:
        connection.set_tunnel.assert_not_called()
    connection.request.assert_called_once_with('POST', '/emails', body=b'{}', headers={})
