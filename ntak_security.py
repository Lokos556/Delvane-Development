"""Resolved NTAK offline primitives, not an approved WS-Security profile.

Authority: interface v9.07 sections3.2,6.1,9.1.7-8. No envelope assembly,
reference/digest selection, official response verifier or network implementation.
"""
import base64
import binascii
from dataclasses import dataclass
from datetime import datetime,timedelta,timezone
import json
from pathlib import Path
import re
import ssl
from urllib.parse import urlsplit
from cryptography import x509
from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives import hashes,serialization
from cryptography.hazmat.primitives.asymmetric import padding,rsa
from cryptography.x509.oid import NameOID,ObjectIdentifier
from lxml import etree
from government_security import credentials,CredentialError
from ntak_contracts import parse_xml,ContractError
from ntak_protocol import ReportingBlocked

DS='http://www.w3.org/2000/09/xmldsig#'
EXCLUSIVE='http://www.w3.org/2001/10/xml-exc-c14n#'
SIGNATURE_ALGORITHMS={
 'http://www.w3.org/2001/04/xmldsig-more#rsa-sha256':hashes.SHA256,
 'http://www.w3.org/2001/04/xmldsig-more#rsa-sha384':hashes.SHA384,
 'http://www.w3.org/2001/04/xmldsig-more#rsa-sha512':hashes.SHA512,
}


def exclusive_c14n(xml,*,inclusive_prefixes):
    """Primitive only. Caller must explicitly supply prefix policy; no wire default."""
    try:
        node=parse_xml(xml)
        if not isinstance(inclusive_prefixes,tuple) or any(
            p!='#default' and (not re.fullmatch(r'[A-Za-z_][A-Za-z0-9_.-]*',p) or p not in node.nsmap)
            for p in inclusive_prefixes):raise ValueError()
        if len(set(inclusive_prefixes))!=len(inclusive_prefixes):raise ValueError()
        return etree.tostring(node,method='c14n',exclusive=True,with_comments=False,inclusive_ns_prefixes=list(inclusive_prefixes))
    except (ContractError,ValueError,TypeError,etree.C14NError):
        raise ReportingBlocked('ntak_canonicalization_invalid') from None


def signed_info_bytes(xml,algorithm_uri,inclusive_prefixes):
    try:
        node=parse_xml(xml)
        if node.tag!='{'+DS+'}SignedInfo':raise ValueError()
        methods=node.findall('{'+DS+'}SignatureMethod')
        canon=node.findall('{'+DS+'}CanonicalizationMethod')
        if len(methods)!=1 or methods[0].get('Algorithm')!=algorithm_uri:raise ValueError()
        if len(canon)!=1 or canon[0].get('Algorithm')!=EXCLUSIVE:raise ValueError()
        prefixes=canon[0].findall('{'+EXCLUSIVE+'}InclusiveNamespaces')
        if len(prefixes)>1 or (prefixes[0].get('PrefixList','').split() if prefixes else [])!=list(inclusive_prefixes):raise ValueError()
    except (ContractError,ValueError,TypeError):raise ReportingBlocked('ntak_signed_info_invalid') from None
    if algorithm_uri not in SIGNATURE_ALGORITHMS or any(n.get('Algorithm','').lower().endswith('#sha1') for n in node.iter()):
        raise ReportingBlocked('HibasAlgoritmus')
    return exclusive_c14n(xml,inclusive_prefixes=inclusive_prefixes)


def signature_value(xml,key,*,algorithm_uri,inclusive_prefixes):
    """RSA SignatureValue primitive. Does NOT approve or verify the Reference list."""
    data=signed_info_bytes(xml,algorithm_uri,inclusive_prefixes)
    if not isinstance(key,rsa.RSAPrivateKey) or key.key_size<4096:raise ReportingBlocked('rsa_4096_required')
    return base64.b64encode(key.sign(data,padding.PKCS1v15(),SIGNATURE_ALGORITHMS[algorithm_uri]())).decode('ascii')


def certificate_validity(cert,*,now):
    if now.tzinfo is None or now.utcoffset() is None:raise ReportingBlocked('ntak_security_clock_invalid')
    if now<cert.not_valid_before_utc:raise ReportingBlocked('certificate_not_yet_valid')
    if now>=cert.not_valid_after_utc-timedelta(days=3):raise ReportingBlocked('certificate_expired_or_expiring')
    public=cert.public_key()
    if not isinstance(public,rsa.RSAPublicKey) or public.key_size<4096:raise ReportingBlocked('rsa_4096_required')


def certificate_binding(cert,registration_id,provider_vat):
    # p99 and p64: literal comparisons only. No guessed VAT/OID transformations.
    for oid,expected,code in ((NameOID.COMMON_NAME,registration_id,'ElteresCNadatok'),
        (ObjectIdentifier('2.5.4.97'),provider_vat,'ElteresOIDadatok')):
        values=cert.subject.get_attributes_for_oid(oid)
        if not expected or len(values)!=1 or values[0].value!=expected:raise ReportingBlocked(code)


