import io
import json
import sys
import urllib.error
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import app as rosa


def snapshot():
    return {
        "today":"2026-09-08","tomorrow":"2026-09-09","operating_mode":"observe",
        "reservations":[],"tasks":[],"maintenance":[],"readiness":[],"staff":[],"knowledge":[]
    }


def test_luna_fallback_uses_simple_responses_text_path(monkeypatch):
    monkeypatch.setattr(rosa,"AI_PROVIDER","openai")
    monkeypatch.setattr(rosa,"OPENAI_API_KEY","fake-key")
    monkeypatch.setattr(rosa,"OPENAI_MODEL","gpt-5.6-luna")
    captured={}
    class Resp:
        def __enter__(self): return self
        def __exit__(self,*a): return False
        def read(self):
            return json.dumps({"output":[{"type":"message","content":[{"type":"output_text","text":"Hello from Luna"}]}]}).encode()
    def fake_urlopen(req,timeout):
        captured["payload"]=json.loads(req.data.decode())
        return Resp()
    monkeypatch.setattr(rosa.urllib.request,"urlopen",fake_urlopen)
    out=rosa._openai_answer("What matters?","en",snapshot(),[])
    assert out=="Hello from Luna"
    payload=captured["payload"]
    assert payload["model"]=="gpt-5.6-luna"
    assert payload["text"]["format"]["type"]=="text"
    assert "json_schema" not in json.dumps(payload)
    assert isinstance(payload["input"],str)
    assert payload["instructions"].startswith("You are Rosa")
    assert rosa.AI_LAST_STATUS["state"]=="ok"


def test_luna_http_error_is_visible_but_never_contains_key(monkeypatch):
    monkeypatch.setattr(rosa,"AI_PROVIDER","openai")
    monkeypatch.setattr(rosa,"OPENAI_API_KEY","super-secret-test-key")
    body=io.BytesIO(json.dumps({"error":{"message":"Unsupported parameter for this request"}}).encode())
    def fail(req,timeout):
        raise urllib.error.HTTPError(req.full_url,400,"Bad Request",{},body)
    monkeypatch.setattr(rosa.urllib.request,"urlopen",fail)
    out=rosa._openai_answer("What matters?","en",snapshot(),[])
    assert out is None
    assert rosa.AI_LAST_STATUS["state"]=="error"
    assert "HTTP 400" in rosa.AI_LAST_STATUS["error"]
    assert "super-secret-test-key" not in rosa.AI_LAST_STATUS["error"]


def test_hotfix_docs_and_port():
    root=Path(__file__).resolve().parents[1]
    bat=(root/'START_ROSA.bat').read_text(encoding='utf-8')
    assert 'PORT=8819' in bat
    assert 'V2.10' in bat
    assert (root/'HOTFIX_V2642.md').exists()
