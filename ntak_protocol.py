"""NTAK v9 XML and response semantics; no I/O or PMS storage."""
from datetime import date, datetime, timezone
from decimal import Decimal
import hashlib
import re
from lxml import etree
from ntak_contracts import ContractError, NAMESPACE, SOAP, XSD, OPERATIONS, contracts, envelope, parse_xml, validate


class ReportingBlocked(ValueError):
    def __init__(self, code, fields=()):
        self.code, self.fields = code, list(fields)
        super().__init__(code)


def require_fields(value, names):
    missing = [n for n in names if n not in value or value[n] is None or value[n] == '']
    if missing:
        raise ReportingBlocked('missing_reporting_data', missing)


def _element(schema, declaration, value):
    name = declaration.get('name')
    node = etree.Element('{' + NAMESPACE + '}' + name)
    kind = declaration.find('{' + XSD + '}complexType')
    if kind is None and declaration.get('type'):
        kind = schema.find("{" + XSD + "}complexType[@name='" + declaration.get('type') + "']")
    if kind is None:
        if isinstance(value, (dict, list)) or value is None:
            raise ReportingBlocked('invalid_reporting_data', [name])
        node.text = ('true' if value else 'false') if isinstance(value, bool) else str(value)
        return node
    if not isinstance(value, dict):
        raise ReportingBlocked('invalid_reporting_data', [name])
    fields = kind.findall('.//{' + XSD + '}element')
    allowed = {n.get('name') for n in fields}
    if set(value) - allowed:
        raise ReportingBlocked('unknown_reporting_field', sorted(set(value) - allowed))
    for field in fields:
        key = field.get('name')
        if key not in value:
            if field.get('minOccurs', '1') != '0':
                raise ReportingBlocked('missing_reporting_data', [key])
            continue
        entries = value[key] if isinstance(value[key], list) else [value[key]]
        for entry in entries:
            node.append(_element(schema, field, entry))
    return node


def header(config, message_id, sent_at):
    require_fields(config, ['registration_id', 'provider_vat', 'software_id', 'software_version'])
    vat = str(config['provider_vat'])
    if re.fullmatch('[0-9]{11}', vat):
        vat = vat[:8] + '-' + vat[8] + '-' + vat[9:]
    return {'uzenetAdatok': {'uzenetId': message_id, 'uzenetKuldesIdeje': sent_at},
            'szoftverAdatok': {'szoftverAzonosito': config['software_id'], 'szoftverVerzio': config['software_version']},
            'szallashely': {'szallasRegisztraciosSzam': config['registration_id'], 'szallashelySzolgaltatoAdoszam': vat}}


def request_xml(operation, config, payload, message_id, sent_at):
    if operation not in OPERATIONS:
        raise ReportingBlocked('unknown_operation')
    data = header(config, message_id, sent_at)
    if set(payload) & set(data):
        raise ReportingBlocked('identity_override_forbidden')
    data.update(payload)
    schema = contracts()[operation][1]
    declaration = schema.find("{" + XSD + "}element[@name='" + OPERATIONS[operation] + "Request']")
    xml = envelope(_element(schema, declaration, data))
    validate(operation, xml)
    return xml


def reservation_payload(reservation, facts, occurred_at):
    require_fields(facts, ['garantaltFoglalas', 'vendegKuldoOrszaga', 'ertekesitesiCsatorna',
                          'foglaltLakoegysegek', 'piaciSzegmens'])
    require_fields(reservation, ['total_huf', 'created_at', 'arrival_date', 'departure_date', 'guest_count'])
    if not 0 < int(reservation['guest_count']) < 100:
        raise ReportingBlocked('invalid_guest_count')  # PDF pp86–87, stricter than XSD.
    if not 0 <= int(reservation['total_huf']) < 1_000_000_000:
        raise ReportingBlocked('invalid_booking_amount')
    capacity = sum(int(x['ferohelyKapacitas']) for x in facts['foglaltLakoegysegek']['foglaltLakoegyseg'])
    units = facts['foglaltLakoegysegek']['foglaltLakoegyseg']
    if any(not 0 < int(x['ferohelyKapacitas']) < 100 for x in units) or int(reservation['guest_count']) > capacity + 2 * len(units):
        raise ReportingBlocked('invalid_capacity')
    arrival, departure = date.fromisoformat(reservation['arrival_date']), date.fromisoformat(reservation['departure_date'])
    if departure < arrival:
        raise ReportingBlocked('invalid_stay_dates')
    data = {k: facts[k] for k in ['garantaltFoglalas', 'vendegKuldoOrszaga', 'ertekesitesiCsatorna', 'foglaltLakoegysegek', 'piaciSzegmens']}
    data.update(foglalasiSzam=reservation['id'], esemenyLetrejotte=occurred_at,
                lemondva=reservation['status'] == 'cancelled', erkezes=str(arrival), tavozas=str(departure),
                foglalasIdopont=reservation['created_at'], foglalasBruttoOsszege=reservation['total_huf'],
                vendegszam=reservation['guest_count'])
    return {'foglalasEsemeny': data}


