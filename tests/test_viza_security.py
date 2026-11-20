"""All credentials here are disposable synthetic test objects inside guarded temp storage."""
from dataclasses import replace
from datetime import datetime,timedelta,timezone
import base64,json,ssl,uuid
import pytest
from cryptography import x509
from cryptography.x509.oid import NameOID
from cryptography.hazmat.primitives import hashes,serialization
from cryptography.hazmat.primitives.asymmetric import rsa,padding
import viza_security as s

NOW=datetime(2032,5,10,9,tzinfo=timezone.utc)

def issue(key,cn,*,issuer=None,issuer_key=None,ca=False,expired=False,dns=None):
    name=x509.Name([x509.NameAttribute(NameOID.COMMON_NAME,cn)])
    b=x509.CertificateBuilder().subject_name(name).issuer_name(issuer.subject if issuer else name).public_key(key.public_key()).serial_number(x509.random_serial_number()).not_valid_before(NOW-timedelta(days=5)).not_valid_after(NOW+timedelta(days=-1 if expired else 60)).add_extension(x509.BasicConstraints(ca=ca,path_length=None),True)
    if dns:b=b.add_extension(x509.SubjectAlternativeName([x509.DNSName(dns)]),False)
    return b.sign(issuer_key or key,hashes.SHA256())

@pytest.fixture
def material(tmp_path):
    key=rsa.generate_private_key(public_exponent=65537,key_size=4096);cert=issue(key,'TEST0000')
    folder=tmp_path/'fictional';folder.mkdir()
    (folder/'private-key.pem').write_bytes(key.private_bytes(serialization.Encoding.PEM,serialization.PrivateFormat.PKCS8,serialization.NoEncryption()))
    (folder/'certificate.pem').write_bytes(cert.public_bytes(serialization.Encoding.PEM))
    bound=s.Binding('fictional-org','fictional-property','test','TEST0000','https://thf.invalid/ws','fictional')
    meta={'system':'VIZA','organization_id':bound.organization_id,'property_id':bound.property_id,'environment':bound.environment,'reporting_id':bound.reporting_id,'endpoint':bound.endpoint,'certificate_sha256':cert.fingerprint(hashes.SHA256()).hex()}
    (folder/'binding.json').write_text(json.dumps(meta),encoding='utf8')
    return tmp_path,folder,key,cert,bound

def test_exact_deterministic_signature_and_tamper(material):
    root,folder,key,cert,bound=material
    ids=[str(uuid.uuid4()),str(uuid.uuid4())];timestamp='2032-05-10T11:00:00.123+02:00'
    validation=s.property_validation(root,bound,ids,timestamp,now=NOW)
    assert validation.ellenorzoString=='|'.join([bound.reporting_id,*ids,timestamp])
    assert not validation.ellenorzoString.endswith(('\n','|'))
    assert validation==s.property_validation(root,bound,ids,timestamp,now=NOW)
    fp=cert.fingerprint(hashes.SHA256()).hex()
    assert s.verify_property(validation,bound,ids,timestamp,now=NOW,expected_fingerprint=fp)==fp
    # Independently verify message hashing once; no prehashed digest input.
    key.public_key().verify(base64.b64decode(validation.alairas),validation.ellenorzoString.encode('utf8'),padding.PKCS1v15(),hashes.SHA256())
    for altered_ids,altered_stamp in ((list(reversed(ids)),timestamp),(ids,timestamp.replace('.123','.124')),([str(uuid.uuid4()),ids[1]],timestamp)):
        with pytest.raises(s.SecurityBlocked):s.verify_property(validation,bound,altered_ids,altered_stamp,now=NOW,expected_fingerprint=fp)
    with pytest.raises(s.SecurityBlocked):s.verify_property(validation,bound,ids,timestamp,now=NOW,expected_fingerprint='00'*32)

@pytest.mark.parametrize('field,value',[('environment','production'),('property_id','other-property'),('reporting_id','OTHER000'),('organization_id','other-org'),('endpoint','https://other.invalid/ws')])
def test_binding_rejection(material,field,value):
    root,_,_,_,bound=material
    with pytest.raises(s.SecurityBlocked):s.load_bound(root,replace(bound,**{field:value}),now=NOW)

