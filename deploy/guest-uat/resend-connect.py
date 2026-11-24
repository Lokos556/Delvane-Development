"""Loopback CONNECT listener in the app network namespace, with host-only egress."""

import asyncio
import ipaddress
import os
import socket
import sys


HOST = 'api.resend.com'
PORT = 3128
CONNECT = {f'CONNECT {HOST}:443 HTTP/1.{version}'.encode('ascii') for version in (0, 1)}


def public_ipv4(value):
    address = ipaddress.IPv4Address(value)
    if not address.is_global or address.is_multicast:
        raise ValueError('Expected a public unicast IPv4 address.')
    return str(address)


def allowed_client_hello(data):
    # This adapter uses Python's standard TLS ClientHello in one record. Fail
    # closed for fragmented or encrypted names and for another virtual host.
    def integer(buf):
        if not buf:
            raise ValueError
        return int.from_bytes(buf, 'big')

    if len(data) < 42 or data[0] != 1 or integer(data[1:4]) != len(data) - 4:
        return False
    end = 38  # Handshake header, legacy version, random.
    for width in (1, 2, 1):  # session ID, cipher suites, compression methods
        end += width + integer(data[end:end + width])
    if end + 2 >= len(data) or integer(data[end:end + 2]) != len(data) - end - 2:
        return False
    rest = data[end + 2:]
    hostname = HOST.encode()
    name = b'\x00' + len(hostname).to_bytes(2, 'big') + hostname
    expected_name = len(name).to_bytes(2, 'big') + name
    accepted = False
    while rest:
        if len(rest) < 4:
            return False
        kind, size = integer(rest[:2]), integer(rest[2:4])
        if size > len(rest) - 4 or kind in (0xFE0D, 0xFFCE):  # ECH and ESNI.
            return False
        if kind == 0:
            if accepted or rest[4:4 + size] != expected_name:
                return False
            accepted = True
        rest = rest[4 + size:]
    return accepted


async def copy_bytes(reader, writer):
    while chunk := await reader.read(16384):
        writer.write(chunk)
        await writer.drain()
    writer.write_eof()


async def serve(listener, addresses):
    active = 0

    async def connect(client, reply):
        nonlocal active
        if active >= 4:
            reply.close()
            return
        active += 1
        upstream = None
        try:
            request = await asyncio.wait_for(client.readuntil(b'\r\n\r\n'), 4)
            if request.split(b'\r\n', 1)[0] not in CONNECT:
                reply.write(b'HTTP/1.1 403 Forbidden\r\nContent-Length: 0\r\nConnection: close\r\n\r\n')
                await reply.drain()
                return
            reply.write(b'HTTP/1.1 200 Connection Established\r\n\r\n')
            await reply.drain()
            async with asyncio.timeout(4):
                header = await client.readexactly(5)
                length = int.from_bytes(header[3:], 'big')
                if header[:2] != b'\x16\x03' or not 1 <= length <= 16384:
                    return
                hello = await client.readexactly(length)
            if not allowed_client_hello(hello):
                return
            for address in addresses:
                try:
                    remote, upstream = await asyncio.wait_for(asyncio.open_connection(address, 443, family=socket.AF_INET), 2)
                except (OSError, TimeoutError):
                    continue
                break
            if upstream is None:
                return
            upstream.write(header + hello)
            await upstream.drain()
            async with asyncio.timeout(30):
                async with asyncio.TaskGroup() as tasks:
                    tasks.create_task(copy_bytes(client, upstream))
                    tasks.create_task(copy_bytes(remote, reply))
        except (OSError, TimeoutError, ValueError, asyncio.IncompleteReadError, asyncio.LimitOverrunError, ExceptionGroup):
            pass  # No headers, message bodies, or destinations from requests are logged.
        finally:
            if upstream:
                upstream.close()
            reply.close()
            active -= 1

    async with await asyncio.start_server(connect, sock=listener, limit=8192) as server:
        await server.serve_forever()


def main():
    namespace, uid, gid, *resolved = sys.argv[1:]
    addresses = tuple(map(public_ipv4, resolved))
    if not addresses or not all(item.isdecimal() and int(item) > 0 for item in (uid, gid)):
        raise SystemExit('Invalid isolated Resend proxy startup settings.')
    # Root setup pins the approved namespace before systemd applies the service
    # capability bound. The relay never needs ptrace access to another process.
    with open('/proc/self/ns/net', 'rb') as host, open(namespace, 'rb') as app:
        if os.path.samestat(os.fstat(host.fileno()), os.fstat(app.fileno())):
            raise SystemExit('The application must have its own network namespace.')
        os.setns(app.fileno(), os.CLONE_NEWNET)
        try:
            listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            listener.bind(('127.0.0.1', PORT))
        finally:
            os.setns(host.fileno(), os.CLONE_NEWNET)
    os.setgroups([])
    os.setresgid(int(gid), int(gid), int(gid))
    os.setresuid(int(uid), int(uid), int(uid))
    with open('/proc/self/status', encoding='ascii') as status:
        caps = {field: int(value.strip(), 16) for field, _, value in (line.partition(':') for line in status)
                if field in ('CapInh', 'CapPrm', 'CapEff', 'CapAmb')}
    if len(caps) != 4 or any(caps.values()):
        raise SystemExit('The Resend relay did not drop its startup capabilities.')
    asyncio.run(serve(listener, addresses))


if __name__ == '__main__':
    main()
