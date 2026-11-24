"""Email dispatch state for the existing guest invitation outbox."""

import hashlib
import hmac
import ipaddress
import json
import os
import re
import secrets
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Protocol
from urllib.parse import urlsplit

from fastapi import HTTPException
from pydantic import BaseModel, ConfigDict, Field

VERSION = 3091
LEASE_SECONDS = 90
REPLAY_HOURS = 24
RECEIPT_PATH = '/api/public/guest-delivery/receipt'
GUEST_PAGE = re.compile(r'/guest/checkin/[A-Za-z0-9_-]{43}')
GUEST_API = re.compile(r'/api/public/checkin/[A-Za-z0-9_-]{43}')
GUEST_ASSETS = {
    '/static/guest-checkin.css', '/static/guest-checkin.js',
    '/static/guest-checkin-i18n.js', '/static/delvane-icon.png',
}
REASONS = frozenset({'provider_unavailable', 'provider_throttled', 'invalid_recipient',
                     'provider_rejected', 'outcome_unknown'})
PROVIDER_ID = re.compile(r'[A-Za-z0-9_.:-]{1,128}')


class Provider(Protocol):
    """Bounded send timeout and 24h idempotent acceptance are required.

    A repeated key for the same envelope must return its original message ID
    without sending again. A provider integration must normalize its failures.
    """
    name: str
    test_mode: bool
    def send(self, *, key: str, **envelope) -> str: ...


class SendFailure(Exception):
    def __init__(self, code: str, *, retryable: bool):
        self.code = code if code in REASONS else 'outcome_unknown'
        self.retryable = retryable and self.code not in {'invalid_recipient', 'provider_rejected'}


@dataclass(frozen=True)
class Policy:
    sender: str
    receipt_secret: bytes
    attempts: int
    base_delay: int
    max_delay: int
    link_hours: int


def public_origin():
    raw = os.getenv('DELVANE_GUEST_PUBLIC_ORIGIN', '').strip()
    if not raw:
        return None
    try:
        parsed = urlsplit(raw)
        host = parsed.hostname or ''
        if (parsed.scheme != 'https' or parsed.netloc.lower() != host or parsed.path not in ('', '/')
                or parsed.query or parsed.fragment
                or not re.fullmatch(r'[a-z0-9](?:[a-z0-9-]*[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]*[a-z0-9])?)+', host)
                or not re.search(r'\.[a-z][a-z0-9-]+$', host)
                or host.endswith(('.local', '.localhost', '.internal', '.invalid', '.test', '.lan'))):
            raise ValueError
        try:
            ipaddress.ip_address(host)
        except ValueError:
            return f'https://{host}'
    except ValueError:
        pass
    raise RuntimeError('Configure a public HTTPS guest origin using a DNS hostname.')


def email(value):
    return bool(re.fullmatch(r"[^\s@<>(),;:\\]+@[a-zA-Z0-9-]+(?:\.[a-zA-Z0-9-]+)+", value)) and len(value) <= 254


def active(backend):
    if os.getenv('DELVANE_GUEST_EMAIL_ENABLED') != '1':
        return None
    provider = (getattr(backend.app.state, 'guest_email_provider', None)
                or getattr(backend.app.state, 'resend_guest_provider', None))
    if provider is None:
        return None
    native_receipts = getattr(provider, 'native_receipts', False)
    sender = provider.sender if native_receipts else os.getenv('DELVANE_GUEST_EMAIL_FROM', '').strip()
    secret = b'' if native_receipts else os.getenv('DELVANE_GUEST_RECEIPT_SECRET', '').encode()
    try:
        attempts = int(os.getenv('DELVANE_GUEST_MAX_ATTEMPTS', '5'))
        base = int(os.getenv('DELVANE_GUEST_RETRY_BASE_SECONDS', '60'))
        cap = int(os.getenv('DELVANE_GUEST_RETRY_MAX_SECONDS', '3600'))
        hours = int(os.getenv('DELVANE_GUEST_LINK_HOURS', '48'))
    except ValueError:
        raise RuntimeError('Guest delivery retry and expiry settings must be integers.') from None
    if (not public_origin() or not email(sender) or (not native_receipts and len(secret) < 32) or not 1 <= attempts <= 10
            or not 1 <= base <= cap <= 3600 or not 1 <= hours <= 168
            or not PROVIDER_ID.fullmatch(provider.name)):
        raise RuntimeError('Guest delivery requires a valid origin, sender, receipt secret and retry policy.')
    return provider, Policy(sender, secret, attempts, base, cap, hours)


