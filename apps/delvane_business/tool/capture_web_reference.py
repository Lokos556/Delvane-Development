"""Render original static assets against synthetic GET fixtures, never the PMS DB.

Own loopback fixture server; browser uses a new temporary profile, a dead loopback
proxy for nonlocal traffic, DNS denial and request interception. No backend import.
Outputs ignored build/visual-reference screenshots, computed CSS and source catalogs.
"""
import base64
import hashlib
import http.client
import json
import os
from pathlib import Path
import secrets
import socket
import struct
import subprocess
import tempfile
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit

APP = Path(__file__).resolve().parents[1]
ROOT = APP.parents[1]
FIXTURES = json.loads((APP / "test/fixtures/web_reference.json").read_text(encoding="utf-8"))
ASSETS = {"/": "index.html", **{"/static/"+name: name for name in
    ("app.js", "v283.js", "styles.css", "delvane-icon.png", "index.html")}}


class FixtureServer(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_GET(self):
        path = urlsplit(self.path).path
        if path in FIXTURES:
            data = json.dumps(FIXTURES[path], ensure_ascii=False).encode()
            content_type = "application/json; charset=utf-8"
        elif path in ASSETS:
            target = ROOT / "static" / ASSETS[path]
            data = target.read_bytes()
            content_type = {".js":"text/javascript", ".css":"text/css", ".png":"image/png"}.get(target.suffix,"text/html")
        else:
            self.send_error(404)
            return
        self.send_response(200)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_POST(self):
        self.send_error(405)  # Screenshot host never executes business actions.


class CDP:
    def __init__(self, url, fixture_port):
        parsed = urlsplit(url)
        if parsed.hostname != "127.0.0.1":
            raise ValueError("Only the owned loopback debugging socket is allowed")
        self.sock = socket.create_connection((parsed.hostname, parsed.port), timeout=10)
        self.port = fixture_port
        self.counter = 0
        key = base64.b64encode(secrets.token_bytes(16)).decode()
        self.sock.sendall((f"GET {parsed.path} HTTP/1.1\r\nHost: 127.0.0.1:{parsed.port}\r\n"
                           f"Upgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: {key}\r\n"
                           "Sec-WebSocket-Version: 13\r\n\r\n").encode())
        response = bytearray()
        while not response.endswith(b"\r\n\r\n"):
            response.extend(self.sock.recv(1))
        expected = base64.b64encode(hashlib.sha1((key+"258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode()).digest())
        if b"101" not in response.splitlines()[0] or expected not in response:
            raise RuntimeError("Debugger handshake failed")

    def _read(self, count):
        data = bytearray()
        while len(data) < count:
            chunk = self.sock.recv(count-len(data))
            if not chunk:
                raise RuntimeError("Debugger closed")
            data.extend(chunk)
        return bytes(data)

    def send(self, method, params=None):
        self.counter += 1
        data = json.dumps({"id":self.counter,"method":method,"params":params or {}}).encode()
        length = len(data)
        header = bytes([0x81, 0x80 | (length if length<126 else 126 if length<65536 else 127)])
        if length>=126:
            header += struct.pack(">H" if length<65536 else ">Q",length)
        mask = secrets.token_bytes(4)
        self.sock.sendall(header+mask+bytes(value ^ mask[i%4] for i,value in enumerate(data)))
        return self.counter

    def call(self, method, params=None):
        request_id = self.send(method,params)
        while True:
            first, second = self._read(2)
            length = second & 127
            if length==126: length = struct.unpack(">H",self._read(2))[0]
            if length==127: length = struct.unpack(">Q",self._read(8))[0]
            mask = self._read(4) if second & 128 else None
            data = self._read(length)
            if mask: data = bytes(value ^ mask[i%4] for i,value in enumerate(data))
            if first & 15 != 1: continue
            item = json.loads(data)
            if item.get("method")=="Fetch.requestPaused":
                event = item["params"]
                target = urlsplit(event["request"]["url"])
                allowed = target.hostname=="127.0.0.1" and target.port==self.port and event["request"]["method"]=="GET"
                self.send("Fetch.continueRequest" if allowed else "Fetch.failRequest",
                          {"requestId":event["requestId"], **({} if allowed else {"errorReason":"BlockedByClient"})})
            if item.get("id")==request_id:
                if "error" in item: raise RuntimeError(item["error"]["message"])
                return item.get("result",{})

    def evaluate(self, expression):
        result = self.call("Runtime.evaluate",{"expression":expression,"awaitPromise":True,"returnByValue":True})
        if "exceptionDetails" in result:
            raise RuntimeError("Reference page evaluation failed")
        return result.get("result",{}).get("value")


def capture():
    browser = next((Path(path) for path in (
        r"C:\Program Files\Google\Chrome\Application\chrome.exe",
        r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe") if Path(path).is_file()),None)
    if browser is None: raise SystemExit("A local Chrome or Edge executable is needed for the source comparison")
    output = APP / "build/visual-reference"
    output.mkdir(parents=True,exist_ok=True)
    server = ThreadingHTTPServer(("127.0.0.1",0),FixtureServer)
    threading.Thread(target=server.serve_forever,daemon=True).start()
    with tempfile.TemporaryDirectory(prefix="delvane-visual-browser-") as profile:
        profile_root = Path(profile).resolve()
        if not profile_root.name.startswith("delvane-visual-browser-"):
            raise RuntimeError("Unexpected browser profile path")
        process = subprocess.Popen([str(browser),"--headless=new","--no-first-run","--no-default-browser-check",
            "--disable-background-networking","--disable-component-update","--disable-sync","--disable-extensions",
            "--disable-default-apps","--metrics-recording-only","--disable-breakpad",
            "--force-webrtc-ip-handling-policy=disable_non_proxied_udp",
            "--proxy-server=http://127.0.0.1:9","--proxy-bypass-list=127.0.0.1;localhost",
            "--host-resolver-rules=MAP * ~NOTFOUND, EXCLUDE 127.0.0.1, EXCLUDE localhost",
            "--remote-debugging-port=0",f"--user-data-dir={profile_root}","about:blank"],
            stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,
            creationflags=subprocess.CREATE_NO_WINDOW if os.name=="nt" else 0)
        cdp = None
        try:
            marker = profile_root / "DevToolsActivePort"
            for _ in range(100):
                if marker.exists(): break
                time.sleep(.1)
            port = int(marker.read_text().splitlines()[0])
            connection = http.client.HTTPConnection("127.0.0.1",port,timeout=10)
            connection.request("GET","/json/list")
            pages = json.loads(connection.getresponse().read())
            connection.close()
            cdp = CDP(next(x["webSocketDebuggerUrl"] for x in pages if x["type"]=="page"),server.server_port)
            cdp.call("Page.enable")
            cdp.call("Fetch.enable",{"patterns":[{"urlPattern":"*","requestStage":"Request"}]})
            cdp.call("Page.addScriptToEvaluateOnNewDocument",{"source":
                "sessionStorage.setItem('rosa_welcomed','1');sessionStorage.setItem('rosa_local_login_v2641','1');localStorage.setItem('rosa_language','en');"})
            cdp.call("Page.navigate",{"url":f"http://127.0.0.1:{server.server_port}/"})
            for _ in range(100):
                if cdp.evaluate("typeof ownerToday === 'function' && typeof V283 !== 'undefined'"): break
                time.sleep(.05)
            catalogs = cdp.evaluate("""JSON.stringify({languages:LANGUAGES,catalogs:Object.fromEntries(
              ['UI','T','I18N','V22_I18N','V23_I18N','V223_I18N','V25_I18N','V26_I18N','V262_ROUTE_I18N','V263_I18N','V28_I18N','V281_I18N','V283','FULL_LOCALE','OPERATIONAL_TRANSLATIONS'].map(k=>{
              try{return [k,eval(k)]}catch(_){return [k,{}]}}))})""")
            (output / "web-locales.json").write_text(catalogs,encoding="utf-8")
            results = []
            for width,height in ((1440,1000),(390,844)):
                cdp.call("Emulation.setDeviceMetricsOverride",{"width":width,"height":height,"deviceScaleFactor":1,"mobile":False})
                cdp.evaluate("ownerToday()")
                cdp.evaluate("new Promise(resolve=>setTimeout(resolve,180))")
                filename = f"web-today-{width}x{height}.png"
                (output / filename).write_bytes(base64.b64decode(cdp.call("Page.captureScreenshot",{"format":"png","captureBeyondViewport":False})["data"]))
                selectors = ["body",".side",".main",".side .nav",".top h1",".v25-metric-row",".v25-metric-row article",".v25-today-board",".v281-registration-strip",".property",".eyebrow",".v22-utility"]
                measurements = cdp.evaluate("""JSON.stringify(Object.fromEntries(%s.map(k=>{const e=document.querySelector(k);if(!e)return [k,null];const s=getComputedStyle(e),r=e.getBoundingClientRect();return [k,{x:r.x,y:r.y,width:r.width,height:r.height,background:s.background,color:s.color,font:s.font,fontFamily:s.fontFamily,fontSize:s.fontSize,padding:s.padding,border:s.border,borderRadius:s.borderRadius,gap:s.gap,display:s.display,columns:s.gridTemplateColumns}]})))""" % json.dumps(selectors))
                results.append({"viewport":[width,height],"measurements":json.loads(measurements)})
                for page, expression in (("intelligence","ownerIntelligence()"),("calendar","ownerReservations()"),("reception","ownerInbox()")):
                    cdp.evaluate(expression)
                    cdp.evaluate("new Promise(resolve=>setTimeout(resolve,100))")
                    (output / f"web-{page}-{width}x{height}.png").write_bytes(base64.b64decode(cdp.call("Page.captureScreenshot",{"format":"png","captureBeyondViewport":False})["data"]))
            (output / "computed-styles.json").write_text(json.dumps(results,indent=2),encoding="utf-8")
            print("Original web Today screenshots, computed CSS and catalogs captured with synthetic GET fixtures.")
        finally:
            if cdp:
                try: cdp.call("Browser.close")
                except (OSError,RuntimeError): pass
                cdp.sock.close()
            try: process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                process.terminate()
                process.wait(timeout=10)
            server.shutdown()
            server.server_close()


if __name__=="__main__":
    capture()
