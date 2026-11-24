"""Resend transport for the existing guest invitation outbox."""

import base64
import hashlib
import hmac
from contextlib import closing
from html import escape
import http.client
import json
import os
import re
import ssl
import time
from urllib.parse import urlsplit

from fastapi import HTTPException

import guest_delivery


WEBHOOK_PATH = '/api/public/guest-delivery/resend-webhook'
API_HOST = 'api.resend.com'
DEFAULT_SENDER = 'checkin@mail.delvane.app'
TAG = 'delvane_invitation'
OUTBOX_ID = re.compile(r'out_[0-9a-f]{12}')
EMAIL_ID = re.compile(r'[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}')
EVENTS = {
    'email.sent': 'accepted',
    'email.delivered': 'delivered',
    'email.delivery_delayed': 'delayed',
    'email.bounced': 'bounced',
    'email.failed': 'failed',
    'email.suppressed': 'suppressed',
}
INVITATION_COPY = {
    'hu': {
        'subject': 'Online bejelentkezés a szállásra',
        'heading': 'Online bejelentkezés',
        'intro': 'Érkezés előtt töltsd ki az online vendégadatlapot. Minden vendég a saját linkjét használja.',
        'button': 'Online bejelentkezés',
        'guest': '{number}. vendég',
        'footer': 'A linkek egyszer használhatók és lejárnak. Ne oszd meg őket, és ne küldj okmányadatokat e-mailben.',
    },
    'en': {
        'subject': 'Online check-in for your stay',
        'heading': 'Online check-in',
        'intro': 'Please complete your guest details before arrival. Use a separate link for each guest.',
        'button': 'Start online check-in',
        'guest': 'Guest {number}',
        'footer': 'Each link expires and can be used once. Please keep it private and do not send identity details by email.',
    },
}


def render_invitation(links, language='bilingual'):
    locales = ('hu', 'en') if language == 'bilingual' else (language,)
    translations = [INVITATION_COPY[locale] for locale in locales]
    subject = ' | '.join(copy['subject'] for copy in translations)
    if len(links) == 1:
        labels = [' / '.join(copy['button'] for copy in translations)]
    else:
        labels = [' / '.join(copy['guest'].format(number=i) for copy in translations)
                  for i in range(1, len(links) + 1)]
    buttons = '\n'.join(
        '<p style="margin:0 0 12px"><a style="display:inline-block;background:#FFD500;color:#000;'
        'border:1px solid #000;border-radius:8px;padding:12px 18px;font-weight:bold;text-decoration:none" '
        f'href="{escape(link, quote=True)}">{escape(label)}</a></p>'
        for label, link in zip(labels, links, strict=True)
    )
    intro = '\n'.join(
        f'<section lang="{locale}"><h{index} style="font-size:24px;margin:0 0 8px">{copy["heading"]}'
        f'</h{index}><p>{copy["intro"]}</p></section>'
        for index, (locale, copy) in enumerate(zip(locales, translations, strict=True), 1)
    )
    footer = '\n'.join(
        f'<p lang="{locale}" style="font-size:13px;margin:16px 0 0">{copy["footer"]}</p>'
        for locale, copy in zip(locales, translations, strict=True)
    )
    html = f"""<!doctype html><html lang="{locales[0]}"><body style="margin:0;background:#f5f5f5;color:#000;font-family:Arial,sans-serif">
<table role="presentation" width="100%" cellspacing="0" cellpadding="0"><tr><td align="center" style="padding:24px 12px">
<table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="max-width:580px;background:#fff;border:1px solid #000">
<tr><td style="padding:16px 22px;background:#FFD500;font-weight:bold;letter-spacing:2px">DELVANE AI</td></tr>
<tr><td style="padding:24px 22px;line-height:1.5">
{intro}
{buttons}
{footer}
</td></tr></table></td></tr></table></body></html>"""
    text_links = '\n\n'.join(f'{label}\n{link}' for label, link in zip(labels, links, strict=True))
    text_intro = '\n\n'.join(f"{copy['heading']}\n{copy['intro']}" for copy in translations)
    text_footer = '\n'.join(copy['footer'] for copy in translations)
    text = f'DELVANE AI\n\n{text_intro}\n\n{text_links}\n\n{text_footer}'
    return {'subject': subject, 'html': html, 'text': text}


def proxy_address(value):
    if not value:
        return None
    try:
        parsed = urlsplit(value)
        if (parsed.scheme == 'http' and parsed.hostname and parsed.port
                and parsed.username is None and not parsed.path and not parsed.query and not parsed.fragment):
            return parsed.hostname, parsed.port
    except ValueError:
        pass
    raise RuntimeError('RESEND_HTTPS_PROXY must be an HTTP CONNECT proxy origin with a port.')


def request_resend(headers, payload, proxy):
    # CONNECT keeps TLS and hostname verification end-to-end. The fixed host,
    # HTTP client without redirect handling, and explicit proxy prevent redirects
    # or process-wide proxy settings from widening credential exposure.
    host, port = proxy or (API_HOST, 443)
    with closing(http.client.HTTPSConnection(host, port, timeout=10,
                                             context=ssl.create_default_context())) as connection:
        if proxy:
            connection.set_tunnel(API_HOST, 443)
        connection.request('POST', '/emails', body=payload, headers=headers)
        with connection.getresponse() as response:
            raw = response.read(16385)
            if len(raw) > 16384:
                raise ValueError('Unexpected Resend response length.')
            return response.status, raw


def signing_key(secret):
    try:
        if secret.startswith('whsec_'):
            encoded = secret.removeprefix('whsec_')
            key = base64.b64decode(encoded + '=' * (-len(encoded) % 4), validate=True)
            if len(key) >= 24:
                return key
    except ValueError:
        pass
    raise RuntimeError('RESEND_WEBHOOK_SECRET must be the signing secret from the Resend webhook.')


