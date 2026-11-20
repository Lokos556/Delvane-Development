"""VIZA property signature and verified-channel boundaries. No live connector exists."""
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Protocol
from urllib.parse import urlsplit
import base64,json,re,ssl
from cryptography import x509
from cryptography.hazmat.primitives import hashes,serialization
from cryptography.hazmat.primitives.asymmetric import padding
from cryptography.x509.oid import NameOID
from government_security import credentials,CredentialError
import viza_contracts as c

class SecurityBlocked(ValueError):pass
class DefinitelyNotSent(Exception):pass
class OutcomeUncertain(Exception):pass
class PermanentFailure(Exception):pass

@dataclass(frozen=True)
class Binding:
    organization_id:str
    property_id:str
    environment:str
    reporting_id:str
    endpoint:str
    credential_reference:str

    def validate(self):
        parsed=urlsplit(self.endpoint)
        if self.environment not in ('test','staging','production'):raise SecurityBlocked('invalid_environment')
        if not re.fullmatch('[A-Za-z0-9]{8}',self.reporting_id):raise SecurityBlocked('invalid_property_reporting_id')
        try:parsed.port
        except ValueError:raise SecurityBlocked('invalid_endpoint_port') from None
        if parsed.scheme!='https' or not parsed.hostname or parsed.username or parsed.password or parsed.query or parsed.fragment:raise SecurityBlocked('verified_https_required')
        if not self.organization_id or not self.property_id:raise SecurityBlocked('missing_property_binding')
        return self


def check_string(reporting_id,arrivals,exact_timestamp):
    if not re.fullmatch('[A-Za-z0-9]{8}',reporting_id) or not 1<=len(arrivals)<=10:raise SecurityBlocked('invalid_property_validation_fields')
    if len(set(arrivals))!=len(arrivals) or any(not re.fullmatch(c.UUID_PATTERN,a) for a in arrivals):raise SecurityBlocked('invalid_arrival_uuid')
    if not isinstance(exact_timestamp,str) or not re.fullmatch(r'[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(?:\.[0-9]+)?(?:Z|[+-][0-9]{2}:[0-9]{2})',exact_timestamp):raise SecurityBlocked('invalid_exact_timestamp')
    try:
        dt=datetime.fromisoformat(exact_timestamp.replace('Z','+00:00'))
        if dt.utcoffset() is None:raise ValueError()
    except (ValueError,TypeError):raise SecurityBlocked('invalid_exact_timestamp') from None
    # Retain the supplied lexical timestamp, including offset/fractional precision.
    value='|'.join([reporting_id,*arrivals,exact_timestamp])
    if any(ch in value for ch in ('\n','\r')):raise SecurityBlocked('invalid_check_string')
    return value


def load_bound(root,binding,*,now=None):
    binding.validate()
    # Validate service/property/environment metadata BEFORE opening any key.
    folder=Path(root).resolve()/binding.credential_reference
    if not re.fullmatch('[A-Za-z0-9_-]{1,80}',binding.credential_reference) or not folder.resolve().is_relative_to(Path(root).resolve()):raise SecurityBlocked('invalid_credential_reference')
    try:
        meta_path=(folder/'binding.json').resolve()
        if not meta_path.is_relative_to(folder.resolve()):raise ValueError()
        metadata=json.loads(meta_path.read_text(encoding='utf8'))
    except (OSError,ValueError):raise SecurityBlocked('missing_viza_credential_binding') from None
    expected={'system':'VIZA','organization_id':binding.organization_id,'property_id':binding.property_id,'environment':binding.environment,'reporting_id':binding.reporting_id,'endpoint':binding.endpoint}
    if any(metadata.get(k)!=v for k,v in expected.items()):raise SecurityBlocked('credential_binding_mismatch')
    try:cert,key,paths=credentials(Path(root),binding.credential_reference,now=now,expiry_margin_days=0)
    except CredentialError as exc:raise SecurityBlocked(str(exc)) from None
    names=cert.subject.get_attributes_for_oid(NameOID.COMMON_NAME)
    if len(names)!=1 or names[0].value!=binding.reporting_id:raise SecurityBlocked('certificate_property_cn_mismatch')
    if metadata.get('certificate_sha256')!=cert.fingerprint(hashes.SHA256()).hex():raise SecurityBlocked('certificate_binding_fingerprint_mismatch')
    return cert,key,paths