def stamp(instant=None):
    return (instant or datetime.now(timezone.utc)).isoformat(timespec='seconds')


def migrate(backend, con):
    con.executescript("""
        CREATE TABLE IF NOT EXISTS guest_invitation_delivery (
            outbox_id TEXT PRIMARY KEY REFERENCES communication_outbox(id) ON DELETE CASCADE,
            provider TEXT NOT NULL, test_mode INTEGER NOT NULL, state TEXT NOT NULL,
            encrypted_envelope TEXT, attempts INTEGER NOT NULL DEFAULT 0, max_attempts INTEGER NOT NULL,
            next_attempt_at TEXT, last_attempt_at TEXT, lease_id TEXT, lease_until TEXT,
            replay_until TEXT NOT NULL, provider_message_id TEXT,
            failure_code TEXT, delivered_at TEXT, updated_at TEXT NOT NULL,
            UNIQUE(provider,provider_message_id)
        );
        CREATE INDEX IF NOT EXISTS idx_guest_invitation_due
            ON guest_invitation_delivery(provider,test_mode,state,next_attempt_at,lease_until);
        CREATE TABLE IF NOT EXISTS guest_invitation_delivery_events (
            id TEXT PRIMARY KEY, outbox_id TEXT NOT NULL REFERENCES guest_invitation_delivery(outbox_id) ON DELETE CASCADE,
            provider TEXT, provider_event_id TEXT, receipt_digest TEXT, kind TEXT NOT NULL,
            detail_code TEXT, created_at TEXT NOT NULL, UNIQUE(provider,provider_event_id)
        );
        CREATE TABLE IF NOT EXISTS guest_link_rate_limits (
            bucket TEXT NOT NULL, window_start INTEGER NOT NULL, hits INTEGER NOT NULL,
            PRIMARY KEY(bucket,window_start)
        );
        CREATE TABLE IF NOT EXISTS guest_invitation_contacts (
            reservation_id TEXT PRIMARY KEY REFERENCES reservations(id) ON DELETE CASCADE,
            encrypted_email TEXT NOT NULL
        );
    """)
    backend.add_column_if_missing(con, 'guest_checkin_tokens', 'invitation_id', 'TEXT')
    con.execute('INSERT OR IGNORE INTO schema_migrations(version,name,applied_at) VALUES (?,?,?)',
                (VERSION, 'guest_invitation_delivery', backend.now_iso()))


def event(con, outbox_id, kind, code=None):
    con.execute("""INSERT INTO guest_invitation_delivery_events(id,outbox_id,kind,detail_code,created_at)
        VALUES (?,?,?,?,?)""", (secrets.token_hex(16), outbox_id, kind, code, stamp()))


def get(con, outbox_id):
    return con.execute('SELECT * FROM guest_invitation_delivery WHERE outbox_id=?', (outbox_id,)).fetchone()


def summary(row, active_adapter):
    if row is None:
        return None
    result = {key: row[key] for key in ('state', 'attempts', 'max_attempts', 'last_attempt_at',
                                      'next_attempt_at', 'failure_code', 'delivered_at')}
    result['channel'] = 'email'
    result['test_mode'] = bool(row['test_mode'])
    result['can_retry'] = bool(active_adapter and driver_matches(row, active_adapter[0])
                               and row['state'] == 'retry_scheduled' and row['attempts'] < row['max_attempts']
                               and stamp() < row['replay_until'])
    return result


