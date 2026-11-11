from pathlib import Path
import re
from urllib.parse import urlsplit, parse_qs


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


def test_static_assets_have_explicit_release_cache_versions():
    html=(ROOT/'static'/'index.html').read_text(encoding='utf-8')
    assets = re.findall(r'(?:href|src)="(/static/[^\"]+)"', html)
    expected = {"/static/styles.css": "2.11.26", "/static/app.js": "2.11.26",
                "/static/v283.js": "2.10.50"}
    assert len(assets) == len(expected)
    assert {urlsplit(asset).path for asset in assets} == set(expected)
    for asset in assets:
        parsed = urlsplit(asset)
        assert parse_qs(parsed.query) == {"v": [expected[parsed.path]]}
        assert (ROOT / parsed.path.lstrip('/')).is_file()
