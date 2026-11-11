import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from fastapi.testclient import TestClient
import app as rosa


def fresh(tmp_path, monkeypatch):
    db_file = tmp_path / 'v223.db'
    monkeypatch.setattr(rosa, 'DB_PATH', db_file)
    rosa.init_db(reset=True)
    return TestClient(rosa.app)


def login(client):
    r = client.post('/api/login', json={'email':'owner@demo.rosa','password':'rosa-owner'})
    assert r.status_code == 200, r.text
    client.headers.update({'X-Rosa-CSRF': r.json()['csrf_token']})


def test_guest_journey_exposes_single_current_stage(tmp_path, monkeypatch):
    c = fresh(tmp_path, monkeypatch)
    login(c)
    r = c.get('/api/guest-journeys')
    assert r.status_code == 200, r.text
    journeys = r.json()
    assert journeys
    allowed = {'booking_confirmed','registration','arrival_preparation','check_in','stay','checkout'}
    for j in journeys:
        assert j['current_stage'] in allowed
        assert 1 <= j['current_stage_index'] <= j['stage_total'] == 5
        assert 'next_stage' in j


def test_v223_frontend_uses_compact_primary_nav_and_chat_send(tmp_path, monkeypatch):
    fresh(tmp_path, monkeypatch)
    src = (Path(__file__).resolve().parents[1] / 'static' / 'app.js').read_text(encoding='utf-8')
    assert "function ownerPrimaryNav()" in src
    assert "['operations',tr('operations')]" in src
    assert 'data-settings-nav' in src
    assert 'rosa-chat-thread' in src
    assert 'sendRosaChat' in src
    assert "input.value=b.textContent" in src  # quick prompts fill; they do not auto-send
    assert 'guest-ticket' in src