def details(con, row, active_adapter):
    result = summary(row, active_adapter)
    if result is not None:
        result['history'] = [dict(event) for event in con.execute('''SELECT kind,created_at
            FROM guest_invitation_delivery_events WHERE outbox_id=?
            ORDER BY created_at DESC,id DESC LIMIT 50''', (row['outbox_id'],))]
    return result


def driver_matches(row, provider):
    return row['provider'] == provider.name and bool(row['test_mode']) == provider.test_mode


def contact_override(backend, con, reservation_id):
    row = con.execute('SELECT encrypted_email FROM guest_invitation_contacts WHERE reservation_id=?',
                      (reservation_id,)).fetchone()
    return backend.decrypt_json(row['encrypted_email'])['email'] if row else ''


def save_contact(backend, con, reservation_id, address):
    if address:
        con.execute('''INSERT INTO guest_invitation_contacts(reservation_id,encrypted_email) VALUES (?,?)
          ON CONFLICT(reservation_id) DO UPDATE SET encrypted_email=excluded.encrypted_email''',
          (reservation_id, backend.encrypt_json({'email': address})))
    else:
        con.execute('DELETE FROM guest_invitation_contacts WHERE reservation_id=?', (reservation_id,))


def queue(backend, con, invitation, driver):
    outbox_id = invitation['id']
    existing = get(con, outbox_id)
    if existing:
        return existing
    provider, policy = driver
    org, rid = invitation['organization_id'], invitation['reservation_id']
    reservation = con.execute('SELECT * FROM reservations WHERE id=? AND organization_id=?',
                              (rid, org)).fetchone()
    if (reservation is None or reservation['status'] != 'confirmed'
            or reservation['property_id'] != invitation['property_id']
            or reservation['departure_date'] < str(backend.date.today())):
        raise HTTPException(409, 'The reservation is no longer eligible for this invitation.')
    contact = con.execute("""SELECT g.email FROM guest_reservations a JOIN guests g ON g.id=a.guest_id
        WHERE a.reservation_id=? AND a.is_primary=1 AND g.organization_id=?""", (rid, org)).fetchone()
    recipient = contact_override(backend, con, rid) or ((contact['email'] or '').strip() if contact else '')
    if not email(recipient):
        raise HTTPException(409, 'A valid booking contact email is required.')
    if len(backend._ensure_guest_records(con, reservation)) != int(reservation['guest_count']):
        raise HTTPException(409, 'Guest records require review.')
    guests = backend._guests_needing_precheckin(con, reservation)
    if not guests:
        raise HTTPException(409, 'All guests have already submitted their pre-check-in details.')
    now = datetime.now(timezone.utc)
    expires = backend.datetime.now().replace(microsecond=0) + timedelta(hours=policy.link_hours)
    links = [f"{public_origin()}/guest/checkin/" + backend._create_guest_checkin_token(
        con, reservation, guest, invitation_id=outbox_id, expire_by=expires) for guest in guests]
    envelope_fields = {'sender': policy.sender, 'recipient': recipient, 'links': links}
    prepare = getattr(provider, 'prepare_envelope', None)
    if prepare is not None:
        envelope_fields = prepare(key=outbox_id, **envelope_fields)
    envelope = backend.encrypt_json(envelope_fields)
    con.execute("""INSERT INTO guest_invitation_delivery
        (outbox_id,provider,test_mode,state,encrypted_envelope,max_attempts,next_attempt_at,replay_until,updated_at)
        VALUES (?,?,?,'queued',?,?,?,?,?)""", (outbox_id, provider.name, int(provider.test_mode), envelope,
            policy.attempts, stamp(now), stamp(now + timedelta(hours=min(REPLAY_HOURS, policy.link_hours))), stamp(now)))
    event(con, outbox_id, 'queued')
    return get(con, outbox_id)


