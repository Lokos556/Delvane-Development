import sys
from pathlib import Path
from fastapi.testclient import TestClient

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import app as rosa


def fresh(tmp_path, monkeypatch):
    db_file=tmp_path/'v262.db'
    monkeypatch.setattr(rosa,'DB_PATH',db_file)
    monkeypatch.setattr(rosa,'AI_PROVIDER','local')
    monkeypatch.setattr(rosa,'OPENAI_API_KEY','')
    rosa.init_db(reset=True)
    return TestClient(rosa.app)


def login(c):
    r=c.post('/api/login',json={'email':'owner@demo.rosa','password':'rosa-owner'})
    assert r.status_code==200,r.text
    c.headers.update({'X-Rosa-CSRF':r.json()['csrf_token']})


def ask(c,text,cid=None,language='en'):
    r=c.post('/api/rosa/chat',json={'message':text,'conversation_id':cid,'language':language})
    assert r.status_code==200,r.text
    return r.json()


def test_schema_2620_and_local_first_provider(tmp_path,monkeypatch):
    c=fresh(tmp_path,monkeypatch); login(c)
    with rosa.db() as con:
        assert con.execute('SELECT name FROM schema_migrations WHERE version=2600').fetchone()['name']=='rosa_intelligence'
        assert con.execute('SELECT name FROM schema_migrations WHERE version=2620').fetchone()['name']=='local_first_intelligence_router'
        assert con.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='rosa_ai_routes'").fetchone()
    p=c.get('/api/rosa/provider').json()
    assert p['strategy']=='local_first'
    assert p['external_fallback_configured'] is False


def test_exact_wifi_never_calls_openai_even_when_configured(tmp_path,monkeypatch):
    c=fresh(tmp_path,monkeypatch); login(c)
    monkeypatch.setattr(rosa,'AI_PROVIDER','openai'); monkeypatch.setattr(rosa,'OPENAI_API_KEY','fake-key')
    calls=[]
    monkeypatch.setattr(rosa,'_openai_answer',lambda *a,**k: calls.append(a) or 'SHOULD NOT BE USED')
    out=ask(c,'What is the Wi-Fi password?')
    assert out['route']=='database'
    assert out['provider']=='local'
    assert not calls
    assert 'Wi-Fi' in out['answer']


def test_operations_summary_never_calls_openai(tmp_path,monkeypatch):
    c=fresh(tmp_path,monkeypatch); login(c)
    monkeypatch.setattr(rosa,'AI_PROVIDER','openai'); monkeypatch.setattr(rosa,'OPENAI_API_KEY','fake-key')
    calls=[]
    monkeypatch.setattr(rosa,'_openai_answer',lambda *a,**k: calls.append(a) or 'SHOULD NOT BE USED')
    out=ask(c,'Who arrives tomorrow?')
    assert out['route']=='operations'
    assert out['provider']=='local'
    assert not calls


def test_action_engine_never_calls_openai(tmp_path,monkeypatch):
    c=fresh(tmp_path,monkeypatch); login(c)
    monkeypatch.setattr(rosa,'AI_PROVIDER','openai'); monkeypatch.setattr(rosa,'OPENAI_API_KEY','fake-key')
    calls=[]
    monkeypatch.setattr(rosa,'_openai_answer',lambda *a,**k: calls.append(a) or 'SHOULD NOT BE USED')
    out=ask(c,"Move today's cleaning from Anna to Erika.")
    assert out['route']=='action'
    assert out['proposals']
    assert not calls


def test_only_fallback_may_call_luna(tmp_path,monkeypatch):
    c=fresh(tmp_path,monkeypatch); login(c)
    monkeypatch.setattr(rosa,'AI_PROVIDER','openai'); monkeypatch.setattr(rosa,'OPENAI_API_KEY','fake-key')
    calls=[]
    monkeypatch.setattr(rosa,'_openai_answer',lambda *a,**k: calls.append(a) or 'This is the Luna fallback answer.')
    out=ask(c,'Think through the situation and tell me what pattern I should be worried about.')
    assert out['route']=='llm'
    assert out['provider']=='openai'
    assert len(calls)==1
    assert out['answer']=='This is the Luna fallback answer.'


def test_without_api_complex_request_stays_safe_local_fallback(tmp_path,monkeypatch):
    c=fresh(tmp_path,monkeypatch); login(c)
    out=ask(c,'Think through the situation and tell me what pattern I should be worried about.')
    assert out['route']=='fallback'
    assert out['provider']=='local'
    assert 'optional Luna fallback' in out['answer']
    with rosa.db() as con:
        routes=[dict(r) for r in con.execute('SELECT route,provider,intent FROM rosa_ai_routes ORDER BY created_at')]
        assert routes[-1]['route']=='fallback'


def test_property_scalar_facts_are_database_route(tmp_path,monkeypatch):
    c=fresh(tmp_path,monkeypatch); login(c)
    out=ask(c,"What is Terra's address?")
    assert out['route']=='database'
    assert '3300 Eger' in out['answer']
    out2=ask(c,'How many guests can Terra take?',out['conversation_id'])
    assert out2['route']=='database'
    assert '5' in out2['answer']


def test_v262_frontend_route_labels_all_locales(tmp_path,monkeypatch):
    fresh(tmp_path,monkeypatch)
    js=(Path(__file__).resolve().parents[1]/'static'/'app.js').read_text(encoding='utf-8')
    for token in ('V262_ROUTE_I18N','route-database','v262RouteLabel','localFirst','lunaReady','noLuna'):
        assert token in js or token in (Path(__file__).resolve().parents[1]/'static'/'styles.css').read_text(encoding='utf-8')
    for lang in ('en','hu','de','es','fr','it','pt','pl','nl','ro','cs','sk','hr','sr','uk','ru','tr','zh'):
        assert f" {lang}:{{" in js or f",{lang}:{{" in js
