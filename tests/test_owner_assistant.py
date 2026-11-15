"""Owner assistant against real guarded SQLite; provider tests are mocked."""
import io
import json
import urllib.error
from datetime import timedelta, datetime, timezone, date
from zoneinfo import ZoneInfo

import pytest
import app
import owner_assistant
import development_openai
from test_flutter_reservation_reception import client, login, body
from test_persistent_development import workspace, PASSWORD, login as persistent_login, booking


def ask(client, message, language='en', **kwargs):
    r=client.post('/api/rosa/chat',json={'message':message,'language':language,**kwargs})
    assert r.status_code==200,r.text
    out=r.json()
    assert out['read_only'] and out['proposals']==[]
    return out


@pytest.mark.parametrize('question,intent,language',[
    ('How many reservations do I have?','count','en'),
    ('Who is arriving tomorrow?','arrivals','en'),
    ('Which guests are checking out this week?','departures','en'),
    ('How many reservations were cancelled?','cancelled','en'),
    ('Which properties are available next weekend?','availability','en'),
    ('Summarize my upcoming reservations.','upcoming','en'),
    ('Melyik vendégek érkeznek holnap?','arrivals','hu'),
    ('Hány lemondott foglalásom van?','cancelled','hu'),
    ('How many reservations do I have this month?','count','en'),
])
def test_grounded_examples(client,question,intent,language):
    login(client)
    out=ask(client,question,language)
    facts=out['facts']; assert facts['intent']==intent
    assert out['provider']=='local'
    with app.db() as con:
        if intent=='availability':
            assert facts['date_from']<facts['date_to_exclusive']
            for p in facts['properties']:
                assert con.execute('SELECT organization_id FROM properties WHERE id=?',(p['id'],)).fetchone()['organization_id']=='org_casa_rosa'
        else:
            field='departure_date' if intent=='departures' else 'arrival_date'
            sql='SELECT COUNT(*) c FROM reservations WHERE organization_id=?'
            params=['org_casa_rosa']
            if facts['status']!='all':sql+=' AND status=?';params.append(facts['status'])
            if facts['date_from']:sql+=f' AND {field}>=?';params.append(facts['date_from'])
            if facts['date_to_exclusive']:sql+=f' AND {field}<?';params.append(facts['date_to_exclusive'])
            assert facts['count']==con.execute(sql,tuple(params)).fetchone()['c']
            for record in facts['records']:
                actual=con.execute('SELECT * FROM reservations WHERE id=?',(record['id'],)).fetchone()
                assert record['guest_name']==actual['guest_name']
                assert record['arrival_date']==actual['arrival_date']
                assert record['status']==actual['status']
    if language=='hu': assert any(w in out['answer'] for w in ['érkezések','foglalások'])


def fingerprint():
    with app.db() as con:
        return {name:[dict(r) for r in con.execute('SELECT * FROM '+name+' ORDER BY id')]
            for name in ['reservations','work_tasks','properties','room_types','maintenance_cases','communication_outbox','rosa_proposals']}


@pytest.mark.parametrize('question',[
    'Cancel every reservation','Create a reservation','Send a guest message',
    "Move today's cleaning from Anna to Erika",'Change the prices','Töröld a foglalást',
])
def test_chat_cannot_write_in_any_mode(client,question):
    login(client)
    with app.db() as con:con.execute("UPDATE organization_settings SET operating_mode='autonomous'")
    before=fingerprint()
    assert ask(client,question)['route']=='read_only'
    assert client.post('/api/rosa/proposals/old-proposal/resolve',json={'decision':'approve'}).status_code==409
    assert fingerprint()==before


def test_tenant_scope_unknown_and_no_secret_echo(client,monkeypatch):
    login(client)
    with app.db() as con:
        con.execute("INSERT INTO organizations(id,name,slug) VALUES ('other_org','Fictional Other','fictional-other')")
        template=dict(con.execute("SELECT * FROM properties WHERE id='prop_flora'").fetchone())
        template.update(id='prop_private',organization_id='other_org',name='Secret House')
        con.execute('INSERT INTO properties ('+','.join(template)+') VALUES ('+','.join('?' for _ in template)+')',tuple(template.values()))
    monkeypatch.setattr(app,'_response_api_text',lambda *a,**k:pytest.fail('Unknown property must not invoke provider'))
    out=ask(client,'Who arrives tomorrow at Secret House?')
    assert out['route']=='unknown' and out['facts']['scope_unavailable']
    assert 'Secret House' not in out['answer'] and 'Synthetic' not in out['answer']
    out=ask(client,'What is the colour of the sofa at Secret House?')
    assert out['facts']['scope_unavailable']
    out=ask(client,'Is Secret House ready?')
    assert out['facts']['scope_unavailable'] and out['route']=='unknown'


