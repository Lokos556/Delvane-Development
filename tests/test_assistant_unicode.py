"""Unicode is preserved verbatim; only the existing 4000-code-point limit applies."""
import pytest
import app
from test_flutter_reservation_reception import client, login
from test_persistent_development import workspace, PASSWORD, login as persistent_login

SAMPLES = [
    'Melyik apartmanok nem állnak készen?',
    'Hány foglalásom van összesen?',
    'Mikor érkezik a következő vendég?',
    'Ősszel hány vendégünk érkezett?',
    'Árvíztűrő tükörfúrógép',
    'áéíóöőúüű ÁÉÍÓÖŐÚÜŰ · Straße français Łódź · e\u0301 👩‍💻',
]


@pytest.mark.parametrize('message', SAMPLES)
def test_unicode_submit_store_and_restore(client, message):
    login(client)
    response=client.post('/api/rosa/chat',json={'message':message,'language':'hu'})
    assert response.status_code==200,response.text
    out=response.json()
    history=client.get('/api/rosa/conversation').json()['messages']
    assert history[-2]['content']==message
    with app.db() as con:
        assert con.execute("SELECT content FROM rosa_chat_messages WHERE conversation_id=? AND role='user' ORDER BY created_at DESC LIMIT 1",(out['conversation_id'],)).fetchone()['content']==message
    if message.startswith('Hány foglalásom'):
        with app.db() as con:
            count=con.execute("SELECT COUNT(*) c FROM reservations WHERE organization_id='org_casa_rosa'").fetchone()['c']
        assert out['facts']['count']==count
    if message.startswith('Melyik apartmanok'):
        assert out['intent']=='readiness' and out['route']=='operations'


def test_unicode_history_survives_persistent_workspace_restart(tmp_path):
    with workspace(tmp_path,PASSWORD) as (_,client):
        persistent_login(client)
        for message in SAMPLES:
            assert client.post('/api/rosa/chat',json={'message':message,'language':'hu'}).status_code==200
    with workspace(tmp_path) as (_,client):
        persistent_login(client)
        stored=[m['content'] for m in client.get('/api/rosa/conversation').json()['messages'] if m['role']=='user']
        assert stored==SAMPLES


def test_unicode_limits_and_security_are_unchanged(client):
    login(client)
    assert client.post('/api/rosa/chat',json={'message':'ű'*4000,'language':'hu'}).status_code==200
    for message in ['ű'*4001,'',' \t\n']:
        assert client.post('/api/rosa/chat',json={'message':message,'language':'hu'}).status_code==400
    client.headers.pop('X-Rosa-CSRF')
    assert client.post('/api/rosa/chat',json={'message':SAMPLES[0],'language':'hu'}).status_code==403


@pytest.mark.parametrize('english,hungarian,intent',[
    ('Anything concerning tomorrow?','Van valami aggasztó holnap?','attention'),
    ("Which properties aren't ready?",'Mely apartmanok nem állnak készen?','readiness'),
    ('How many reservations were cancelled?','Hány lemondott foglalásom van?','cancelled'),
])
def test_localized_suggestions_retain_supported_lookups(client,english,hungarian,intent):
    login(client)
    en=client.post('/api/rosa/chat',json={'message':english,'language':'en'}).json()
    hu=client.post('/api/rosa/chat',json={'message':hungarian,'language':'hu'}).json()
    assert en['intent']==hu['intent']==intent
    for field in ['tasks','properties','records','count']:
        assert en['facts'].get(field)==hu['facts'].get(field)
