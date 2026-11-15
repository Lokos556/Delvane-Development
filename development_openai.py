"""Explicit OpenAI-only HTTPS transport for the otherwise offline local workspace.

Capture socket primitives before isolation. Never relax the process-wide guards;
only this transport may resolve/connect, only to api.openai.com:443 with verified TLS.
"""
import http.client
import io
import socket
import ssl
import urllib.error
from contextlib import contextmanager
from unittest.mock import patch

_RESOLVE = socket.getaddrinfo
_CONNECT = socket.socket.connect


class LimitedResponse(io.BytesIO):
    pass


def openai_only(request, timeout=12):
    if request.full_url != 'https://api.openai.com/v1/responses' or request.get_method() != 'POST':
        raise ValueError('Only the fixed OpenAI Responses endpoint is permitted')
    if not isinstance(request.data, bytes) or len(request.data)>64000:
        raise ValueError('OpenAI request exceeds the development payload limit')
    connection=http.client.HTTPSConnection('api.openai.com',443,timeout=min(timeout,12))
    raw=None
    try:
        for family, kind, protocol, _, address in _RESOLVE('api.openai.com',443,type=socket.SOCK_STREAM):
            raw=socket.socket(family,kind,protocol)
            raw.settimeout(min(timeout,12))
            try:
                _CONNECT(raw,address)
                connection.sock=ssl.create_default_context().wrap_socket(raw,server_hostname='api.openai.com')
                raw=None
                break
            except OSError:
                raw.close(); raw=None
        if connection.sock is None: raise OSError('OpenAI connection unavailable')
        connection.request('POST','/v1/responses',body=request.data,headers=dict(request.header_items()))
        response=connection.getresponse()
        payload=response.read(256001)
        if len(payload)>256000: raise ValueError('OpenAI response exceeds development limit')
        if response.status != 200:
            # Discard provider error body; never expose credentials or raw diagnostics.
            raise urllib.error.HTTPError(request.full_url,response.status,'OpenAI request failed',{},io.BytesIO())
        return LimitedResponse(payload)
    finally:
        connection.close()
        if raw: raw.close()


@contextmanager
def enabled(application, key, model):
    if not key or not model: raise ValueError('OpenAI opt-in requires a server-side key and model')
    with patch.object(application,'AI_PROVIDER','openai'), \
         patch.object(application,'OPENAI_API_KEY',key), \
         patch.object(application,'ASSISTANT_MODEL',model), \
         patch.object(application,'OPENAI_TRANSPORT',openai_only):
        yield
