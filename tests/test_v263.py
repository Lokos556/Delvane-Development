from pathlib import Path
import json,re

ROOT=Path(__file__).resolve().parents[1]

def test_single_thread_workspace_and_large_operations_desk_are_primary():
    js=(ROOT/'static'/'app.js').read_text(encoding='utf-8')
    css=(ROOT/'static'/'styles.css').read_text(encoding='utf-8')
    start=js.index('async function ownerIntelligence(){', js.index('function v264OpenDesk'))
    end=js.index('\n\nboot();', start)
    ui=js[start:end]
    for token in ('v264-workspace','v264-pulse','v264-chat-main','v264-ops-layer','v264-ops-desk','v264-metric-strip','/api/rosa/conversation'):
        assert token in js+css
    assert 'v263-history-panel' not in ui
    assert 'rosaNewChat' not in ui
    assert 'data-conversation' not in ui
    assert "api('/api/rosa/conversations')" not in ui
    assert 'width:min(860px,72%)' in css
    assert 'grid-template-columns:repeat(4,minmax(0,1fr))' in css
    assert 'overflow-y:auto' in css


def test_v263_new_copy_is_localized_for_every_supported_language():
    js=(ROOT/'static'/'app.js').read_text(encoding='utf-8')
    start=js.index('const V263_I18N=')+len('const V263_I18N=')
    end=js.index(';\n\nfunction v263',start)
    data=json.loads(js[start:end])
    expected={'en','hu','de','es','fr','it','pt','pl','nl','ro','cs','sk','hr','sr','uk','ru','tr','zh'}
    assert set(data)==expected
    keys=set(data['en'])
    assert {'history','recentChats','liveContext','askAnything','newConversation','quickQuestions'} <= keys
    for lang,vals in data.items():
        assert set(vals)==keys, f'{lang} localization keys differ'
        assert all(str(v).strip() for v in vals.values())