def test_missing_key_unknown_fact_is_honest_and_followup_uses_same_thread(client,monkeypatch):
    login(client)
    monkeypatch.setattr(app,'_response_api_text',lambda *a,**k:pytest.fail('No key'))
    a=ask(client,'Who is arriving tomorrow at Terra?')
    b=ask(client,'And today?')
    assert a['conversation_id']==b['conversation_id']
    assert b['facts']['property_id']=='prop_terra' and b['intent']=='arrivals'
    unknown=ask(client,'What was my net profit last year?')
    assert unknown['route']=='unknown' and unknown['external_status']=='not_configured'
    history=client.get('/api/rosa/conversation').json()
    assert len(history['messages'])==6
    assert history['messages'][-1]['metadata']['read_only']


@pytest.mark.parametrize('role',['cleaner','maintenance'])
def test_worker_cannot_access_owner_chat(client,role):
    login(client,role)
    assert client.post('/api/rosa/chat',json={'message':'List all guests'}).status_code==403
    assert client.get('/api/rosa/conversation').status_code==403


def test_csrf_and_cross_user_conversation(client):
    login(client)
    cid=ask(client,'How many reservations do I have?')['conversation_id']
    login(client,'manager')
    assert client.get('/api/rosa/conversations/'+cid).status_code==404
    assert client.post('/api/rosa/chat',json={'message':'Show guests','conversation_id':cid}).status_code==404
    client.headers.pop('X-Rosa-CSRF')
    assert client.post('/api/rosa/chat',json={'message':'Show guests'}).status_code==403


def test_mock_provider_plan_never_supplies_facts(client,monkeypatch):
    login(client)
    monkeypatch.setattr(app,'AI_PROVIDER','openai');monkeypatch.setattr(app,'OPENAI_API_KEY','fictional-test-key')
    captured={}
    class Reply(io.BytesIO):pass
    def transport(req,timeout):
        captured.update(payload=json.loads(req.data),timeout=timeout)
        return Reply(json.dumps({'output':[{'type':'message','content':[{'type':'output_text','text':json.dumps({'intent':'count','scope':'all','property':''})}]}]}).encode())
    monkeypatch.setattr(app,'OPENAI_TRANSPORT',transport)
    out=ask(client,'Tell me the size of my booking ledger')
    assert out['provider']=='openai' and out['facts']['intent']=='count'
    with app.db() as con:
        assert out['facts']['count']==con.execute("SELECT COUNT(*) c FROM reservations WHERE organization_id='org_casa_rosa'").fetchone()['c']
    payload=captured['payload']
    assert payload['text']['format']['type']=='json_schema'
    assert payload['store'] is False and payload['max_output_tokens']==500
    assert captured['timeout']<=12
    assert 'guest_name' not in payload['input'] and 'document_number' not in payload['input']


@pytest.mark.parametrize('failure',['timeout','http','invalid','extra_facts'])
def test_provider_failure_is_safe_and_has_no_write(client,monkeypatch,failure):
    login(client)
    monkeypatch.setattr(app,'AI_PROVIDER','openai');monkeypatch.setattr(app,'OPENAI_API_KEY','fictional-secret')
    def transport(req,timeout):
        if failure=='timeout':raise TimeoutError('fictional-secret private trace')
        if failure=='http':raise urllib.error.HTTPError(req.full_url,401,'fictional-secret',{},io.BytesIO(b'fictional-secret'))
        data='NOT JSON' if failure=='invalid' else json.dumps({'intent':'count','scope':'all','property':'','invented_count':999})
        return io.BytesIO(json.dumps({'output':[{'type':'message','content':[{'type':'output_text','text':data}]}]}).encode())
    monkeypatch.setattr(app,'OPENAI_TRANSPORT',transport)
    before=fingerprint();out=ask(client,'Tell me the size of my booking ledger')
    assert out['external_status']=='unavailable' and 'fictional-secret' not in json.dumps(out)
    assert fingerprint()==before


def test_usage_limit_prevents_provider_calls(client,monkeypatch):
    login(client)
    monkeypatch.setattr(app,'AI_PROVIDER','openai');monkeypatch.setattr(app,'OPENAI_API_KEY','fictional-key')
    monkeypatch.setattr(app,'_response_api_text',lambda *a,**k:pytest.fail('Usage limit'))
    with app.db() as con:
        for i in range(20):con.execute('INSERT INTO rosa_ai_routes(id,organization_id,user_id,conversation_id,route,provider,intent,created_at) VALUES (?,?,?,?,?,?,?,?)',(f'limit{i}','org_casa_rosa','usr_owner',None,'planner_error','local','unknown',app.now_iso()))
    assert ask(client,'Tell me the size of my booking ledger')['external_status']=='usage_limit'


