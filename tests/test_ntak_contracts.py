"""Offline contract regressions, not official NTAK validation or transmission."""
import json
import pytest
from lxml import etree
import app
from ntak_contracts import ContractError, NAMESPACE, OPERATIONS, contracts, parse_xml, start_date_request, validate

ID = '00000000-0000-4000-8000-000000000001'
CONFIG = {'registration_id': 'MA99000001', 'provider_vat': '12345678112',
          'software_id': 'FICTIONALTEST', 'software_version': '1.0'}


def test_all_supplied_contracts_compile_without_external_dependencies():
    assert set(contracts()) == set(OPERATIONS)


def test_existing_preview_uses_schema_and_does_not_invent_identity():
    xml = app._ntak_start_date_request_xml({'public_config_json': json.dumps(CONFIG)})
    root = validate('information', xml.encode())
    assert root.find('.//{' + NAMESPACE + '}szallashelySzolgaltatoAdoszam').text == '12345678-1-12'
    assert 'szallasNev' not in xml and 'szallashelySzolgaltatoNev' not in xml
    for field in CONFIG:
        cfg = dict(CONFIG); cfg.pop(field)
        with pytest.raises(app.HTTPException) as error:
            app._ntak_start_date_request_xml({'public_config_json': json.dumps(cfg)})
        assert error.value.status_code == 422


@pytest.mark.parametrize('operation', ['information', 'reservation', 'stay', 'daily_close'])
def test_submission_receipt_schema(operation):
    name = OPERATIONS[operation] + 'Response'
    xml = f'<{name} xmlns="{NAMESPACE}"><feldolgozasAzonosito>{ID}</feldolgozasAzonosito></{name}>'.encode()
    validate(operation, xml, response=True)
    with pytest.raises(ContractError):
        validate(operation, xml.replace(ID.encode(), b'not-a-uuid'), response=True)


@pytest.mark.parametrize('status', ['BEFOGADVA','TELJESEN_HIBAS','VIZSGALANDO','TELJESEN_SIKERES','UJRA_KULDENDO'])
def test_verification_status_schema(status):
    xml = f'<ellenorzesResponse xmlns="{NAMESPACE}"><uzenetValaszok><feldolgozasAzonosito>{ID}</feldolgozasAzonosito><statusz>{status}</statusz><figyelmeztetesLista/><hibaLista/></uzenetValaszok></ellenorzesResponse>'.encode()
    validate('verification', xml, response=True)
    # PDF p46 requires this result, but the supplied verification XSD forbids it.
    with pytest.raises(ContractError):
        validate('verification', xml.replace(b'</uzenetValaszok>', b'<elvartAdatszolgaltatasKezdoDatuma>2026-01-01</elvartAdatszolgaltatasKezdoDatuma></uzenetValaszok>'), response=True)


def test_unicode_is_preserved_in_schema_permitted_error_text():
    text = 'Árvíztűrő tükörfúrógép – Ősszel érkezők'
    xml = f'<foglalasEsemenyResponse xmlns="{NAMESPACE}"><hibaLista><hiba><mezoNeve>field</mezoNeve><kuldottErtek>{text}</kuldottErtek><hibaKulcs>Test</hibaKulcs><hibaUzenet>{text}</hibaUzenet></hiba></hibaLista><figyelmeztetesLista/></foglalasEsemenyResponse>'.encode()
    root = validate('reservation', xml, response=True)
    assert root.find('.//{' + NAMESPACE + '}hibaUzenet').text == text


@pytest.mark.parametrize('xml', [
    b'<!DOCTYPE a [<!ENTITY test "secret">]><a>&test;</a>',
    b'<!DOCTYPE a SYSTEM "https://example.invalid/external.dtd"><a/>',
    b'<a>', b'not xml', b'<!DOCTYPE a [<!ENTITY x SYSTEM "file:///secret">]><a>&x;</a>',
])
def test_untrusted_xml_is_rejected_without_entity_resolution(xml):
    with pytest.raises(ContractError):
        parse_xml(xml)


def test_unofficial_fields_and_wrong_message_types_rejected():
    xml = start_date_request(CONFIG, ID, '2026-01-01T00:00:00Z')
    with pytest.raises(ContractError):
        validate('reservation', xml)
    root = parse_xml(xml)
    group = root.find('.//{' + NAMESPACE + '}szallashely')
    etree.SubElement(group, '{' + NAMESPACE + '}szallasNev').text = 'Fictional property'
    with pytest.raises(ContractError):
        validate('information', etree.tostring(root))