def certificate_base64(cert):
    return base64.b64encode(cert.public_bytes(serialization.Encoding.DER)).decode('ascii')


def verify_signature_value(xml,value,cert,*,algorithm_uri,inclusive_prefixes,trusted_fingerprint,now):
    """Pinned offline primitive, NOT certificate-chain or SOAP-response verification."""
    data=signed_info_bytes(xml,algorithm_uri,inclusive_prefixes)
    if not trusted_fingerprint or cert.fingerprint(hashes.SHA256()).hex()!=trusted_fingerprint:
        raise ReportingBlocked('ntak_verification_trust_missing')
    certificate_validity(cert,now=now)
    try:
        if not isinstance(value,(str,bytes)) or len(value)>16384:raise ValueError()
        signature=base64.b64decode(value,validate=True)
        cert.public_key().verify(signature,data,padding.PKCS1v15(),SIGNATURE_ALGORITHMS[algorithm_uri]())
    except (InvalidSignature,ValueError,TypeError,binascii.Error):raise ReportingBlocked('ntak_signature_invalid') from None
    return True


def creation_window(created,*,now):
    """p63 maximum300s. Future timestamps fail closed; official future skew unknown."""
    if not isinstance(created,datetime) or not isinstance(now,datetime) or created.utcoffset() is None or now.utcoffset() is None:
        raise ReportingBlocked('ntak_security_clock_invalid')
    age=(now-created).total_seconds()
    if not 0<=age<=300:raise ReportingBlocked('ntak_timestamp_invalid')
    return age


@dataclass(frozen=True)
class Binding:
    organization_id:str
    property_id:str
    environment:str
    registration_id:str
    provider_vat:str
    software_id:str
    endpoint:str
    credential_reference:str

    def validate(self,approved_endpoint):
        if any(not isinstance(value,str) or not value for value in self.__dict__.values()):
            raise ReportingBlocked('ntak_endpoint_binding_invalid')
        try:
            parts=urlsplit(self.endpoint)
            port=parts.port
        except ValueError:raise ReportingBlocked('ntak_endpoint_binding_invalid') from None
        if (not approved_endpoint or self.endpoint!=approved_endpoint or self.environment not in ('test','production')
            or parts.scheme!='https' or not parts.hostname or port not in (None,443) or parts.username or parts.password
            or parts.query or parts.fragment or not self.organization_id or not self.property_id
            or not self.registration_id or not self.provider_vat or not self.software_id):
            raise ReportingBlocked('ntak_endpoint_binding_invalid')
        if not re.fullmatch(r'[A-Za-z0-9_-]{1,80}',self.credential_reference):raise ReportingBlocked('invalid_credential_reference')


def local_tls_context(root,binding,*,approved_endpoint,ca_file,now):
    """Operator binding/trust policy, not proof of NTAK issuance or interoperability.

    Explicitly supplied local CA material only; no downloads, socket or HTTP call.
    Metadata is checked before loading a key. Universal certificate used for TLS.
    """
    binding.validate(approved_endpoint)
    if ca_file is None:raise ReportingBlocked('ntak_verification_trust_missing')
    folder=(Path(root).resolve()/binding.credential_reference).resolve()
    metadata_path=(folder/'binding.json').resolve()
    if not folder.is_relative_to(Path(root).resolve()) or not metadata_path.is_relative_to(folder):
        raise ReportingBlocked('invalid_credential_reference')
    try:meta=json.loads(metadata_path.read_text(encoding='utf8'))
    except (OSError,ValueError):raise ReportingBlocked('ntak_credential_binding_missing') from None
    if not isinstance(meta,dict):raise ReportingBlocked('ntak_credential_binding_missing')
    expected={'system':'NTAK',**binding.__dict__}
    if any(meta.get(k)!=v for k,v in expected.items()):raise ReportingBlocked('ntak_credential_binding_mismatch')
    try:cert,key,paths=credentials(Path(root),binding.credential_reference,now=now,expiry_margin_days=3)
    except CredentialError as exc:raise ReportingBlocked(str(exc)) from None
    certificate_validity(cert,now=now)
    certificate_binding(cert,binding.registration_id,binding.provider_vat)
    if meta.get('certificate_sha256')!=cert.fingerprint(hashes.SHA256()).hex():raise ReportingBlocked('ntak_credential_binding_mismatch')
    try:
        context=ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
        context.minimum_version=ssl.TLSVersion.TLSv1_2 # Local hardening, not a claimed official minimum.
        context.verify_mode=ssl.CERT_REQUIRED;context.check_hostname=True
        context.load_verify_locations(cafile=str(ca_file))
        context.load_cert_chain(str(paths[0]),str(paths[1]))
        return context
    except (OSError,ValueError,ssl.SSLError):raise ReportingBlocked('ntak_verification_trust_missing') from None