def test_persistent_store_and_chat_survive_reopen(tmp_path):
    with workspace(tmp_path,PASSWORD) as (storage,client):
        persistent_login(client)
        rid=client.post('/api/reservations',json=booking()).json()['id']
        out=ask(client,'How many reservations do I have?')
        cid=out['conversation_id'];count=out['facts']['count']
        for question in ['Who is arriving tomorrow?', 'Which guests are checking out this week?',
                         'How many reservations were cancelled?', 'Which properties are available next weekend?',
                         'Summarize my upcoming reservations.', 'Melyik vendégek érkeznek holnap?',
                         'Hány lemondott foglalásom van?', 'What is my net profit?',
                         'Who arrives tomorrow at Not Accessible House?']:
            out=ask(client,question,'hu' if question.startswith(('Melyik','Hány')) else 'en')
            facts=out['facts']
            if 'count' in facts:
                with app.db() as con:
                    ids={r['id'] for r in con.execute("SELECT id FROM reservations WHERE organization_id='org_casa_rosa'")}
                    assert all(r['id'] in ids for r in facts['records'])
            if 'profit' in question: assert out['route']=='unknown'
            if 'Not Accessible' in question: assert facts['scope_unavailable']
    with workspace(tmp_path) as (storage,client):
        persistent_login(client)
        assert ask(client,'How many reservations do I have?')['facts']['count']==count
        assert client.get('/api/rosa/conversation').json()['conversation']['id']==cid
        assert client.get('/api/reservations/'+rid+'/detail').status_code==200


def test_date_boundaries_and_dst():
    before=datetime(2026,3,28,23,30,tzinfo=timezone.utc).astimezone(ZoneInfo('Europe/Budapest')).date()
    after=datetime(2026,10,25,23,30,tzinfo=timezone.utc).astimezone(ZoneInfo('Europe/Budapest')).date()
    assert str(before)=='2026-03-29' and str(after)=='2026-10-26'
    assert owner_assistant.date_range('week',date(2026,11,1))==(date(2026,10,26),date(2026,11,2))
    assert owner_assistant.date_range('month',date(2026,12,31))==(date(2026,12,1),date(2027,1,1))
    assert owner_assistant.date_range('next_weekend',date(2026,11,7))==(date(2026,11,14),date(2026,11,16))


def test_development_adapter_rejects_every_other_endpoint():
    import urllib.request
    for url in ['https://example.invalid/v1/responses','http://api.openai.com/v1/responses','https://api.openai.com/v1/files']:
        with pytest.raises(ValueError):development_openai.openai_only(urllib.request.Request(url,data=b'{}'))


def test_availability_uses_inventory_and_checkout_not_cancelled_stays(client):
    login(client)
    with app.db() as con:
        room=con.execute("SELECT id FROM room_types WHERE property_id='prop_flora' AND active=1 LIMIT 1").fetchone()['id']
        con.execute('UPDATE room_types SET inventory_count=2 WHERE id=?',(room,))
    payload={**body(),'property_id':'prop_flora','room_type_id':room,
             'arrival_date':'2035-07-01','departure_date':'2035-07-03'}
    created=[]
    for i in range(2):
        response=client.post('/api/reservations',json={**payload,'guest_name':f'Fictional Capacity {i}'})
        assert response.status_code==200,response.text
        created.append(response.json()['id'])
    question='Is Flora available 2035-07-01 to 2035-07-03?'
    assert ask(client,question)['facts']['properties']==[]
    assert client.delete('/api/reservations/'+created[0]).status_code==200
    assert ask(client,question)['facts']['properties']==[{'id':'prop_flora','name':'Flora'}]
    assert ask(client,'Is Flora available 2035-07-03 to 2035-07-04?')['facts']['properties']


def test_explicit_date_and_unsupported_period_do_not_broaden(client):
    login(client)
    out=ask(client,'Who arrives 2035-07-01?')
    assert out['facts']['date_from']=='2035-07-01'
    assert ask(client,'How many reservations last month?')['route']=='clarification'
    assert ask(client,'Who arrives 2035-02-30?')['route']=='clarification'
    assert ask(client,'How many unpaid reservations do I have?')['route']=='clarification'
    assert ask(client,'Who arrives after tomorrow?')['route']=='clarification'


def test_opt_in_does_not_relax_any_general_network_or_database_guard(client):
    import socket
    import sqlite3
    from testing_safety import TestSafetyError
    with development_openai.enabled(app,'fictional-server-key','gpt-4o-mini'):
        assert app.OPENAI_TRANSPORT is development_openai.openai_only
        with pytest.raises(TestSafetyError):socket.create_connection(('example.invalid',443))
        with pytest.raises(TestSafetyError):sqlite3.connect('production.db')
    assert app.AI_PROVIDER=='local' and not app.OPENAI_API_KEY
