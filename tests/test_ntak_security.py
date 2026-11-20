"""Synthetic primitives only: no claimed official signing profile or live TLS."""
from dataclasses import replace
from datetime import datetime,timedelta,timezone
import base64,json,ssl
from pathlib import Path
import pytest
from cryptography import x509
from cryptography.hazmat.primitives import hashes,serialization
from cryptography.hazmat.primitives.asymmetric import rsa,padding
from cryptography.x509.oid import NameOID,ObjectIdentifier
import ntak_security as s
from ntak_protocol import ReportingBlocked
from test_viza_security import handshake
from test_flutter_reservation_reception import client

NOW=datetime(2032,5,10,9,tzinfo=timezone.utc)
REG='MA99000001';VAT='12345678-1-12'

@pytest.fixture(scope='module')
def key():return rsa.generate_private_key(public_exponent=65537,key_size=4096)


def issue(key,*,cn=REG,vat=VAT,expires=60,ca=False,issuer=None,dns=None):
    attrs=[x509.NameAttribute(NameOID.COMMON_NAME,cn)]
    if vat is not None:attrs.append(x509.NameAttribute(ObjectIdentifier('2.5.4.97'),vat))
    subject=x509.Name(attrs)
    builder=x509.CertificateBuilder().subject_name(subject).issuer_name(issuer.subject if issuer else subject).public_key(key.public_key()).serial_number(x509.random_serial_number()).not_valid_before(datetime(2000,1,1,tzinfo=timezone.utc)).not_valid_after(NOW+timedelta(days=expires)).add_extension(x509.BasicConstraints(ca=ca,path_length=None),True)
    if dns:builder=builder.add_extension(x509.SubjectAlternativeName([x509.DNSName(dns)]),False)
    return builder.sign(key,hashes.SHA256())


def fragment(algorithm):
    # Deliberately a primitive fixture, not a complete/signable NTAK envelope.
    return (f'<ds:SignedInfo xmlns:ds="{s.DS}"><ds:CanonicalizationMethod Algorithm="{s.EXCLUSIVE}"/>'
        f'<ds:SignatureMethod Algorithm="{algorithm}"/><ds:Reference URI="#fictional-body">'
        '<ds:DigestMethod Algorithm="http://www.w3.org/2001/04/xmldsig-more#sha384"/>'
        '<ds:DigestValue>ZmFrZQ==</ds:DigestValue></ds:Reference></ds:SignedInfo>').encode()


@pytest.mark.parametrize('algorithm',list(s.SIGNATURE_ALGORITHMS))
def test_deterministic_signature_value_and_tamper(key,algorithm):
    xml=fragment(algorithm);cert=issue(key)
    signature=s.signature_value(xml,key,algorithm_uri=algorithm,inclusive_prefixes=())
    assert signature==s.signature_value(xml,key,algorithm_uri=algorithm,inclusive_prefixes=())
    key.public_key().verify(base64.b64decode(signature),s.exclusive_c14n(xml,inclusive_prefixes=()),padding.PKCS1v15(),s.SIGNATURE_ALGORITHMS[algorithm]())
    args={'algorithm_uri':algorithm,'inclusive_prefixes':(),'trusted_fingerprint':cert.fingerprint(hashes.SHA256()).hex(),'now':NOW}
    assert s.verify_signature_value(xml,signature,cert,**args)
    with pytest.raises(ReportingBlocked,match='ntak_signature_invalid'):s.verify_signature_value(xml.replace(b'ZmFrZQ==',b'YmFk'),signature,cert,**args)
    with pytest.raises(ReportingBlocked):s.verify_signature_value(xml,signature,cert,**{**args,'trusted_fingerprint':None})
    with pytest.raises(ReportingBlocked):s.verify_signature_value(xml,signature,cert,**{**args,'trusted_fingerprint':'00'*32})
    with pytest.raises(ReportingBlocked):s.verify_signature_value(xml,'not base64!',cert,**args)
    assert x509.load_der_x509_certificate(base64.b64decode(s.certificate_base64(cert)))==cert


def test_exclusive_canonicalization_unicode_comments_and_explicit_prefixes():
    xml='<p:x xmlns:p="urn:p" xmlns:u="urn:u" z="2" a="1">\u0150<!--hidden--></p:x>'.encode()
    assert s.exclusive_c14n(xml,inclusive_prefixes=())=='<p:x xmlns:p="urn:p" a="1" z="2">\u0150</p:x>'.encode()
    assert b'xmlns:u="urn:u"' in s.exclusive_c14n(xml,inclusive_prefixes=('u',))
    for raw,prefixes in [(b'<!DOCTYPE x [<!ENTITY a "secret">]><x>&a;</x>',()),(b'<x/>',('absent',)),(b'<x/>',None)]:
        with pytest.raises(ReportingBlocked):s.exclusive_c14n(raw,inclusive_prefixes=prefixes)