def cancel(con, outbox_id, code):
    row = get(con, outbox_id)
    if not row or row['state'] == 'cancelled':
        return
    con.execute("""UPDATE guest_invitation_delivery SET state='cancelled',encrypted_envelope=NULL,
        next_attempt_at=NULL,lease_id=NULL,lease_until=NULL,failure_code=NULL,updated_at=? WHERE outbox_id=?""",
        (stamp(), outbox_id))
    con.execute("UPDATE guest_checkin_tokens SET status='revoked' WHERE invitation_id=? AND status='active'",
                (outbox_id,))
    event(con, outbox_id, 'cancelled', code)


def cancel_for_booking(con, reservation_id, *, pending_only=False):
    pending = " AND d.state IN ('queued','retry_scheduled')" if pending_only else ""
    for row in con.execute("""SELECT o.id FROM communication_outbox o JOIN guest_invitation_delivery d
        ON d.outbox_id=o.id WHERE o.reservation_id=? AND d.state!='cancelled'""" + pending, (reservation_id,)).fetchall():
        cancel(con, row['id'], 'guest_submitted' if pending_only else 'booking_changed')
        if pending_only:
            con.execute("UPDATE communication_outbox SET status='cancelled' WHERE id=?", (row['id'],))


def due(backend, driver):
    provider, _ = driver
    now = stamp()
    with backend.db() as con:
        candidate = con.execute("""SELECT o.id,o.organization_id,o.reservation_id
            FROM guest_invitation_delivery d JOIN communication_outbox o ON o.id=d.outbox_id
            WHERE d.provider=? AND d.test_mode=? AND (
                (d.state IN ('queued','retry_scheduled') AND d.next_attempt_at<=?) OR
                (d.state='sending' AND d.lease_until<=?)
            ) ORDER BY COALESCE(d.next_attempt_at,d.lease_until),o.id LIMIT 1""",
            (provider.name, int(provider.test_mode), now, now)).fetchone()
        if not candidate:
            return None
        outbox_id = candidate['id']
        backend._lock_reservation(con, candidate['reservation_id'], candidate['organization_id'])
        row = get(con, outbox_id)
        if row['state'] in ('queued', 'retry_scheduled') and row['next_attempt_at'] <= now:
            pass
        elif row['state'] != 'sending' or row['lease_until'] > now:
            return None
        valid = con.execute("""SELECT 1 FROM guest_checkin_tokens t JOIN reservations r ON r.id=t.reservation_id
            WHERE t.invitation_id=? AND t.status='active' AND t.expires_at>? AND r.status='confirmed'
            AND r.organization_id=t.organization_id AND r.property_id=t.property_id LIMIT 1""",
            (outbox_id, backend.now_iso())).fetchone()
        if now >= row['replay_until'] or row['attempts'] >= row['max_attempts'] or not valid:
            uncertain = row['state'] == 'sending' or row['failure_code'] == 'outcome_unknown'
            state = 'unconfirmed' if uncertain else 'permanent_failed'
            code = 'outcome_unknown' if state == 'unconfirmed' else 'invitation_expired'
            set_result(con, outbox_id, state, code)
            return None
        lease = secrets.token_hex(16)
        until = stamp(datetime.now(timezone.utc) + timedelta(seconds=LEASE_SECONDS))
        con.execute("""UPDATE guest_invitation_delivery SET state='sending',lease_id=?,lease_until=?,
            attempts=attempts+1,last_attempt_at=?,next_attempt_at=NULL,failure_code=NULL,updated_at=?
            WHERE outbox_id=?""", (lease, until, now, now, outbox_id))
        event(con, outbox_id, 'sending')
        return dict(candidate), lease, row['encrypted_envelope']


def set_result(con, outbox_id, state, code=None, *, next_at=None, message_id=None):
    con.execute("""UPDATE guest_invitation_delivery SET state=?,failure_code=?,next_attempt_at=?,
        lease_id=NULL,lease_until=NULL,provider_message_id=COALESCE(provider_message_id,?),
        delivered_at=CASE WHEN ?='delivered' THEN COALESCE(delivered_at,?) ELSE delivered_at END,
        encrypted_envelope=CASE WHEN ?='retry_scheduled' THEN encrypted_envelope ELSE NULL END,
        updated_at=? WHERE outbox_id=?""", (state, code, next_at, message_id, state, stamp(), state, stamp(), outbox_id))
    event(con, outbox_id, state, code)


