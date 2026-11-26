from datetime import timedelta,date
import pytest
import app
import reservation_allocations as ra
from test_flutter_reservation_reception import client,login,body

BASE='/api/properties/prop_flora/physical-units'


def setup(client):
    login(client)
    rt=client.get('/api/properties/prop_flora/room-types').json()['room_types'][0]['id']
    with app.db() as con:con.execute('UPDATE room_types SET inventory_count=4 WHERE id=?',(rt,))
    units=[]
    for number,kind,single,double,extra in [('101','STANDARD',1,1,0),('102','SUPERIOR',0,1,0),('103','ECONOMY',1,1,0),('104','APARTMAN',0,1,1)]:
        p=dict(effective_from='2020-01-01',room_type_id=rt,building='Fictional building',unit_number=number,classification=kind,single_beds=single,double_beds=double,extra_beds=extra,reason='Fictional explicit unit')
        res=client.post(BASE,json=p);assert res.status_code==200,res.text
        units.append((res.json()['id'],p))
    return rt,units


def booking(client,offset=100):
    p={**body(), 'allocations': []};p['arrival_date']=str(app.date.today()+timedelta(days=offset));p['departure_date']=str(app.date.today()+timedelta(days=offset+2))
    res=client.post('/api/reservations',json=p);assert res.status_code==200,res.text
    return res.json()['id'],p


def assign(client,rid,p,units):
    return client.put(f'/api/reservations/{rid}/allocations',json={'allocations':[{'unit_id':u,'date_from':p['arrival_date'],'date_to':p['departure_date']} for u in units],'reason':'Normal reservation assignment'})


def test_multi_unit_quantity_history_cancel_restart(client):
    rt,units=setup(client);rid,p=booking(client)
    def avail():
        with app.db() as con:return app._reservation_availability(con,'org_casa_rosa','prop_flora',date.fromisoformat(p['arrival_date']),rt)
    assert avail()==3
    assert assign(client,rid,p,[units[2][0],units[3][0]]).status_code==200
    assert avail()==2
    assert client.patch('/api/reservations/'+rid,json={'guest_count':5}).status_code==200
    assert client.patch('/api/reservations/'+rid,json={'guest_count':7}).status_code==409
    assert assign(client,rid,p,[units[0][0],units[3][0]]).status_code==200
    assert avail()==2
    url=f'/api/reservations/{rid}/allocations'
    history=client.get(url).json();assert len(history['active'])==2 and len(history['history'])==4
    with app.db() as con:
        ra.migrate(con,app.now_iso());ra.migrate(con,app.now_iso())
        assert con.execute('SELECT COUNT(*) c FROM reservations WHERE id=?',(rid,)).fetchone()['c']==1
    app.init_db();assert len(client.get(url).json()['active'])==2
    assert client.delete('/api/reservations/'+rid).status_code==200
    assert not client.get(url).json()['active']
    assert len(client.get(url).json()['history'])==4
    assert avail()==4


def test_conflict_adjacent_ooo_rollback(client):
    rt,units=setup(client);rid,p=booking(client);other,_=booking(client)
    assert assign(client,rid,p,[units[2][0]]).status_code==200
    assert assign(client,other,p,[units[0][0],units[2][0]]).status_code==409
    assert not client.get(f'/api/reservations/{other}/allocations').json()['active']
    nextid,n=booking(client,102)
    assert assign(client,nextid,n,[units[2][0]]).status_code==200
    period={'state':'OOO','date_from':p['arrival_date'],'date_to':p['arrival_date'],'reason':'Fictional maintenance'}
    assert client.post(BASE+'/'+units[2][0]+'/periods',json=period).status_code==409
    for state,unit in zip(('OOO','OOS'),(units[0][0],units[1][0])):
        assert client.post(BASE+'/'+unit+'/periods',json={**period,'state':state}).status_code==200
        assert assign(client,other,p,[unit]).status_code==409


def test_dates_capacity_and_unassignment(client):
    rt,units=setup(client);rid,p=booking(client)
    assert assign(client,rid,p,[units[2][0]]).status_code==200
    moved={**p,'arrival_date':str(app.date.today()+timedelta(days=110)),'departure_date':str(app.date.today()+timedelta(days=112))}
    response=client.patch('/api/reservations/'+rid,json={k:moved[k] for k in ('arrival_date','departure_date')})
    assert response.status_code==200,response.text
    url=f'/api/reservations/{rid}/allocations'
    history=client.get(url).json()
    assert history['active'][0]['date_from']==moved['arrival_date'] and len(history['history'])==2
    assert assign(client,rid,moved,[]).status_code==200
    assert not client.get(url).json()['active']
    assert assign(client,rid,{**moved,'departure_date':moved['arrival_date']},[units[0][0]]).status_code==422