def validate_business(operation, payload, today):
    """Rules not expressed by XSD. Never substitute unavailable facts."""
    if operation == 'reservation':
        data = payload['foglalasEsemeny']
        arrival = date.fromisoformat(data['erkezes'])
        if arrival < today:
            raise ReportingBlocked('past_arrival_policy_conflict')  # pp54 vs87: no guessed exception.
    if operation == 'stay':
        events = payload['esemenyek']
        if not any(events.values()):
            raise ReportingBlocked('missing_actual_stay_event')
        for entries in events.values():
            for event in entries:
                when = datetime.fromisoformat(event['idopont'].replace('Z', '+00:00'))
                if when.tzinfo is None or when.date() > today or (today - when.date()).days > 366:
                    raise ReportingBlocked('invalid_event_time')
    if operation == 'daily_close':
        data = payload['napiFeltoltes']
        day = date.fromisoformat(data['lezartNap'])
        month = today.year * 12 + today.month - 15
        from calendar import monthrange
        lower = date((month - 1) // 12, (month - 1) % 12 + 1,
                     min(today.day, monthrange((month - 1) // 12, (month - 1) % 12 + 1)[1]))
        if day >= today or day < lower:
            raise ReportingBlocked('invalid_closing_date')
        classification = data['napiZarasBesorolas']
        if classification['besorolas'] == 'MODOSITO':
            require_fields(classification, ['jegyzokonyvAzonosito', 'indoklas'])
        for group in ('szobaAdatok', 'ferohelyAdatok'):
            if any(not isinstance(v, int) or isinstance(v, bool) or v < 0 for v in data[group].values()):
                raise ReportingBlocked('invalid_capacity')
    def walk(value):
        if isinstance(value, dict):
            if 'osszeg' in value and (not Decimal(str(value['osszeg'])).is_finite() or Decimal(str(value['osszeg'])) < 0):
                raise ReportingBlocked('invalid_amount')
            for v in value.values(): walk(v)
        elif isinstance(value, list):
            for v in value: walk(v)
    walk(payload)


def response(operation, xml, processing_id=None):
    root = parse_xml(xml)
    # SOAP faults are rejected; raw strings/guest values never become log messages.
    if root.find('.//{' + SOAP + '}Fault') is not None:
        return {'state': 'rejected', 'codes': ['soap_fault']}
    node = validate(operation, xml, response=True)
    def codes(parent, group):
        return [n.text or '' for n in parent.findall('.//{' + NAMESPACE + '}' + group + '/{' + NAMESPACE + '}hiba/{' + NAMESPACE + '}hibaKulcs')]
    if operation == 'verification':
        matches = [v for v in node if v.findtext('{' + NAMESPACE + '}feldolgozasAzonosito') == processing_id]
        if len(matches) != 1:
            raise ReportingBlocked('unmatched_processing_identifier')
        result = matches[0]
        status = result.findtext('{' + NAMESPACE + '}statusz')
        mapping = {'BEFOGADVA': 'accepted', 'TELJESEN_SIKERES': 'succeeded',
                   'TELJESEN_HIBAS': 'rejected', 'VIZSGALANDO': 'review_required', 'UJRA_KULDENDO': 'resend_required'}
        return {'state': mapping[status], 'codes': codes(result, 'hibaLista'), 'warnings': codes(result, 'figyelmeztetesLista')}
    receipt = node.findtext('{' + NAMESPACE + '}feldolgozasAzonosito')
    return {'state': 'accepted' if receipt else 'rejected', 'processing_id': receipt,
            'codes': codes(node, 'hibaLista'), 'warnings': codes(node, 'figyelmeztetesLista')}


def guest_hash(canonical_identity: str, permanent_bcrypt_salt: bytes):
    """PDF pp57–59: caller supplies verified identity, never automatic name reordering."""
    import bcrypt
    if not canonical_identity.strip() or not re.fullmatch(rb'\$2[aby]\$[0-9]{2}\$[./A-Za-z0-9]{22}', permanent_bcrypt_salt):
        raise ReportingBlocked('missing_guest_hash_inputs')
    digest = hashlib.sha256(canonical_identity.encode('utf-8')).hexdigest().encode('ascii')
    return bcrypt.hashpw(digest, permanent_bcrypt_salt).decode('ascii')[-31:]
