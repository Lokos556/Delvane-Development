from pathlib import Path


ROOT=Path(__file__).resolve().parents[1]


def test_desktop_sidebar_is_fixed_without_changing_mobile_drawer():
    css=(ROOT/'static'/'styles.css').read_text(encoding='utf-8')
    desktop=css.index('@media(min-width:851px)')
    desktop_rules=css[desktop:]
    assert '.shell>.side{' in desktop_rules
    assert 'position:fixed;' in desktop_rules
    assert 'height:100dvh;' in desktop_rules
    assert 'padding-left:235px;' in desktop_rules
    mobile=css.index('@media(max-width:850px)')
    mobile_rules=css[mobile:desktop]
    assert '.side{display:flex!important;position:fixed!important;' in mobile_rules
    assert 'transform:translateX(-104%)' in mobile_rules


def test_static_assets_are_cache_busted_for_v2104():
    html=(ROOT/'static'/'index.html').read_text(encoding='utf-8')
    assert html.count('?v=2.10.27')==3