def test_no_sha1_or_implicit_canonicalization_profile(key):
    sha1='http://www.w3.org/2000/09/xmldsig#rsa-sha1'
    with pytest.raises(ReportingBlocked,match='HibasAlgoritmus'):s.signature_value(fragment(sha1),key,algorithm_uri=sha1,inclusive_prefixes=())
    alg=next(iter(s.SIGNATURE_ALGORITHMS));xml=fragment(alg)
    for value in (xml.replace(s.EXCLUSIVE.encode(),b'unknown'),xml.replace(b'more#sha384',b'more#sha1')):
        with pytest.raises(ReportingBlocked):s.signature_value(value,key,algorithm_uri=alg,inclusive_prefixes=())
    with pytest.raises(ReportingBlocked):s.signature_value(b'<unrelated/>',key,algorithm_uri=alg,inclusive_prefixes=())


@pytest.mark.parametrize('cn,vat,code',[('OTHER',VAT,'ElteresCNadatok'),(REG,'VATHU-12345678','ElteresOIDadatok'),(REG,None,'ElteresOIDadatok')])
def test_literal_certificate_binding_no_guessed_transform(key,cn,vat,code):
    with pytest.raises(ReportingBlocked,match=code):s.certificate_binding(issue(key,cn=cn,vat=vat),REG,VAT)


def test_three_day_expiry_and_timestamp_boundaries(key):
    cert=issue(key,expires=3)
    with pytest.raises(ReportingBlocked,match='certificate_expired'):s.certificate_validity(cert,now=NOW)
    s.certificate_validity(cert,now=NOW-timedelta(microseconds=1))
    with pytest.raises(ReportingBlocked):s.certificate_validity(issue(key,expires=-1),now=NOW)
    for seconds in (0,300):assert s.creation_window(NOW-timedelta(seconds=seconds),now=NOW)==seconds
    for seconds in (-1,301):
        with pytest.raises(ReportingBlocked):s.creation_window(NOW-timedelta(seconds=seconds),now=NOW)
    with pytest.raises(ReportingBlocked):s.creation_window(NOW.replace(tzinfo=None),now=NOW)


@pytest.fixture
def material(tmp_path,key):
    ca=issue(key,cn='Fictional CA',vat=None,ca=True)
    cert=issue(key,issuer=ca);folder=tmp_path/'fictional';folder.mkdir()
    (folder/'certificate.pem').write_bytes(cert.public_bytes(serialization.Encoding.PEM))
    (folder/'private-key.pem').write_bytes(key.private_bytes(serialization.Encoding.PEM,serialization.PrivateFormat.PKCS8,serialization.NoEncryption()))
    binding=s.Binding('fictional-org','fictional-property','test',REG,VAT,'FICTIONAL','https://pms.synthetic.invalid/ntak/v9','fictional')
    metadata={'system':'NTAK',**binding.__dict__,'certificate_sha256':cert.fingerprint(hashes.SHA256()).hex()}
    (folder/'binding.json').write_text(json.dumps(metadata),encoding='utf8')
    ca_file=tmp_path/'fictional-ca.pem';ca_file.write_bytes(ca.public_bytes(serialization.Encoding.PEM))
    return tmp_path,folder,binding,ca_file,ca


def test_tls_verified_chain_and_hostname_memory_only(material,key):
    root,folder,binding,ca_file,ca=material
    server_cert=issue(key,cn='pms.synthetic.invalid',vat=None,issuer=ca,dns='pms.synthetic.invalid')
    server_file=root/'fictional-server.pem';server_file.write_bytes(server_cert.public_bytes(serialization.Encoding.PEM))
    server=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER);server.load_cert_chain(str(server_file),str(folder/'private-key.pem'))
    server.verify_mode=ssl.CERT_REQUIRED;server.load_verify_locations(cafile=str(ca_file))
    ctx=s.local_tls_context(root,binding,approved_endpoint=binding.endpoint,ca_file=ca_file,now=NOW)
    assert ctx.verify_mode==ssl.CERT_REQUIRED and ctx.check_hostname and ctx.minimum_version>=ssl.TLSVersion.TLSv1_2
    assert handshake(ctx,server,'pms.synthetic.invalid')
    with pytest.raises(ssl.SSLCertVerificationError):handshake(ctx,server,'wrong.invalid')
    untrusted=s.local_tls_context(root,binding,approved_endpoint=binding.endpoint,ca_file=server_file,now=NOW)
    # Trusting a non-root leaf alone is not the required issuer chain.
    with pytest.raises(ssl.SSLCertVerificationError):handshake(untrusted,server,'pms.synthetic.invalid')


