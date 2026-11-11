from pathlib import Path


def test_v283_hungarian_surfaces_and_readability():
    root=Path(__file__).resolve().parents[1]
    js=(root/'static'/'v283.js').read_text(encoding='utf-8')
    css=(root/'static'/'styles.css').read_text(encoding='utf-8')
    for token in ['CSAPAT ÉS HOZZÁFÉRÉS','Hozzáférés és szerepkörök','ROSA TANÍTÁSA','STRUKTURÁLT ÜZLETI MEMÓRIA','HIBA BEJELENTÉSE','A csapatod, a munkájuk']:
        assert token in js
    assert '.v282-role-groups div{font-size:13px' in css
    assert '.v282-role-card header p{font-size:14px' in css
    assert 'START_ROSA_PHONE.bat' in [p.name for p in root.iterdir()]


def test_v283_phone_launcher_binds_lan_safely():
    root=Path(__file__).resolve().parents[1]
    bat=(root/'START_ROSA_PHONE.bat').read_text(encoding='utf-8')
    assert '--host 0.0.0.0' in bat
    assert 'Private networks only' in bat
    normal=(root/'START_ROSA.bat').read_text(encoding='utf-8')
    assert '--host 127.0.0.1' in normal
    assert '8819' in normal