def worker_once(backend, driver):
    claim = due(backend, driver)
    if not claim:
        return False
    item, lease, encrypted = claim
    provider, policy = driver
    outbox_id = item['id']
    message = None
    failure = None
    try:
        envelope = backend.decrypt_json(encrypted)
        message = provider.send(key=outbox_id, **envelope)
        if not isinstance(message, str) or not PROVIDER_ID.fullmatch(message):
            raise SendFailure('outcome_unknown', retryable=True)
    except SendFailure as error:
        failure = error
    except Exception:
        # A timeout or lost response may conceal acceptance. Reuse the same
        # provider idempotency key; never retain the provider exception text.
        failure = SendFailure('outcome_unknown', retryable=True)
    with backend.db() as con:
        backend._lock_reservation(con, item['reservation_id'], item['organization_id'])
        row = get(con, outbox_id)
        if row['state'] != 'sending' or row['lease_id'] != lease:
            return True  # receipt, cancellation or newer worker already won
        if failure is None:
            if message_is_bound(con, provider.name, message, outbox_id):
                set_result(con, outbox_id, 'unconfirmed', 'outcome_unknown')
            else:
                set_result(con, outbox_id, 'provider_accepted', message_id=message)
        elif failure.retryable and row['attempts'] < row['max_attempts']:
            bound = min(policy.max_delay, policy.base_delay * 2 ** (row['attempts'] - 1))
            delay = bound - secrets.randbelow(max(1, bound // 4 + 1))
            retry = stamp(datetime.now(timezone.utc) + timedelta(seconds=delay))
            if retry < row['replay_until']:
                set_result(con, outbox_id, 'retry_scheduled', failure.code, next_at=retry)
            else:
                set_result(con, outbox_id, 'unconfirmed' if failure.code == 'outcome_unknown'
                           else 'permanent_failed', failure.code)
        else:
            set_result(con, outbox_id, 'unconfirmed' if failure.code == 'outcome_unknown'
                       else 'permanent_failed', failure.code)
    return True


class Receipt(BaseModel):
    model_config = ConfigDict(extra='forbid')
    event_id: str = Field(pattern=PROVIDER_ID.pattern)
    outbox_id: str = Field(pattern=PROVIDER_ID.pattern)
    message_id: str = Field(pattern=PROVIDER_ID.pattern)
    state: str = Field(pattern=r'^(accepted|delivered|delayed|bounced|failed|suppressed)$')


def verify_receipt(raw, timestamp, signature, secret):
    if not re.fullmatch(r'[0-9]{1,12}', timestamp) or not re.fullmatch(r'[0-9a-f]{64}', signature):
        raise HTTPException(401, 'Invalid receipt authentication.')
    if abs(datetime.now(timezone.utc).timestamp() - int(timestamp)) > 300:
        raise HTTPException(401, 'Invalid receipt authentication.')
    expected = hmac.new(secret, timestamp.encode() + b'.' + raw, hashlib.sha256).hexdigest()
    if not hmac.compare_digest(expected, signature):
        raise HTTPException(401, 'Invalid receipt authentication.')
    try:
        value = Receipt.model_validate_json(raw)
        if value.state not in ('accepted', 'delivered', 'bounced'):
            raise ValueError
        return value
    except ValueError:
        raise HTTPException(422, 'Invalid receipt.') from None


def message_is_bound(con, provider, message_id, outbox_id):
    return con.execute('''SELECT 1 FROM guest_invitation_delivery
        WHERE provider=? AND provider_message_id=? AND outbox_id!=?''',
        (provider, message_id, outbox_id)).fetchone() is not None


def native_receipt(backend, provider, event_id, state, message_id, outbox_id):
    if outbox_id is None:
        with backend.db() as con:
            row = con.execute("""SELECT outbox_id FROM guest_invitation_delivery
                WHERE provider=? AND test_mode=? AND provider_message_id=?""",
                (provider.name, int(provider.test_mode), message_id)).fetchone()
        if not row:
            return {'ok': True, 'ignored': True}
        outbox_id = row['outbox_id']
    value = Receipt(event_id=event_id, state=state, message_id=message_id, outbox_id=outbox_id)
    return receipt(backend, provider, value, ignore_missing=True)


def receipt(backend, provider, value, *, ignore_missing=False):
    digest = hashlib.sha256(value.model_dump_json().encode()).hexdigest()
    with backend.db() as con:
        item = con.execute("""SELECT organization_id,reservation_id FROM communication_outbox
            WHERE id=?""", (value.outbox_id,)).fetchone()
        if item:
            backend._lock_reservation(con, item['reservation_id'], item['organization_id'])
        row = get(con, value.outbox_id) if item else None
        if not row or not driver_matches(row, provider):
            if ignore_missing:
                return {'ok': True, 'ignored': True}
            raise HTTPException(404, 'Invitation delivery not found.')
        if row['provider_message_id'] and row['provider_message_id'] != value.message_id:
            raise HTTPException(409, 'Receipt message does not match this invitation.')
        if not row['attempts'] or message_is_bound(con, provider.name, value.message_id, value.outbox_id):
            raise HTTPException(409, 'Receipt message does not match this invitation.')
        inserted = con.execute("""INSERT INTO guest_invitation_delivery_events
            (id,outbox_id,provider,provider_event_id,receipt_digest,kind,created_at)
            VALUES (?,?,?,?,?,?,?) ON CONFLICT(provider,provider_event_id) DO NOTHING""",
            (secrets.token_hex(16), value.outbox_id, provider.name, value.event_id,
             digest, 'receipt_' + value.state, stamp()))
        if inserted.rowcount == 0:
            seen = con.execute("""SELECT receipt_digest FROM guest_invitation_delivery_events
                WHERE provider=? AND provider_event_id=?""", (provider.name, value.event_id)).fetchone()
            if seen['receipt_digest'] != digest:
                raise HTTPException(409, 'Receipt event identifier was reused.')
            return {'ok': True, 'duplicate': True}
        current = row['state']
        if current not in ('cancelled', 'delivered'):
            if value.state == 'delivered':
                set_result(con, value.outbox_id, 'delivered', message_id=value.message_id)
            elif value.state in ('bounced', 'failed', 'suppressed'):
                code = {'bounced': 'provider_bounced', 'failed': 'provider_rejected',
                        'suppressed': 'provider_suppressed'}[value.state]
                set_result(con, value.outbox_id, 'permanent_failed', code, message_id=value.message_id)
            elif current != 'permanent_failed':
                if value.state == 'delayed':
                    set_result(con, value.outbox_id, 'provider_delayed', message_id=value.message_id)
                elif current != 'provider_delayed':
                    set_result(con, value.outbox_id, 'provider_accepted', message_id=value.message_id)
    return {'ok': True, 'duplicate': False}


def checkin_rate_allowed(backend, ip, token):
    window = int(datetime.now(timezone.utc).timestamp()) // 60
    buckets = [('ip:' + hashlib.sha256(ip.encode()).hexdigest(), 60)]
    with backend.db() as con:
        con.execute('DELETE FROM guest_link_rate_limits WHERE window_start<?', (window-1,))
        digest = backend._guest_checkin_token_hash(token)
        if con.execute("SELECT 1 FROM guest_checkin_tokens WHERE token_hash=? AND status='active'",
                       (digest,)).fetchone():
            buckets.append(('token:' + digest, 30))
        allowed = True
        for bucket, limit in buckets:
            row = con.execute("""INSERT INTO guest_link_rate_limits(bucket,window_start,hits) VALUES (?,?,1)
                ON CONFLICT(bucket,window_start) DO UPDATE SET hits=guest_link_rate_limits.hits+1
                RETURNING hits""", (bucket, window)).fetchone()
            allowed = allowed and row['hits'] <= limit
    return allowed
