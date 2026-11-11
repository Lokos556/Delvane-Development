import json

import app as rosa


def test_ntak_v9_start_date_request_has_official_structure():
    connection = {
        "public_config_json": json.dumps({
            "registration_id": "SZ25003491",
            "software_id": "ROSA301001",
            "software_version": "2.10.1",
            "provider_vat": "12345678-2-42",
            "provider_name": "Casa Rosa",
            "property_name": "Casa Rosa Aqua",
        }),
        "system": "NTAK",
    }
    xml = rosa._ntak_start_date_request_xml(connection)
    assert '<v9:adatszolgaltatasKezdoDatumRequest>' in xml
    assert '<v9:software_id>' not in xml
    assert '<v9:szoftverAzonosito>ROSA301001</v9:szoftverAzonosito>' in xml
    assert '<v9:szallasRegisztraciosSzam>SZ25003491</v9:szallasRegisztraciosSzam>' in xml
    assert 'http://mtu.gov.hu/ntak/v9' in xml


def test_government_readiness_stays_locked_until_official_package_is_present():
    ntak = {
        "system": "NTAK",
        "public_config_json": json.dumps({
            "registration_id": "SZ25003491",
            "endpoint_url": "https://test.example.invalid/ntak",
        }),
    }
    result = rosa._government_test_readiness(ntak)
    assert result["ready"] is False
    assert "NTAK software ID" in result["missing"]
    assert "NTAK signing certificate" in result["missing"]
    assert result["requires_ws_security"] is True


def test_viza_readiness_requires_storage_forwarding_module_and_id():
    viza = {
        "system": "VIZA",
        "public_config_json": json.dumps({}),
    }
    result = rosa._government_test_readiness(viza)
    assert result["ready"] is False
    assert "VIZA storage-forwarding module" in result["missing"]
    assert "VIZA unique developer ID" in result["missing"]
    assert result["requires_id_scanner"] is True
