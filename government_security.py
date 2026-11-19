"""Reusable server-side credential checks. No key/CSR generation or network I/O."""
from datetime import datetime, timedelta, timezone
from pathlib import Path
import ssl
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa


class CredentialError(ValueError):
    pass


def credentials(root: Path, reference: str, *, now=None, expiry_margin_days=0):
    # Reference is an operator-created directory name, never a path from Flutter.
    import re
    if not re.fullmatch(r'[A-Za-z0-9_-]{1,80}', reference):
        raise CredentialError('invalid_credential_reference')
    root = root.resolve()
    folder = (root / reference).resolve()
    if not folder.is_relative_to(root):
        raise CredentialError('invalid_credential_reference')
    paths = [(folder / name).resolve() for name in ('certificate.pem', 'private-key.pem')]
    if any(not p.is_relative_to(folder) or not p.is_file() for p in paths):
        raise CredentialError('missing_certificate_or_key')
    try:
        certificate = x509.load_pem_x509_certificate(paths[0].read_bytes())
        key = serialization.load_pem_private_key(paths[1].read_bytes(), password=None)
    except (ValueError, TypeError, OSError):
        raise CredentialError('unreadable_certificate_or_key') from None
    if not isinstance(key, rsa.RSAPrivateKey) or key.key_size < 4096:
        raise CredentialError('rsa_4096_required')
    if certificate.public_key().public_bytes(serialization.Encoding.DER, serialization.PublicFormat.SubjectPublicKeyInfo) != key.public_key().public_bytes(serialization.Encoding.DER, serialization.PublicFormat.SubjectPublicKeyInfo):
        raise CredentialError('certificate_key_mismatch')
    now = now or datetime.now(timezone.utc)
    if now < certificate.not_valid_before_utc:
        raise CredentialError('certificate_not_yet_valid')
    if now >= certificate.not_valid_after_utc - timedelta(days=expiry_margin_days):
        raise CredentialError('certificate_expired_or_expiring')
    return certificate, key, paths


def certificate_status(root, reference, now=None):
    try:
        cert, _, _ = credentials(Path(root), reference, now=now, expiry_margin_days=3)
        return {'state': 'locally_valid', 'expires_at': cert.not_valid_after_utc.isoformat(),
                'sha256': cert.fingerprint(hashes.SHA256()).hex(), 'officially_validated': False}
    except CredentialError as exc:
        return {'state': str(exc), 'officially_validated': False}


def client_tls_context(root, reference, *, ca_file=None):
    _, _, paths = credentials(Path(root), reference, expiry_margin_days=3)
    context = ssl.create_default_context(cafile=ca_file)
    context.minimum_version = ssl.TLSVersion.TLSv1_2
    context.load_cert_chain(str(paths[0]), str(paths[1]))
    return context
