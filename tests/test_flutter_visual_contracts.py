"""Verify the source Ask-bar contract only under repository test isolation."""
import pytest
from fastapi.testclient import TestClient
import app


@pytest.fixture
def client(request):
    assert app.DB_PATH.resolve().is_relative_to(request.config._delvane_safety.root)
    assert not app.CHANNEX_API_KEY and not app.OPENAI_API_KEY
    app.init_db()
    with TestClient(app.app) as client:
        login=client.post('/api/login',json={'email':'owner@demo.rosa','password':'rosa-owner'})
        assert login.status_code==200
        client.headers['X-Rosa-CSRF']=login.json()['csrf_token']
        yield client


def test_reference_ask_bar_returns_local_answer_without_provider_access(client,monkeypatch):
    def forbidden(*args,**kwargs):
        raise AssertionError('A local visual-workspace answer must not contact a provider')
    monkeypatch.setattr(app,'_channex_request',forbidden)
    result=client.post('/api/rosa/ask',json={'message':'What needs attention?'})
    assert result.status_code==200
    assert isinstance(result.json()['answer'],str) and result.json()['answer']


def test_reference_ask_bar_does_not_bypass_session_csrf(client):
    client.headers.pop('X-Rosa-CSRF')
    assert client.post('/api/rosa/ask',json={'message':'What needs attention?'}).status_code==403


@pytest.mark.parametrize('decision', ['Approved', 'Declined'])
def test_operational_desk_resolves_only_the_decision_record(client, decision):
    # A disposable record makes this independent of seeded calendar dates.
    with app.db() as con:
        con.execute('''INSERT INTO approval_items
            (id,organization_id,kind,title,detail,recommendation,status,created_at)
            VALUES (?,?,?,?,?,?,?,?)''',
            ('native_desk_decision','org_casa_rosa','review','Synthetic review',
             'Local test only','Review','open',app.now_iso()))
    before=client.get('/api/intelligence').json()
    assert any(x['id']=='native_desk_decision' for x in before['approvals'])
    assert client.post('/api/approvals/native_desk_decision/resolve',
                       json={'decision':decision}).status_code==200
    after=client.get('/api/intelligence').json()
    assert not any(x['id']=='native_desk_decision' for x in after['approvals'])
    with app.db() as con:
        row=con.execute('SELECT status,resolved_at FROM approval_items WHERE id=?',
                        ('native_desk_decision',)).fetchone()
        assert row['status']=='resolved' and row['resolved_at']
        assert con.execute('SELECT COUNT(*) c FROM activity WHERE message LIKE ?',
                           (f'%decided: {decision}%Synthetic review%',)).fetchone()['c']==1


def test_operational_desk_enforces_csrf_and_worker_role(client):
    client.headers.pop('X-Rosa-CSRF')
    assert client.post('/api/approvals/missing/resolve',json={'decision':'Approved'}).status_code==403
    response=client.post('/api/login',json={'email':'cleaner@demo.rosa','password':'rosa-cleaner'})
    assert response.status_code==200
    client.headers['X-Rosa-CSRF']=response.json()['csrf_token']
    assert client.get('/api/intelligence').status_code==403
    assert client.post('/api/approvals/missing/resolve',json={'decision':'Approved'}).status_code==403