def test_key_expiry_cn_and_missing_trust(material):
    root,folder,key,cert,bound=material
    with pytest.raises(s.SecurityBlocked):s.tls_context(root,bound,None,None,now=NOW)
    (folder/'private-key.pem').write_bytes(rsa.generate_private_key(public_exponent=65537,key_size=4096).private_bytes(serialization.Encoding.PEM,serialization.PrivateFormat.PKCS8,serialization.NoEncryption()))
    with pytest.raises(s.SecurityBlocked,match='mismatch'):s.load_bound(root,bound,now=NOW)
    (folder/'private-key.pem').write_bytes(key.private_bytes(serialization.Encoding.PEM,serialization.PrivateFormat.PKCS8,serialization.NoEncryption()))
    for cn,expired in [('TEST0000',True),('OTHER000',False)]:
        altered=issue(key,cn,expired=expired);(folder/'certificate.pem').write_bytes(altered.public_bytes(serialization.Encoding.PEM))
        meta=json.loads((folder/'binding.json').read_text(encoding='utf8'));meta['certificate_sha256']=altered.fingerprint(hashes.SHA256()).hex();(folder/'binding.json').write_text(json.dumps(meta),encoding='utf8')
        with pytest.raises(s.SecurityBlocked):s.load_bound(root,bound,now=NOW)
    with pytest.raises(s.SecurityBlocked):s.DisabledOfficialTransport().exchange('anything',b'')
    with pytest.raises(s.SecurityBlocked):s.UnresolvedOuterSecurity().sign(b'')
    with pytest.raises(s.SecurityBlocked):s.UnresolvedOuterSecurity().verify_response(b'')

def handshake(client_context,server_context,hostname):
    ci,co,si,so=(ssl.MemoryBIO() for _ in range(4))
    client=client_context.wrap_bio(ci,co,server_side=False,server_hostname=hostname)
    server=server_context.wrap_bio(si,so,server_side=True)
    done=[False,False]
    for _ in range(30):
        for n,peer in enumerate((client,server)):
            try:peer.do_handshake();done[n]=True
            except (ssl.SSLWantReadError,ssl.SSLWantWriteError):pass
        packet=co.read()
        if packet:si.write(packet)
        packet=so.read()
        if packet:ci.write(packet)
        if all(done):return True
    raise AssertionError('In-memory TLS handshake did not finish')

def test_tls_trust_and_hostname_without_sockets(material):
    root,folder,key,_,bound=material
    # TLS uses the machine clock; make this peer chain valid around real UTC too.
    real_now=datetime.now(timezone.utc)
    ca_name=x509.Name([x509.NameAttribute(NameOID.COMMON_NAME,'Fictional root')])
    def tls_cert(cn,dns=None,issuer=None,ca=False):
        b=x509.CertificateBuilder().subject_name(x509.Name([x509.NameAttribute(NameOID.COMMON_NAME,cn)])).issuer_name(issuer.subject if issuer else ca_name).public_key(key.public_key()).serial_number(x509.random_serial_number()).not_valid_before(datetime(2000,1,1,tzinfo=timezone.utc)).not_valid_after(datetime(2100,1,1,tzinfo=timezone.utc)).add_extension(x509.BasicConstraints(ca=ca,path_length=None),True)
        if dns:b=b.add_extension(x509.SubjectAlternativeName([x509.DNSName(dns)]),False)
        return b.sign(key,hashes.SHA256())
    ca=tls_cert('Fictional root',ca=True);server_cert=tls_cert('thf.invalid','thf.invalid',ca)
    ca_file=root/'fictional-ca.pem';ca_file.write_bytes(ca.public_bytes(serialization.Encoding.PEM))
    server_file=root/'fictional-server.pem';server_file.write_bytes(server_cert.public_bytes(serialization.Encoding.PEM))
    server=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER);server.load_cert_chain(str(server_file),str(folder/'private-key.pem'))
    client=s.tls_context(root,bound,ca_file,ca_file,now=NOW)
    assert handshake(client,server,'thf.invalid')
    with pytest.raises(ssl.SSLCertVerificationError):handshake(client,server,'wrong.invalid')
    untrusted=ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    with pytest.raises(ssl.SSLCertVerificationError):handshake(untrusted,server,'thf.invalid')
    bad=ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT);bad.check_hostname=False
    with pytest.raises(s.SecurityBlocked):s.VerifiedHttpsTransport(bound,bad)
    with pytest.raises(s.SecurityBlocked):s.VerifiedHttpsTransport(bound,ssl.create_default_context())
    channel=s.VerifiedHttpsTransport(bound,client)
    with pytest.raises(s.SecurityBlocked):channel.exchange('anything',b'')
