import sys
from pathlib import Path
from fastapi.testclient import TestClient

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import app as rosa


def fresh(tmp_path, monkeypatch, mode='observe', openai=False):
    db_file=tmp_path/'v28.db'
    monkeypatch.setattr(rosa,'DB_PATH',db_file)
    monkeypatch.setattr(rosa,'AI_PROVIDER','openai' if openai else 'local')
    monkeypatch.setattr(rosa,'OPENAI_API_KEY','fake-key' if openai else '')
    rosa.init_db(reset=True)
    c=TestClient(rosa.app)
    r=c.post('/api/login',json={'email':'owner@demo.rosa','password':'rosa-owner'})
    assert r.status_code==200,r.text
    c.headers.update({'X-Rosa-CSRF':r.json()['csrf_token']})
    if mode!='observe':
        assert c.patch('/api/organization/mode',json={'mode':mode}).status_code==200
    return c


def test_v28_schema_and_runtime(tmp_path,monkeypatch):
    c=fresh(tmp_path,monkeypatch)
    runtime=c.get('/api/system/runtime').json()
    assert runtime['version']=='2.10.27'
    assert runtime['schema_version']==3056
    with rosa.db() as con:
        row=con.execute('SELECT * FROM schema_migrations WHERE version=2800').fetchone()
        assert row and row['name']=='reception_and_automation'
        for table in ('automation_rules','communication_outbox','automation_runs'):
            assert con.execute("SELECT name FROM sqlite_master WHERE type='table' AND name=?",(table,)).fetchone()
        assert con.execute('SELECT COUNT(*) c FROM automation_rules WHERE organization_id=?',('org_casa_rosa',)).fetchone()['c']==5


def test_reception_summary_is_explicit_about_external_send(tmp_path,monkeypatch):
    c=fresh(tmp_path,monkeypatch)
    d=c.get('/api/reception/summary').json()
    assert d['inbox']>=2
    assert d['enabled_rules']==5
    assert d['external_sending_connected'] is False


def test_observe_scheduler_only_creates_previews(tmp_path,monkeypatch):
    c=fresh(tmp_path,monkeypatch,mode='observe')
    out=c.post('/api/automation/run')
    assert out.status_code==200,out.text
    assert out.json()['created']>0
    rows=c.get('/api/communications/outbox').json()
    generated=[x for x in rows if x.get('rule_id')]
    assert generated
    assert all(x['status']=='preview' for x in generated)
    assert all(x['channel']=='Rosa preview' for x in generated)


def test_assist_scheduler_requests_approval_and_notifies(tmp_path,monkeypatch):
    c=fresh(tmp_path,monkeypatch,mode='assist')
    out=c.post('/api/automation/run').json()
    assert out['created']>0
    rows=[x for x in c.get('/api/communications/outbox').json() if x.get('rule_id')]
    assert rows and all(x['status']=='awaiting_approval' for x in rows)
    notes=c.get('/api/notifications').json()
    assert notes['unread']>0
    nid=notes['items'][0]['id']
    assert c.post(f'/api/notifications/{nid}/read').status_code==200


def test_automation_rule_authority_and_toggle(tmp_path,monkeypatch):
    c=fresh(tmp_path,monkeypatch)
    rule=c.get('/api/automation/rules').json()[0]
    r=c.patch(f"/api/automation/rules/{rule['id']}",json={'enabled':False,'authority_mode':'never'})
    assert r.status_code==200,r.text
    assert r.json()['enabled'] is False
    assert r.json()['authority_mode']=='never'
    changed=next(x for x in c.get('/api/automation/rules').json() if x['id']==rule['id'])
    assert changed['enabled']==0 and changed['authority_mode']=='never'


def test_outbox_approve_edit_and_simulated_send_never_claims_external(tmp_path,monkeypatch):
    c=fresh(tmp_path,monkeypatch,mode='assist')
    c.post('/api/automation/run')
    item=next(x for x in c.get('/api/communications/outbox').json() if x['status']=='awaiting_approval')
    edited=c.patch(f"/api/communications/outbox/{item['id']}",json={'body':'Edited by owner.'})
    assert edited.status_code==200
    approved=c.post(f"/api/communications/outbox/{item['id']}/approve")
    assert approved.json()=={'ok':True,'status':'ready','external_send':False}
    sent=c.post(f"/api/communications/outbox/{item['id']}/simulate-send")
    assert sent.json()=={'ok':True,'status':'simulated_sent','external_send':False}


