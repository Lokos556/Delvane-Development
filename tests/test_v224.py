import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from fastapi.testclient import TestClient
import app as rosa


def fresh(tmp_path, monkeypatch):
    db_file = tmp_path / 'v224.db'
    monkeypatch.setattr(rosa, 'DB_PATH', db_file)
    rosa.init_db(reset=True)
    return TestClient(rosa.app)


def login(client):
    r = client.post('/api/login', json={'email':'owner@demo.rosa','password':'rosa-owner'})
    assert r.status_code == 200, r.text
    client.headers.update({'X-Rosa-CSRF': r.json()['csrf_token']})


def test_demo_has_eight_guest_journeys_for_board(tmp_path, monkeypatch):
    c=fresh(tmp_path, monkeypatch); login(c)
    r=c.get('/api/guest-journeys')
    assert r.status_code == 200
    assert len(r.json()) >= 8


def test_compact_board_is_eight_per_page_and_order_tracker(tmp_path, monkeypatch):
    fresh(tmp_path, monkeypatch)
    root=Path(__file__).resolve().parents[1]
    js=(root/'static'/'app.js').read_text(encoding='utf-8')
    css=(root/'static'/'styles.css').read_text(encoding='utf-8')
    assert 'const pageSize=8' in js
    assert 'guestJourneyBoard(journeys)' in js
    assert 'guest-ticket-track' in js
    assert 'guest-ticket-now' in js
    assert 'guestPagePrev' in js and 'guestPageNext' in js
    assert 'ownerOperations()' in js
    assert 'renderOperations()' not in js
    assert 'grid-template-columns:repeat(4,minmax(0,1fr))' in css
    assert 'height:164px' in css