def test_cross_property_permissions_and_aggregate_conflict(client):
    rt,units=setup(client);rid,p=booking(client)
    with app.db() as con:con.execute("UPDATE room_types SET inventory_count=1 WHERE id=?",(rt,))
    assert assign(client,rid,p,[units[2][0],units[3][0]]).status_code==409
    foreign=client.get('/api/properties/prop_terra/room-types').json()['room_types'][0]['id']
    data={**units[0][1],'unit_number':'Foreign','room_type_id':foreign}
    uid=client.post('/api/properties/prop_terra/physical-units',json=data).json()['id']
    assert assign(client,rid,p,[uid]).status_code==404
    login(client,'cleaner');assert client.get(f'/api/reservations/{rid}/allocations').status_code==403
    login(client);client.headers.pop('X-Rosa-CSRF')
    assert assign(client,rid,p,[]).status_code==403


def test_concurrent_claims_only_one_wins(client):
    from concurrent.futures import ThreadPoolExecutor
    rt,units=setup(client);r1,p=booking(client);r2,_=booking(client)
    def claim(rid):
        with app.db() as con:
            con.execute("UPDATE properties SET id=id WHERE id='prop_flora'")
            r=dict(con.execute('SELECT * FROM reservations WHERE id=?',(rid,)).fetchone())
            try:
                ra.replace(con,r,[{'unit_id':units[2][0],'date_from':p['arrival_date'],'date_to':p['departure_date']}],'fictional','Concurrent assignment',app.now_iso())
                return 'saved'
            except app.HTTPException as exc:return exc.status_code
    with ThreadPoolExecutor(max_workers=2) as pool:results=list(pool.map(claim,[r1,r2]))
    assert sorted(map(str,results))==['409','saved']


def test_mixed_type_demand_reconciles_and_no_second_primary_charge(client):
    rt,units=setup(client);rid,p=booking(client)
    with app.db() as con:
        con.execute('''INSERT INTO room_types(id,organization_id,property_id,name,code,inventory_count,max_guests,active,created_at,updated_at)
          VALUES ('second-type','org_casa_rosa','prop_flora','Fictional apartment','second',1,3,1,?,?)''',(app.now_iso(),app.now_iso()))
    data={**units[3][1],'effective_from':str(app.date.today()),'room_type_id':'second-type'}
    assert client.put(BASE+'/'+units[3][0],json=data).status_code==200
    assert assign(client,rid,p,[units[2][0],units[3][0]]).status_code==200
    with app.db() as con:
        day=date.fromisoformat(p['arrival_date'])
        assert app._reservation_availability(con,'org_casa_rosa','prop_flora',day,rt)==3
        assert app._reservation_availability(con,'org_casa_rosa','prop_flora',day,'second-type')==0
    assert assign(client,rid,p,[units[2][0]]).status_code==200
    with app.db() as con:assert app._reservation_availability(con,'org_casa_rosa','prop_flora',day,'second-type')==1


def test_failed_date_move_rolls_back_booking_and_history(client):
    rt,units=setup(client);r1,p=booking(client);r2,nextstay=booking(client,102)
    assert assign(client,r1,p,[units[2][0]]).status_code==200
    assert assign(client,r2,nextstay,[units[2][0]]).status_code==200
    failed=client.patch('/api/reservations/'+r1,json={k:nextstay[k] for k in ('arrival_date','departure_date')})
    assert failed.status_code==409
    with app.db() as con:assert con.execute('SELECT arrival_date FROM reservations WHERE id=?',(r1,)).fetchone()['arrival_date']==p['arrival_date']
    assert len(client.get(f'/api/reservations/{r1}/allocations').json()['history'])==1


def test_split_intervals_do_not_invent_date_changes(client):
    rt,units=setup(client);rid,p=booking(client);mid=str(date.fromisoformat(p['arrival_date'])+timedelta(days=1))
    url=f'/api/reservations/{rid}/allocations'
    data={'allocations':[{'unit_id':units[2][0],'date_from':p['arrival_date'],'date_to':mid},
                          {'unit_id':units[3][0],'date_from':mid,'date_to':p['departure_date']}],
          'reason':'Planned reservation allocation sequence'}
    assert client.put(url,json=data).status_code==200
    assert client.patch('/api/reservations/'+rid,json={'departure_date':str(date.fromisoformat(p['departure_date'])+timedelta(days=1))}).status_code==409
    assert len(client.get(url).json()['active'])==2
