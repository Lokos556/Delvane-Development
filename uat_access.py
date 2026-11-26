"""Host-specific access boundary for the approved native UAT accounts."""

import json
import re


HOST = 'api.delvane.app'
ID = r'[A-Za-z0-9_-]{1,128}'
PUBLIC = {('GET', '/api/client/environment'), ('POST', '/api/login')}

# Exact routes used by the native PMS. New routes require explicit review here.
ROUTES = {
    'GET': (
        r'me|owner/dashboard|worker/dashboard|organization|reception/summary',
        r'operations/(?:actual-occupancy|properties|timeline|today-command)',
        r'properties|reservations|guests|guest-journeys|inbox|inventory|maintenance',
        r'notifications(?:/preferences)?|team/overview|automation/rules|communications/outbox',
        r'security|audit|retention|search|knowledge|intelligence|memory',
        r'integrations|integration-events|integration-sync/summary|rosa/(?:conversation|provider|actions)',
        rf'properties/{ID}/(?:overview|room-types|rate-plans|physical-units(?:/capacity|/assignment-options|/{ID}/history)?)',
        rf'reservations/{ID}/(?:detail|booking-contact|reporting-details|guest-checkin-status|guest-checkin-links|allocations|actual-stay|channex-availability-delivery)',
        rf'guests/{ID}|work-tasks/{ID}(?:/checklist)?|registration/{ID}/sensitive',
        rf'registration/records/{ID}/(?:workspace|reporting-profile|viza-identity(?:/sources)?)',
        rf'government/status|government/(?:ntak|viza)/properties/{ID}',
        rf'government/ntak/forms|government/ntak/properties/{ID}/jobs/{ID}/diagnostics',
    ),
    'POST': (
        r'logout|reservations|inbox|work-tasks|maintenance|automation/run|notifications/read-all|rosa/(?:ask|chat)',
        rf'reservations/{ID}/(?:actual-stay|notes|registration-reminder|guests/{ID}/verify)',
        rf'properties/{ID}/(?:room-types|rate-plans|physical-units(?:/{ID}/periods(?:/{ID}/cancel)?)?)',
        rf'communications/outbox/{ID}/(?:approve|retry)|notifications/{ID}/read',
        rf'inbox/{ID}/(?:analyze|apply|reply-sent|archive|draft)|approvals/{ID}/resolve',
        rf'work-tasks/{ID}/(?:start|finish)|maintenance/{ID}/resolve|guests/{ID}/preferences',
        rf'government/ntak/properties/{ID}/jobs/{ID}/evidence-export',
    ),
    'PATCH': (
        rf'reservations/{ID}(?:/operations)?|organization/mode|automation/rules/{ID}|inventory/{ID}',
        rf'work-tasks/{ID}/(?:assignment|checklist/{ID})|maintenance/{ID}/status',
        rf'communications/outbox/{ID}|inbox/{ID}/draft|authority/{ID}|knowledge/{ID}',
    ),
    'PUT': (
        rf'reservations/{ID}/allocations|notifications/preferences',
        rf'properties/{ID}/physical-units/(?:{ID}|historical-stock/{ID})',
        rf'registration/records/{ID}/(?:workspace|sensitive|reporting-profile|viza-identity)',
        rf'government/ntak/properties/{ID}/(?:daily-closing/[0-9]{{4}}-[0-9]{{2}}-[0-9]{{2}}|reservations/{ID}/facts)',
    ),
    'DELETE': (rf'reservations/{ID}|security/sessions/{ID}',),
}
PATHS = {method: re.compile(r'/api/(?:' + '|'.join(paths) + ')') for method, paths in ROUTES.items()}


def route_allowed(method, path, raw_path):
    # Prevent normalization aliases between Cloudflare, Nginx and ASGI.
    return (raw_path == path.encode() and ('%' not in path)
            and ((method, path) in PUBLIC or bool(method in PATHS and PATHS[method].fullmatch(path))))


def approved_accounts(raw):
    if not raw:
        return frozenset()
    try:
        accounts = json.loads(raw)
        if (not isinstance(accounts, list) or not 1 <= len(accounts) <= 50
                or any(not isinstance(pair, list) or len(pair) != 2
                       or any(not isinstance(value, str) or not re.fullmatch(ID, value) for value in pair)
                       for pair in accounts)):
            raise ValueError
        return frozenset(tuple(pair) for pair in accounts)
    except (TypeError, ValueError):
        raise RuntimeError('Invalid native UAT account allowlist.') from None


def can_access(accounts, user):
    return bool(user and (user['organization_id'], user['id']) in accounts)
