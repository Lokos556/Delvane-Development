"""Offline v9 contract loading. No network, credentials, or database access.

Schemas are loaded directly from the supplied WSDLs, not reconstructed from PDF
examples. Schema compliance alone does not imply NTAK business-rule compliance.
"""
from copy import deepcopy
from functools import lru_cache
from pathlib import Path
import re

from lxml import etree

NAMESPACE = 'http://mtu.gov.hu/ntak/v9'
SOAP = 'http://schemas.xmlsoap.org/soap/envelope/'
XSD = 'http://www.w3.org/2001/XMLSchema'
CONTRACT_DIR = Path(__file__).resolve().parent / 'docs' / 'ntak' / 'v9'
BROWSER_PREAMBLE = b'This XML file does not appear to have any style information associated with it. The document tree is shown below.'
OPERATIONS = {
    'information': 'adatszolgaltatasKezdoDatum',
    'verification': 'ellenorzes',
    'stay': 'esemenyvezereltAdatkuldes',
    'reservation': 'foglalasEsemeny',
    'daily_close': 'napiZaras',
}


class ContractError(ValueError):
    """Safe error without submitted values or parser excerpts containing PII."""


def parse_xml(data: bytes):
    if not isinstance(data, bytes) or len(data) > 8 * 1024 * 1024:
        raise ContractError('Invalid XML size or encoding')
    try:
        root = etree.fromstring(data, etree.XMLParser(
            resolve_entities=False, load_dtd=False, no_network=True,
            huge_tree=False, recover=False))
    except etree.XMLSyntaxError:
        raise ContractError('Malformed XML') from None
    if root.getroottree().docinfo.doctype or any(isinstance(n, etree._Entity) for n in root.iter()):
        raise ContractError('DTD and entity declarations are forbidden')
    return root


@lru_cache(maxsize=1)
def contracts():
    result = {}
    for path in sorted(CONTRACT_DIR.glob('*.txt')):
        raw = path.read_bytes().removeprefix(b'\xef\xbb\xbf').lstrip()
        if raw.startswith(BROWSER_PREAMBLE):
            raw = raw[len(BROWSER_PREAMBLE):].lstrip()
        root = parse_xml(raw)
        if root.tag != '{http://schemas.xmlsoap.org/wsdl/}definitions':
            raise ContractError('Expected WSDL definitions')
        if root.findall('.//{http://schemas.xmlsoap.org/wsdl/}import'):
            raise ContractError('External WSDL dependencies are not permitted')
        schemas = root.findall('.//{' + XSD + '}schema')
        if len(schemas) != 1:
            raise ContractError('Expected one embedded XSD')
        schema = schemas[0]
        if any(schema.findall('.//{' + XSD + '}' + tag) for tag in ('import', 'include', 'redefine')):
            raise ContractError('External schema dependencies are not permitted')
        names = {n.get('name') for n in schema.findall('{' + XSD + '}element')}
        matches = [key for key, op in OPERATIONS.items() if op + 'Request' in names]
        if len(matches) != 1 or matches[0] in result:
            raise ContractError('Ambiguous WSDL operation')
        try:
            compiled = etree.XMLSchema(schema)
        except etree.XMLSchemaParseError:
            raise ContractError('Invalid embedded schema') from None
        result[matches[0]] = (compiled, schema, path.name)
    if set(result) != set(OPERATIONS):
        raise ContractError('Missing required v9 WSDL')
    return result


def validate(operation: str, data: bytes, *, response=False):
    if operation not in OPERATIONS:
        raise ContractError('Unknown operation')
    root = parse_xml(data)
    if root.tag == '{' + SOAP + '}Envelope':
        bodies = root.findall('{' + SOAP + '}Body')
        if len(bodies) != 1 or len(bodies[0]) != 1:
            raise ContractError('Expected one SOAP body payload')
        root = bodies[0][0]
    expected = '{' + NAMESPACE + '}' + OPERATIONS[operation] + ('Response' if response else 'Request')
    if root.tag != expected:
        raise ContractError('Unexpected message type')
    schema = contracts()[operation][0]
    if not schema.validate(root):
        raise ContractError('Message does not conform to the supplied v9 schema')
    return root


def envelope(payload):
    root = etree.Element('{' + SOAP + '}Envelope', nsmap={'soapenv': SOAP, 'v9': NAMESPACE})
    etree.SubElement(root, '{' + SOAP + '}Header')
    etree.SubElement(root, '{' + SOAP + '}Body').append(deepcopy(payload))
    return etree.tostring(root, encoding='UTF-8', xml_declaration=True)


def start_date_request(config: dict, message_id: str, sent_at: str) -> bytes:
    """Unsigned preview only. Missing identity values are never fabricated."""
    required = ('software_version', 'software_id', 'registration_id', 'provider_vat')
    if any(not str(config.get(k) or '').strip() for k in required):
        raise ContractError('Missing NTAK software or property identity configuration')
    vat = str(config['provider_vat']).strip()
    # Formatting an explicitly supplied Hungarian tax number preserves every digit.
    if re.fullmatch(r'[0-9]{11}', vat):
        vat = vat[:8] + '-' + vat[8] + '-' + vat[9:]
    root = etree.Element('{' + NAMESPACE + '}adatszolgaltatasKezdoDatumRequest', nsmap={'v9': NAMESPACE})
    for group, values in (
        ('uzenetAdatok', [('uzenetId', message_id), ('uzenetKuldesIdeje', sent_at)]),
        ('szoftverAdatok', [('szoftverVerzio', config['software_version']), ('szoftverAzonosito', config['software_id'])]),
        ('szallashely', [('szallasRegisztraciosSzam', config['registration_id']), ('szallashelySzolgaltatoAdoszam', vat)]),
    ):
        node = etree.SubElement(root, '{' + NAMESPACE + '}' + group)
        for name, value in values:
            etree.SubElement(node, '{' + NAMESPACE + '}' + name).text = str(value)
    xml = envelope(root)
    validate('information', xml)
    return xml


def audit():
    """Machine-readable local evidence; this does not contact any SOAP address."""
    import hashlib
    return {
        'network_contacted': False,
        'official_validation': False,
        'operations': {
            key: {
                'file': filename,
                'sha256': hashlib.sha256((CONTRACT_DIR / filename).read_bytes()).hexdigest(),
                'embedded_schema_compiles': True,
                'external_schema_dependencies': [],
                'elements': schema.xpath('./xs:element/@name', namespaces={'xs': XSD}),
                'enumerations': {
                    node.get('name'): node.xpath('.//xs:enumeration/@value', namespaces={'xs': XSD})
                    for node in schema.findall('{' + XSD + '}simpleType')
                    if node.findall('.//{' + XSD + '}enumeration')
                },
            }
            for key, (_, schema, filename) in contracts().items()
        },
    }


if __name__ == '__main__':
    import json
    print(json.dumps(audit(), ensure_ascii=True, indent=2))