def property_validation(root,binding,arrivals,exact_timestamp,*,now=None):
    cert,key,_=load_bound(root,binding,now=now)
    value=check_string(binding.reporting_id,arrivals,exact_timestamp)
    # sign(message, SHA256) hashes once, matching openssl dgst -sha256 -sign.
    signature=key.sign(value.encode('utf8'),padding.PKCS1v15(),hashes.SHA256())
    return c.Validation(ellenorzoString=value,alairoTanusitvany=base64.b64encode(cert.public_bytes(serialization.Encoding.DER)).decode('ascii'),alairas=base64.b64encode(signature).decode('ascii'))


def verify_property(validation,binding,arrivals,exact_timestamp,*,now=None,expected_fingerprint=None):
    binding.validate()
    if not expected_fingerprint:raise SecurityBlocked('missing_verification_trust')
    if validation.ellenorzoString!=check_string(binding.reporting_id,arrivals,exact_timestamp):raise SecurityBlocked('property_check_string_mismatch')
    try:
        cert=x509.load_der_x509_certificate(base64.b64decode(validation.alairoTanusitvany,validate=True))
        if cert.fingerprint(hashes.SHA256()).hex()!=expected_fingerprint:raise ValueError()
        names=cert.subject.get_attributes_for_oid(NameOID.COMMON_NAME)
        now=now or datetime.now(timezone.utc)
        if len(names)!=1 or names[0].value!=binding.reporting_id or not cert.not_valid_before_utc<=now<cert.not_valid_after_utc:raise ValueError()
        cert.public_key().verify(base64.b64decode(validation.alairas,validate=True),validation.ellenorzoString.encode('utf8'),padding.PKCS1v15(),hashes.SHA256())
    except Exception:raise SecurityBlocked('invalid_property_signature') from None
    return cert.fingerprint(hashes.SHA256()).hex()


def tls_context(root,binding,root_ca,issuer_ca,*,now=None):
    _,_,paths=load_bound(root,binding,now=now)
    try:
        authorities=[]
        for path in (root_ca,issuer_ca):
            if not path:raise ValueError()
            cert=x509.load_pem_x509_certificate(Path(path).read_bytes())
            if not cert.extensions.get_extension_for_class(x509.BasicConstraints).value.ca:raise ValueError()
            authorities.append(cert.public_bytes(serialization.Encoding.PEM).decode('ascii'))
        context=ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
        context.load_verify_locations(cadata='\n'.join(authorities))
        context.minimum_version=ssl.TLSVersion.TLSv1_2
        context.verify_mode=ssl.CERT_REQUIRED;context.check_hostname=True
        context.load_cert_chain(str(paths[0]),str(paths[1]))
        context._viza_binding=binding
        context._viza_trust_present=True
        return context
    except (OSError,ValueError,ssl.SSLError,x509.ExtensionNotFound):raise SecurityBlocked('missing_or_invalid_thf_trust') from None

class OuterSecurity(Protocol):
    def sign(self,envelope:bytes,*,binding:Binding,wire_timestamp:str)->bytes:...
    def verify_response(self,envelope:bytes,*,binding:Binding,request_digest:str)->bytes:...

class UnresolvedOuterSecurity:
    def sign(self,*a,**kw):raise SecurityBlocked('Q2_outer_ws_security_unresolved')
    def verify_response(self,*a,**kw):raise SecurityBlocked('Q2_response_security_unresolved')

class Transport(Protocol):
    mode:str
    def exchange(self,operation:str,body:bytes,*,binding:Binding,wire_timestamp:str)->bytes:...

class DisabledOfficialTransport:
    mode='disabled'
    def exchange(self,*a,**kw):raise SecurityBlocked('official_transmission_disabled')

class VerifiedHttpsTransport:
    """Foundation only: validate TLS and security dependencies. No HTTP implementation."""
    mode='disabled'
    def __init__(self,binding,context,security=None):
        binding.validate()
        if getattr(context,'_viza_binding',None)!=binding or not getattr(context,'_viza_trust_present',False):raise SecurityBlocked('missing_bound_thf_trust')
        if context.verify_mode!=ssl.CERT_REQUIRED or not context.check_hostname or context.minimum_version<ssl.TLSVersion.TLSv1_2:raise SecurityBlocked('unsafe_tls_configuration')
        self.binding=binding;self.context=context;self.security=security or UnresolvedOuterSecurity()
    def exchange(self,*a,**kw):raise SecurityBlocked('official_transmission_disabled')

class OfflineMockTransport:
    """Injected by offline tests only; never selectable from configuration/API."""
    mode='mock'
    def __init__(self,handler):self.handler=handler;self.calls=[]
    def exchange(self,operation,body,*,binding,wire_timestamp):
        binding.validate();self.calls.append((operation,binding,wire_timestamp))
        return self.handler(operation,body,binding,wire_timestamp)
