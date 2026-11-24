"""Run with a local Linux nginx binary. Uses only a synthetic loopback origin."""

from http.client import HTTPConnection
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
from threading import Thread
import time


TOKEN = 'S' * 43
HOST = 'guest.delvane.app'
APP = Path(__file__).resolve().parents[1] / 'deploy' / 'guest-uat' / 'nginx.conf'
WEBHOOK = '/api/public/guest-delivery/resend-webhook'


class Upstream(BaseHTTPRequestHandler):
    requests = []

    def handle_request(self):
        body = self.rfile.read(int(self.headers.get('Content-Length', '0')))
        self.requests.append((self.command, self.path, dict(self.headers), body))
        self.send_response(200)
        self.send_header('Set-Cookie', 'synthetic=ignore')
        self.send_header('Cache-Control', 'public, max-age=3600')
        self.end_headers()

    do_GET = do_HEAD = do_POST = handle_request

    def log_message(self, *_):
        pass


def request(path, method='GET', body=None, **headers):
    with socket.socket(socket.AF_UNIX) as client:
        client.settimeout(3)
        client.connect(str(path))
        http = HTTPConnection(HOST)
        http.sock = client
        http.request(method, headers.pop('target'), body=body,
                     headers={'Host': HOST, 'X-Forwarded-Proto': 'https', **headers})
        response = http.getresponse()
        response.read()
        return response.status, response.headers


def check(path):
    denied = [
        ('GET', '/'), ('POST', '/api/login'), ('GET', '/docs'), ('GET', '/openapi.json'),
        ('GET', '/health/ready'), ('GET', '/api/client/environment'), ('GET', '/api/reservations'),
        ('POST', '/api/government/ntak/properties/uat'), ('GET', '/api/government/viza/properties/uat'),
        ('GET', WEBHOOK), ('PUT', WEBHOOK), ('POST', WEBHOOK + '/'), ('POST', WEBHOOK + '?extra=1'),
        ('POST', '/api/public/guest-delivery/receipt'), ('GET', '/static/app.js'),
        ('GET', '/guest/checkin/' + TOKEN + '/'), ('GET', '/guest/checkin/short'),
        ('GET', '/guest/checkin/' + TOKEN + '?unexpected=1'), ('GET', '/guest//checkin/' + TOKEN),
        ('GET', '/guest/checkin/' + TOKEN + '/../../../api/reservations'),
        ('GET', '/guest/checkin/' + TOKEN + '%2f'), ('GET', '/static/%67uest-checkin.js'),
        ('PUT', '/api/public/checkin/' + TOKEN), ('POST', '/static/guest-checkin.js'),
        ('GET', '/static/guest-checkin.js?v=dev&x=1'),
    ]
    for method, target in denied:
        assert request(path, method, target=target)[0] == 404, (method, target)
    for wrong_host in ('operator.delvane.app', '127.0.0.1', 'guest.delvane.app.evil.invalid'):
        assert request(path, target='/guest/checkin/' + TOKEN, Host=wrong_host)[0] == 404
    assert request(path, target='/guest/checkin/' + TOKEN, **{'X-Forwarded-Proto': 'http'})[0] == 404
    status, headers = request(path, 'POST', b'{}', target=WEBHOOK)
    assert status == 401 and headers['Cache-Control'] == 'no-store'
    assert not Upstream.requests

    for method, target in [('GET', '/guest/checkin/' + TOKEN),
                           ('HEAD', '/guest/checkin/' + TOKEN),
                           ('GET', '/api/public/checkin/' + TOKEN),
                           ('GET', '/static/delvane-icon.png'),
                           ('GET', '/static/guest-checkin.css?v=20261114-forms-nav'),
                           ('GET', '/static/guest-checkin.js'),
                           ('GET', '/static/guest-checkin-i18n.js')]:
        status, headers = request(path, method, target=target)
        assert status == 200 and headers['Cache-Control'] == 'no-store'
        assert headers['Referrer-Policy'] == 'no-referrer' and headers['Set-Cookie'] is None
    assert request(path, 'POST', b'{}', target='/api/public/checkin/' + TOKEN, **{
        'Content-Type': 'application/json', 'Cookie': 'synthetic-owner=test',
        'Authorization': 'synthetic-ignored', 'CF-Connecting-IP': '192.0.2.42',
        'X-Forwarded-For': '192.0.2.99', 'X-Rosa-CSRF': 'synthetic-ignored'})[0] == 200
    _, _, headers, body = Upstream.requests[-1]
    assert body == b'{}' and headers['Content-Type'] == 'application/json'
    assert headers['Host'] == HOST and headers['X-Forwarded-For'] == '192.0.2.42'
    assert {'Cookie', 'Authorization', 'X-Rosa-CSRF'}.isdisjoint(headers)
    assert request(path, 'POST', b'{}' * 32769, target='/api/public/checkin/' + TOKEN)[0] == 413
    raw = '{ "type": "simulated",\n  "guest": "Ő" }\n'.encode()
    svix = {'Svix-Id': 'msg_test', 'Svix-Timestamp': '1785000000', 'Svix-Signature': 'v1,test v1,rollover'}
    for missing in svix:
        assert request(path, 'POST', raw, target=WEBHOOK, **{k: v for k, v in svix.items() if k != missing})[0] == 401
    assert request(path, 'POST', raw, target=WEBHOOK, Host='operator.delvane.app', **svix)[0] == 404
    assert request(path, 'POST', raw, target=WEBHOOK, **svix, **{'X-Forwarded-Proto': 'http'})[0] == 404
    assert request(path, 'POST', b'x' * 65537, target=WEBHOOK, **svix)[0] == 413
    status, headers = request(path, 'POST', raw, target=WEBHOOK, **svix, Cookie='synthetic=never', Authorization='ignored')
    assert status == 200 and headers['Cache-Control'] == 'no-store' and headers['Set-Cookie'] is None
    _, uri, sent, forwarded = Upstream.requests[-1]
    assert uri == WEBHOOK and forwarded == raw and all(sent[k] == v for k, v in svix.items())
    assert 'Authorization' not in sent and 'Cookie' not in sent
    assert request(path, target='/static/guest-checkin.css', **svix)[0] == 200
    assert not set(svix).intersection(Upstream.requests[-1][2])
    print(f'Guest origin smoke passed ({len(denied)} blocked route/method cases and raw-byte Svix header forwarding).')


