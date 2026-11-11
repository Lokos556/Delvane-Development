from pathlib import Path
import sys
from fastapi.testclient import TestClient

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import app as rosa

def fresh(tmp_path, monkeypatch):
    db_file=tmp_path/'v264.db'
    monkeypatch.setattr(rosa,'DB_PATH',db_file)
    rosa.init_db(reset=True)
    return TestClient(rosa.app)

def login(c):
    r=c.post('/api/login',json={'email':'owner@demo.rosa','password':'rosa-owner'})
    assert r.status_code==200,r.text
    c.headers.update({'X-Rosa-CSRF':r.json()['csrf_token']})

def test_primary_conversation_endpoint_reuses_one_thread(tmp_path,monkeypatch):
    c=fresh(tmp_path,monkeypatch); login(c)
    first=c.get('/api/rosa/conversation'); assert first.status_code==200,first.text
    cid=first.json()['conversation']['id']
    second=c.get('/api/rosa/conversation'); assert second.status_code==200
    assert second.json()['conversation']['id']==cid
    legacy=c.post('/api/rosa/conversations',json={}); assert legacy.status_code==200
    assert legacy.json()['id']==cid
    with rosa.db() as con:
        assert con.execute("SELECT COUNT(*) c FROM rosa_conversations WHERE organization_id='org_casa_rosa' AND user_id='usr_owner'").fetchone()['c']==1

def test_operations_desk_preserves_decisions_exceptions_and_next48():
    root=Path(__file__).resolve().parents[1]
    js=(root/'static'/'app.js').read_text(encoding='utf-8')
    for token in ('data-v264-panel="decisions"','data-v264-panel="exceptions"','data-v264-panel="next48"','d.approvals.map(v264DecisionCard)','d.exceptions.map(v264ExceptionCard)','arrivals.map(v264ArrivalCard)'):
        assert token in js
