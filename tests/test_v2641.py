from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]

def test_operations_desk_has_no_stale_cp_reference():
    js=(ROOT/'static'/'app.js').read_text(encoding='utf-8')
    assert "cp('recommends')" not in js
    assert "localizeOperationalText('ROSA RECOMMENDS')" in js

def test_local_first_launch_guard_and_login_marker_exist():
    js=(ROOT/'static'/'app.js').read_text(encoding='utf-8')
    assert "rosa_local_login_v2641" in js
    assert "['127.0.0.1','localhost'].includes(location.hostname)" in js
    assert "await api('/api/logout',{method:'POST'})" in js

def test_session_cookie_name_remains_production_stable():
    py=(ROOT/'app.py').read_text(encoding='utf-8')
    assert 'SESSION_COOKIE = "rosa_session"' in py