def main():
    nginx = str(Path(sys.argv[1]).resolve())
    with tempfile.TemporaryDirectory(prefix='delvane-guest-origin-') as tmp, ThreadingHTTPServer(('127.0.0.1', 0), Upstream) as upstream:
        work = Path(tmp)
        config = APP.read_text().replace('/run/delvane-guest-uat', tmp).replace(
            '127.0.0.1:8080', f'127.0.0.1:{upstream.server_port}')
        # Keep distro-specific temp paths in the disposable directory.
        temp_paths = ('client_body', 'proxy', 'fastcgi', 'uwsgi', 'scgi')
        config = config.replace('http {', 'http {\n' + '\n'.join(
            f'    {name}_temp_path {tmp}/{name};' for name in temp_paths))
        path = work / 'nginx.conf'
        path.write_text(config)
        command = [nginx, '-e', '/dev/null', '-p', tmp + '/', '-c', str(path)]
        subprocess.run(command + ['-t'], check=True)
        Thread(target=upstream.serve_forever, daemon=True).start()
        worker = subprocess.Popen(command)
        try:
            sock = work / 'origin.sock'
            for _ in range(30):
                if sock.exists() or worker.poll() is not None:
                    break
                time.sleep(.1)
            assert worker.poll() is None and sock.is_socket()
            check(sock)
        finally:
            worker.terminate()
            worker.wait(timeout=5)
            upstream.shutdown()


if __name__ == '__main__':
    main()
