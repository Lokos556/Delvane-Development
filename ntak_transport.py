"""Transport boundary. Official traffic remains explicitly unavailable.

Mock adapters are injected into the worker only by offline tests, never selected
through environment variables or an owner endpoint.
"""
from typing import Protocol
from ntak_protocol import ReportingBlocked


class SoapTransport(Protocol):
    def exchange(self, operation: str, xml: bytes, *, property_id: str, environment: str) -> bytes: ...


class UnresolvedOfficialTransport:
    def exchange(self, operation, xml, *, property_id, environment):
        raise ReportingBlocked('signature_profile_unresolved')


def require_resolved_operation(operation):
    if operation == 'information':
        raise ReportingBlocked('information_response_contract_unresolved')


class SignatureProfile(Protocol):
    """Future approved implementation must sign using the existing matching key.

    PDF pp61–63 disagree on required references. The application never selects a
    profile implicitly; there is deliberately no production fallback signer.
    """
    def sign(self, envelope: bytes, certificate, private_key) -> bytes: ...
