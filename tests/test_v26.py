import json
import sys
from pathlib import Path

from fastapi.testclient import TestClient

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import app as rosa


def fresh(tmp_path, monkeypatch):
    db_file = tmp_path / "v26.db"
    monkeypatch.setattr(rosa, "DB_PATH", db_file)
    rosa.init_db(reset=True)
    return TestClient(rosa.app)


def login(c, email="owner@demo.rosa", password="rosa-owner"):
    r=c.post("/api/login",json={"email":email,"password":password})
    assert r.status_code==200,r.text
    c.headers.update({"X-Rosa-CSRF":r.json()["csrf_token"]})


def new_chat(c, text, conversation_id=None, language="en"):
    r=c.post("/api/rosa/chat",json={"message":text,"conversation_id":conversation_id,"language":language})
    assert r.status_code==200,r.text
    return r.json()


def test_v26_schema_provider_and_persistent_chat(tmp_path, monkeypatch):
    c=fresh(tmp_path,monkeypatch); login(c)
    with rosa.db() as con:
        assert con.execute("SELECT * FROM schema_migrations WHERE version=2600").fetchone()["name"]=="rosa_intelligence"
        for table in ("rosa_conversations","rosa_chat_messages","rosa_proposals"):
            assert con.execute("SELECT name FROM sqlite_master WHERE type='table' AND name=?",(table,)).fetchone()
    provider=c.get("/api/rosa/provider").json()
    assert provider["provider"] in {"local","openai"}
    first=new_chat(c,"Who arrives tomorrow?")
    cid=first["conversation_id"]
    detail=c.get(f"/api/rosa/conversations/{cid}").json()
    assert len(detail["messages"])==2
    assert detail["messages"][0]["role"]=="user"
    assert detail["messages"][1]["role"]=="rosa"
    assert "arrivals" in detail["messages"][1]["content"].lower()
    second=new_chat(c,"What about Terra?",cid)
    assert second["conversation_id"]==cid
    again=c.get(f"/api/rosa/conversations/{cid}").json()
    assert len(again["messages"])==4
    assert again["conversation"]["context"]["last_property_name"]=="Terra"


def test_observe_action_is_simulated_and_does_not_reassign(tmp_path, monkeypatch):
    # Owner assistant is read-only in every existing operating/authority mode.
    c=fresh(tmp_path,monkeypatch); login(c)
    assert c.patch('/api/organization/mode',json={'mode':'observe'}).status_code==200
    with rosa.db() as con:
        before=[dict(r) for r in con.execute('SELECT id,assigned_to FROM work_tasks ORDER BY id')]
        prior=con.execute('SELECT COUNT(*) c FROM rosa_actions').fetchone()['c']
    out=new_chat(c,"Move today's cleaning from Anna to Erika.")
    assert out['proposals']==[] and out['read_only'] and out['route']=='read_only'
    assert c.post('/api/rosa/proposals/historical/resolve',json={'decision':'approve'}).status_code==409
    with rosa.db() as con:
        assert [dict(r) for r in con.execute('SELECT id,assigned_to FROM work_tasks ORDER BY id')]==before
        assert con.execute('SELECT COUNT(*) c FROM rosa_actions').fetchone()['c']==prior



def test_assist_action_requires_approval_then_persists(tmp_path, monkeypatch):
    # Owner assistant is read-only in every existing operating/authority mode.
    c=fresh(tmp_path,monkeypatch); login(c)
    assert c.patch('/api/organization/mode',json={'mode':'assist'}).status_code==200
    with rosa.db() as con:
        before=[dict(r) for r in con.execute('SELECT id,assigned_to FROM work_tasks ORDER BY id')]
        prior=con.execute('SELECT COUNT(*) c FROM rosa_actions').fetchone()['c']
    out=new_chat(c,"Move today's cleaning from Anna to Erika.")
    assert out['proposals']==[] and out['read_only'] and out['route']=='read_only'
    assert c.post('/api/rosa/proposals/historical/resolve',json={'decision':'approve'}).status_code==409
    with rosa.db() as con:
        assert [dict(r) for r in con.execute('SELECT id,assigned_to FROM work_tasks ORDER BY id')]==before
        assert con.execute('SELECT COUNT(*) c FROM rosa_actions').fetchone()['c']==prior



def test_autonomous_auto_executes_but_never_rule_blocks(tmp_path, monkeypatch):
    # Owner assistant is read-only in every existing operating/authority mode.
    c=fresh(tmp_path,monkeypatch); login(c)
    assert c.patch('/api/organization/mode',json={'mode':'autonomous'}).status_code==200
    with rosa.db() as con:
        before=[dict(r) for r in con.execute('SELECT id,assigned_to FROM work_tasks ORDER BY id')]
        prior=con.execute('SELECT COUNT(*) c FROM rosa_actions').fetchone()['c']
    out=new_chat(c,"Move today's cleaning from Anna to Erika.")
    assert out['proposals']==[] and out['read_only'] and out['route']=='read_only'
    assert c.post('/api/rosa/proposals/historical/resolve',json={'decision':'approve'}).status_code==409
    with rosa.db() as con:
        assert [dict(r) for r in con.execute('SELECT id,assigned_to FROM work_tasks ORDER BY id')]==before
        assert con.execute('SELECT COUNT(*) c FROM rosa_actions').fetchone()['c']==prior



def test_conversation_tenant_isolation(tmp_path, monkeypatch):
    c=fresh(tmp_path,monkeypatch); login(c)
    cid=new_chat(c,"Anything concerning tomorrow?")["conversation_id"]
    c.post("/api/logout")
    login(c,"owner@isolation.demo","rosa-isolation")
    assert c.get(f"/api/rosa/conversations/{cid}").status_code==404


def test_v26_frontend_and_all_locales(tmp_path, monkeypatch):
    fresh(tmp_path,monkeypatch)
    root=Path(__file__).resolve().parents[1]
    js=(root/"static"/"app.js").read_text(encoding="utf-8")
    css=(root/"static"/"styles.css").read_text(encoding="utf-8")
    for token in ("V26_I18N","/api/rosa/chat","/api/rosa/conversation","v26-proposal","v264-workspace","promptReassign"):
        assert token in js+css
    # Evaluate the compact JSON literal directly from the JS declaration.
    marker="const V26_I18N="; start=js.index(marker)+len(marker); end=js.index(";\nconst V262_ROUTE_I18N",start)
    data=json.loads(js[start:end])
    locales=["en","hu","de","es","fr","it","pt","pl","nl","ro","cs","sk","hr","sr","uk","ru","tr","zh"]
    assert set(data)==set(locales)
    keys=set(data["en"]); assert len(keys)>=20
    for lang in locales:
        assert set(data[lang])==keys
        assert all(str(v).strip() for v in data[lang].values())
