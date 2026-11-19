"""Physical inventory API tests use only guarded, fictional test databases."""
from datetime import date
import pytest
import app
import physical_units
from test_flutter_reservation_reception import client,login

BASE='/api/properties/prop_flora/physical-units'
D1='2026-01-01'
D2='2026-01-02'
D3='2026-01-03'


def payload(client,number='101',classification='STANDARD',single=1,double=1,extra=0):
    room=client.get('/api/properties/prop_flora/room-types').json()['room_types'][0]['id']
    return dict(effective_from=D1,room_type_id=room,building='Fictional building',unit_number=number,
                classification=classification,single_beds=single,double_beds=double,extra_beds=extra,reason='Explicit fictional inventory')


def create(client,**kwargs):
    data=payload(client,**kwargs);response=client.post(BASE,json=data)
    assert response.status_code==200,response.text
    return response.json()['id'],data


def cap(client,day):return client.get(BASE+'/capacity',params={'business_date':day}).json()


def test_official_four_units_dated_capacity_and_history(client):
    login(client)
    ids=[]
    for args in [('101','STANDARD',1,1,0),('102','SUPERIOR',0,1,0),('103','ECONOMY',1,1,0),('104','APARTMAN',0,1,1)]:
        uid,_=create(client,**dict(zip(('number','classification','single','double','extra'),args)));ids.append(uid)
    assert cap(client,D1)['counts']['total']=={'units':4,'regular_places':10,'extra_places':1}
    for uid,state in zip(ids[2:],('OOO','OOS')):
        response=client.post(BASE+f'/{uid}/periods',json={'state':state,'date_from':D2,'date_to':D2,'reason':'Fictional maintenance'})
        assert response.status_code==200,response.text
    counts=cap(client,D2)['counts']
    assert counts['OOO']=={'units':1,'regular_places':3,'extra_places':0}
    assert counts['OOS']=={'units':1,'regular_places':2,'extra_places':1}
    assert counts['available']=={'units':2,'regular_places':5,'extra_places':0}
    assert cap(client,D3)['counts']['available']==counts['total']
    assert len(client.get(BASE+f'/{ids[2]}/history').json()['periods'])==1
    with app.db() as con:
        physical_units.migrate(con,app.now_iso());physical_units.migrate(con,app.now_iso())
        assert con.execute('SELECT COUNT(*) c FROM physical_units').fetchone()['c']==4
        assert con.execute('SELECT COUNT(*) c FROM schema_migrations WHERE version=3074').fetchone()['c']==1
    app.init_db()
    assert cap(client,D2)['counts']==counts


def test_versions_deactivation_and_single_apartment(client):
    login(client);uid,data=create(client,number='Apartment',classification='APARTMAN',single=0,double=1)
    changed={**data,'effective_from':D2,'single_beds':1,'reason':'Added a regular single bed'}
    assert client.put(BASE+'/'+uid,json=changed).status_code==200
    assert cap(client,D1)['counts']['total']['regular_places']==2
    assert cap(client,D2)['counts']['total']['regular_places']==3
    assert client.put(BASE+'/'+uid,json=changed).status_code==409
    assert client.put(BASE+'/'+uid,json={**changed,'effective_from':D3,'active':False}).status_code==200
    assert cap(client,D3)['counts']['total']['units']==0
    assert cap(client,D1)['counts']['total']['units']==1
    assert len(client.get(BASE+'/'+uid+'/history').json()['versions'])==3


@pytest.mark.parametrize('updates',[{'single_beds':-1},{'double_beds':1.5},{'extra_beds':True},
    {'single_beds':0,'double_beds':0},{'classification':'FAKE'},{'effective_from':'invalid'},
    {'building':''},{'unit_number':' '},{'room_type_id':'unknown'}])
def test_invalid_unit_data(client,updates):
    login(client);data=payload(client)
    assert client.post(BASE,json={**data,**updates}).status_code==422
    assert cap(client,D1)['units']==[]