def test_simple_guest_reply_stays_local_even_with_openai(tmp_path,monkeypatch):
    c=fresh(tmp_path,monkeypatch,openai=True)
    calls=[]
    monkeypatch.setattr(rosa,'_guest_reply_with_luna',lambda *a,**k: calls.append(1) or 'AI')
    r=c.post('/api/inbox/msg_terra_arrival/draft',json={'tone':'warm_concise'})
    assert r.status_code==200,r.text
    assert r.json()['provider']=='local'
    assert not calls


def test_complex_guest_reply_can_use_luna_but_factual_gaps_do_not(tmp_path,monkeypatch):
    c=fresh(tmp_path,monkeypatch,openai=True)
    # Linked stay with known context and a long, nuanced message -> Luna drafting is useful.
    made=c.post('/api/inbox',json={
        'reservation_id':'res_terra_next','property_id':'prop_terra','source':'Booking.com','sender_name':'Daniel Weber','sender_contact':'','subject':'Arrival issue',
        'body':'Hi, our train was delayed and we are really sorry, but we may arrive much later than expected tonight. Could you please tell us the easiest way to handle arrival without causing trouble, and whether parking will still be straightforward when we get there?'
    })
    assert made.status_code==200,made.text
    mid=made.json()['id']
    monkeypatch.setattr(rosa,'_guest_reply_with_luna',lambda *a,**k:'Warm Luna draft')
    ai=c.post(f'/api/inbox/{mid}/draft',json={'tone':'warm_concise'}).json()
    assert ai['provider']=='openai' and ai['route']=='luna' and ai['draft_reply']=='Warm Luna draft'

    # Missing objective knowledge remains local: Luna must not invent it.
    missing=c.post('/api/inbox',json={
        'reservation_id':'res_terra_next','property_id':'prop_terra','source':'Direct email','sender_name':'Daniel Weber','sender_contact':'','subject':'Question',
        'body':'Could you tell me the exact sofa colour and model in Terra before we arrive?'
    }).json()['id']
    # message_analysis does not know sofa attributes; local draft remains conservative.
    out=c.post(f'/api/inbox/{missing}/draft',json={'tone':'warm_concise'}).json()
    assert out['provider']=='local'


def test_reception_tenant_isolation(tmp_path,monkeypatch):
    c=fresh(tmp_path,monkeypatch)
    with rosa.db() as con:
        con.execute("INSERT INTO organizations(id,name,slug) VALUES ('org_other','Other','other')")
        con.execute("INSERT INTO automation_rules(id,organization_id,rule_key,label,trigger_key,offset_hours,enabled,authority_mode,description,created_at,updated_at) VALUES ('rule_other','org_other','x','Other rule','x',0,1,'ask','',?,?)",(rosa.now_iso(),rosa.now_iso()))
        con.execute("INSERT INTO communication_outbox(id,organization_id,reservation_id,property_id,source_message_id,rule_id,channel,message_type,subject,body,scheduled_for,status,generated_by,created_at,updated_at) VALUES ('out_other','org_other',NULL,NULL,NULL,'rule_other','Rosa preview','guest_message','','secret',NULL,'preview','local',?,?)",(rosa.now_iso(),rosa.now_iso()))
    assert all(x['id']!='out_other' for x in c.get('/api/communications/outbox').json())
    assert all(x['id']!='rule_other' for x in c.get('/api/automation/rules').json())


def test_frontend_reception_replaces_inbox_without_new_primary_nav():
    root=Path(__file__).resolve().parents[1]
    js=(root/'static'/'app.js').read_text(encoding='utf-8')
    css=(root/'static'/'styles.css').read_text(encoding='utf-8')
    assert "['inbox',v28('reception')]" in js
    assert 'data-reception-tab="scheduled"' in js
    assert 'data-reception-tab="automations"' in js
    assert 'openV28Notifications' in js
    assert 'v28-inbox-workspace' in css
    assert 'external_sending_connected' not in js or 'Live external sending' in js

def test_v28_locale_catalog_has_all_18_languages_and_key_parity():
    root=Path(__file__).resolve().parents[1]
    js=(root/'static'/'app.js').read_text(encoding='utf-8')
    locales=['en','hu','de','es','fr','it','pt','pl','nl','ro','cs','sk','hr','sr','uk','ru','tr','zh']
    start=js.index('const V28_I18N=')
    end=js.index('function v28(k)',start)
    block=js[start:end]
    for code in locales:
        assert f" {code}:" in block or f"\n {code}:" in block
    for key in ('reception','scheduled','automations','smartDraft','runNow','externalNote','notifications','simulateSend'):
        assert block.count(f"{key}:")==18