@pytest.mark.parametrize('field,value',[('property_id','other'),('organization_id','other'),('environment','production'),('endpoint','https://other.invalid/ntak/v9'),('software_id','OTHER')])
def test_operator_binding_denies_cross_scope_before_key_access(material,field,value,monkeypatch):
    root,_,binding,ca_file,_=material
    monkeypatch.setattr(s,'credentials',lambda *a,**kw:pytest.fail('Binding mismatch must precede reading a key'))
    altered=replace(binding,**{field:value})
    with pytest.raises(ReportingBlocked):s.local_tls_context(root,altered,approved_endpoint=binding.endpoint,ca_file=ca_file,now=NOW)


def test_missing_mismatched_and_expired_credentials(material,key):
    root,folder,binding,ca_file,_=material
    args={'approved_endpoint':binding.endpoint,'ca_file':ca_file,'now':NOW}
    with pytest.raises(ReportingBlocked):s.local_tls_context(root,binding,**{**args,'ca_file':None})
    (folder/'private-key.pem').unlink()
    with pytest.raises(ReportingBlocked,match='missing_certificate_or_key'):s.local_tls_context(root,binding,**args)
    other=rsa.generate_private_key(public_exponent=65537,key_size=4096)
    (folder/'private-key.pem').write_bytes(other.private_bytes(serialization.Encoding.PEM,serialization.PrivateFormat.PKCS8,serialization.NoEncryption()))
    with pytest.raises(ReportingBlocked,match='certificate_key_mismatch'):s.local_tls_context(root,binding,**args)
    (folder/'private-key.pem').write_bytes(key.private_bytes(serialization.Encoding.PEM,serialization.PrivateFormat.PKCS8,serialization.NoEncryption()))
    (folder/'certificate.pem').write_bytes(issue(key,expires=2).public_bytes(serialization.Encoding.PEM))
    with pytest.raises(ReportingBlocked,match='certificate_expired'):s.local_tls_context(root,binding,**args)


def test_security_failure_visible_in_task15_without_raw_detail(client):
    import app,ntak_reporting as r
    from test_ntak_reporting import configured,BASE,get
    _,job=configured(client)
    class Blocked:
        def exchange(self,*a,**kw):raise ReportingBlocked('certificate_expired_or_expiring')
    r.worker_once(app.db,transport=Blocked())
    assert get(job)['state']=='blocked' and get(job)['error_code']=='certificate_expired_or_expiring'
    data=client.get(BASE+f'/jobs/{job}/diagnostics').json()
    items=[v for result in data['results'] for v in result['diagnostics']]
    assert {'severity':'error','code':'certificate_expired_or_expiring','field':'GLOBAL','guidance':'connection'} in items
    from ntak_transport import UnresolvedOfficialTransport
    with pytest.raises(ReportingBlocked,match='signature_profile_unresolved'):UnresolvedOfficialTransport().exchange('reservation',b'',property_id='fictional-property',environment='test')


def test_short_key_and_invalid_endpoint_fail_closed():
    weak=rsa.generate_private_key(public_exponent=65537,key_size=2048)
    algorithm=next(iter(s.SIGNATURE_ALGORITHMS))
    with pytest.raises(ReportingBlocked,match='rsa_4096_required'):s.signature_value(fragment(algorithm),weak,algorithm_uri=algorithm,inclusive_prefixes=())
    for endpoint in ('http://pms.synthetic.invalid/ntak/v9','https://u:p@pms.synthetic.invalid/ntak/v9','https://[bad','https://pms.synthetic.invalid/ntak/v9?x=1'):
        binding=s.Binding('org','prop','test',REG,VAT,'FICTIONAL',endpoint,'fictional')
        with pytest.raises(ReportingBlocked):binding.validate(endpoint)


def test_documented_error_spelling_variants_and_malformed_operator_metadata(material):
    import ntak_diagnostics as d
    for code in ('ElteresCnAdatok','ElteresOidAdatok'):
        item=d.sanitize('reservation',[{'code':code,'field':'GLOBAL','severity':'error'}])[0]
        assert item['code']==code and item['guidance']=='connection'
    root,folder,binding,ca_file,_=material
    (folder/'binding.json').write_text('[]',encoding='utf8')
    with pytest.raises(ReportingBlocked,match='ntak_credential_binding_missing'):
        s.local_tls_context(root,binding,approved_endpoint=binding.endpoint,ca_file=ca_file,now=NOW)