def test_period_overlap_cancel_and_deactivation_guard(client):
    login(client);uid,data=create(client)
    url=BASE+'/'+uid+'/periods'
    period={'state':'OOO','date_from':D1,'date_to':D3,'reason':'Fictional renovation'}
    pid=client.post(url,json=period).json()['id']
    assert client.post(url,json={**period,'state':'OOS'}).status_code==409
    assert client.post(url,json={**period,'date_to':'2025-12-31'}).status_code==422
    assert client.post(url,json={**period,'state':'closed'}).status_code==422
    assert client.put(BASE+'/'+uid,json={**data,'effective_from':D2,'active':False}).status_code==409
    assert client.post(url+'/'+pid+'/cancel',json={'effective_from':D2,'reason':'Reopened after repair'}).status_code==200
    assert cap(client,D1)['counts']['OOO']['units']==1
    assert cap(client,D2)['counts']['available']['units']==1
    assert client.post(url,json={**period,'state':'OOS','date_from':D2}).status_code==200
    history=client.get(BASE+'/'+uid+'/history').json()['periods']
    assert len(history)==2 and history[0]['cancelled_from']==D2


def test_authorization_identity_and_no_aggregate_mutation(client):
    login(client)
    with app.db() as con:
        before=[dict(x) for x in con.execute('SELECT * FROM room_types ORDER BY id')]
        mappings=[dict(x) for x in con.execute('SELECT * FROM channex_room_type_mappings ORDER BY id')]
    uid,data=create(client)
    assert client.post(BASE,json=data).status_code==409
    foreign='/api/properties/prop_other/physical-units'
    assert client.get(foreign+'/capacity',params={'business_date':D1}).status_code==404
    assert client.put(foreign+'/'+uid,json={**data,'effective_from':D2}).status_code==404
    other='/api/properties/prop_terra/physical-units'
    assert client.get(other+'/'+uid+'/history').status_code==404
    assert client.post(other,json=data).status_code==422
    with app.db() as con:
        assert before==[dict(x) for x in con.execute('SELECT * FROM room_types ORDER BY id')]
        assert mappings==[dict(x) for x in con.execute('SELECT * FROM channex_room_type_mappings ORDER BY id')]
    login(client,'manager')
    assert client.get(BASE+'/capacity',params={'business_date':D1}).status_code==200
    assert client.post(BASE,json=data).status_code==403
    login(client,'cleaner')
    assert client.get(BASE+'/capacity',params={'business_date':D1}).status_code==403
    login(client);client.headers.pop('X-Rosa-CSRF')
    assert client.post(BASE,json=data).status_code==403


def test_legacy_inventory_remains_explicitly_unconfigured(client):
    login(client)
    assert cap(client,D1)['counts']['total']['units']==0
    assert any(not r['matches'] for r in cap(client,D1)['aggregate_comparison'])
    with app.db() as con:
        assert con.execute('SELECT COUNT(*) c FROM room_types').fetchone()['c']>0
        assert con.execute('SELECT COUNT(*) c FROM physical_units').fetchone()['c']==0


def test_future_inactive_intervals_and_identity_history(client):
    login(client);uid,data=create(client)
    assert client.put(BASE+'/'+uid,json={**data,'effective_from':D3,'active':False}).status_code==200
    response=client.post(BASE+'/'+uid+'/periods',json={'state':'OOO','date_from':D2,'date_to':D3,'reason':'Crosses deactivation'})
    assert response.status_code==409
    assert client.post(BASE+'/'+uid+'/periods',json={'state':'OOS','date_from':'2025-12-01','date_to':D1,'reason':'Before unit existed'}).status_code==409
    assert client.get(BASE+'/capacity',params={'business_date':'not-a-date'}).status_code==422
    assert client.post(BASE,json={**data,'effective_from':D3}).status_code==409


def test_room_type_mapping_can_change_only_prospectively(client):
    login(client);uid,data=create(client)
    with app.db() as con:
        con.execute('''INSERT INTO room_types(id,organization_id,property_id,name,code,inventory_count,max_guests,active,created_at,updated_at)
           VALUES ('fictional-new-type','org_casa_rosa','prop_flora','Fictional type','fixture',2,3,1,?,?)''',(app.now_iso(),app.now_iso()))
    assert client.put(BASE+'/'+uid,json={**data,'effective_from':D2,'room_type_id':'fictional-new-type','unit_number':'New label'}).status_code==200
    assert cap(client,D1)['units'][0]['room_type_id']==data['room_type_id']
    assert cap(client,D2)['units'][0]['room_type_id']=='fictional-new-type'
    assert cap(client,D1)['units'][0]['unit_number']=='101'