class ResendProvider:
    name = 'resend'
    test_mode = False
    native_receipts = True

    def __init__(self, api_key, sender, webhook_key, recipient=None, proxy=None, transport=None, *, language='bilingual'):
        self._api_key = api_key
        self.sender = sender
        self._webhook_key = webhook_key
        self._trial_recipient = recipient
        self._proxy = proxy
        self._transport = transport or request_resend
        self._language = language

    @classmethod
    def from_environment(cls, *, sending):
        key = os.getenv('RESEND_API_KEY', '').strip() if sending else ''
        sender = os.getenv('RESEND_FROM_EMAIL', DEFAULT_SENDER).strip()
        webhook_key = signing_key(os.getenv('RESEND_WEBHOOK_SECRET', '').strip())
        recipient = os.getenv('RESEND_TEST_RECIPIENT', '').strip() or None
        language = os.getenv('RESEND_INVITATION_LANGUAGE', 'bilingual').strip()
        if (sending and (not key or any(char.isspace() for char in key))
                or not guest_delivery.email(sender) or sender.rsplit('@', 1)[-1].lower() != 'mail.delvane.app'
                or (recipient and not guest_delivery.email(recipient))):
            raise RuntimeError('Resend requires valid sending settings and a sender on mail.delvane.app.')
        if language not in ('bilingual', 'hu', 'en'):
            raise RuntimeError('RESEND_INVITATION_LANGUAGE must be bilingual, hu or en.')
        return cls(key, sender, webhook_key, recipient, proxy_address(os.getenv('RESEND_HTTPS_PROXY', '')),
                   language=language)

    def prepare_envelope(self, *, key, sender, recipient, links):
        if self._trial_recipient and recipient != self._trial_recipient:
            raise HTTPException(409, 'This invitation does not match the configured trial recipient.')
        # Freeze rendered content in the encrypted outbox. A restart or template
        # update must submit exactly the same request for a given Resend key.
        document = {'from': f'Delvane AI <{sender}>', 'to': [recipient],
                    'tags': [{'name': TAG, 'value': key}], **render_invitation(links, self._language)}
        return {'recipient': recipient, 'payload': json.dumps(document, ensure_ascii=False, separators=(',', ':'))}

    def send(self, *, key, recipient, payload):
        if not self._api_key or (self._trial_recipient and recipient != self._trial_recipient):
            raise guest_delivery.SendFailure('provider_rejected', retryable=False)
        headers = {'Authorization': f'Bearer {self._api_key}', 'Content-Type': 'application/json; charset=utf-8',
                   'Idempotency-Key': f'guest-invitation/{key}', 'User-Agent': 'Delvane-Guest-Invitations/1'}
        try:
            status, raw = self._transport(headers, payload.encode('utf-8'), self._proxy)
        except (OSError, http.client.HTTPException, ValueError):
            raise guest_delivery.SendFailure('outcome_unknown', retryable=True) from None
        try:
            document = json.loads(raw)
        except (ValueError, RecursionError):
            document = {}
        if not isinstance(document, dict):
            document = {}
        if 200 <= status < 300:
            message_id = document.get('id')
            if isinstance(message_id, str) and EMAIL_ID.fullmatch(message_id):
                return message_id
            raise guest_delivery.SendFailure('outcome_unknown', retryable=True)
        code = document.get('name')
        if status == 429 and code not in ('daily_quota_exceeded', 'monthly_quota_exceeded'):
            raise guest_delivery.SendFailure('provider_throttled', retryable=True)
        if status >= 500 or status == 408 or (status == 409 and code == 'concurrent_idempotent_requests'):
            raise guest_delivery.SendFailure('outcome_unknown', retryable=True)
        if status == 409 and code == 'invalid_idempotent_request':
            raise guest_delivery.SendFailure('outcome_unknown', retryable=False)
        raise guest_delivery.SendFailure('provider_rejected', retryable=False)

    def verify_webhook(self, raw, headers):
        identifier = headers.get('svix-id', '')
        timestamp = headers.get('svix-timestamp', '')
        if (not guest_delivery.PROVIDER_ID.fullmatch(identifier) or not re.fullmatch(r'[0-9]{1,12}', timestamp)
                or abs(time.time() - int(timestamp)) > 300):
            raise HTTPException(401, 'Invalid receipt authentication.')
        signed = f'{identifier}.{timestamp}.'.encode('ascii') + raw
        expected = base64.b64encode(hmac.new(self._webhook_key, signed, hashlib.sha256).digest()).decode('ascii')
        signatures = headers.get('svix-signature', '')
        if not signatures.isascii() or not any(
            version == 'v1' and hmac.compare_digest(signature, expected)
            for version, _, signature in (part.partition(',') for part in signatures.split())
        ):
            raise HTTPException(401, 'Invalid receipt authentication.')
        try:
            document = json.loads(raw)
            if not isinstance(document, dict) or not isinstance(document.get('type'), str):
                raise ValueError
            state = EVENTS.get(document['type'])
            if state is None:
                return None
            data = document.get('data')
            if not isinstance(data, dict):
                raise ValueError
            message_id = data.get('email_id')
            if not isinstance(message_id, str) or not EMAIL_ID.fullmatch(message_id):
                raise ValueError
            tags = data.get('tags')
            outbox_id = tags.get(TAG) if isinstance(tags, dict) else None
            if outbox_id is not None and (not isinstance(outbox_id, str) or not OUTBOX_ID.fullmatch(outbox_id)):
                raise ValueError
            return identifier, state, message_id, outbox_id
        except (ValueError, RecursionError):
            raise HTTPException(422, 'Invalid receipt.') from None
