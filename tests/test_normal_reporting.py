import json
import pytest
import app
from test_flutter_reservation_reception import client,login,body
from test_ntak_reporting import CONFIG,BASE
from test_reservation_allocations import setup

FACTS={'garantaltFoglalas':True,'vendegKuldoOrszaga':'HU','ertekesitesiCsatorna':'DIREKT_ONLINE','piaciSzegmens':'UZLETI_EGYENI','expected_guest_count':1}


def test_normal_booking_revision_sequence_and_country_block(client):
    rt,units=setup(client)
    assert client.put(BASE,json=CONFIG).status_code==200
    data=body();data['total_huf']=20000;data['reporting']=FACTS
    data['allocations']=[{'unit_id':units[0][0],'date_from':data['arrival_date'],'date_to':data['departure_date']}]
    made=client.post('/api/reservations',json=data);assert made.status_code==200,made.text
    rid=made.json()['id']
    def jobs():
        with app.db() as con:return [dict(x) for x in con.execute('SELECT j.* FROM ntak_jobs j JOIN government_outbox o ON o.id=j.id WHERE o.reservation_id=? ORDER BY j.created_at',(rid,))]
    assert jobs()[-1]['state']=='ready'
    assert json.loads(jobs()[-1]['payload_json'])['foglalasEsemeny']['vendegszam']==1
    for guarantee in (False,False,True):
        assert client.patch('/api/reservations/'+rid,json={'reporting':{'garantaltFoglalas':guarantee}}).status_code==200
    assert len(jobs())==3
    assert client.patch('/api/reservations/'+rid,json={'reporting':{'vendegKuldoOrszaga':'EGYEBKULFOLDI'}}).status_code==200
    assert jobs()[-1]['error_code']=='sending_country_contract_unresolved'
    assert client.patch('/api/reservations/'+rid,json={'reporting':{'vendegKuldoOrszaga':'HU'}}).status_code==200
    assert client.delete('/api/reservations/'+rid).status_code==200
    last=json.loads(jobs()[-1]['payload_json'])['foglalasEsemeny']
    assert last['lemondva'] and last['foglaltLakoegysegek']['foglaltLakoegyseg'][0]['ferohelyKapacitas']==3
    assert last['foglalasiSzam']==rid


def test_reporting_and_allocation_rollback(client):
    rt,units=setup(client);client.put(BASE,json=CONFIG)
    data=body();data['reporting']={**FACTS,'garantaltFoglalas':'yes'}
    response=client.post('/api/reservations',json=data);assert response.status_code==422
    with app.db() as con:assert con.execute("SELECT COUNT(*) c FROM reservations WHERE guest_name=?",(data['guest_name'],)).fetchone()['c']==0


def test_normal_multi_unit_creation_uses_combined_capacity(client):
    rt,units=setup(client)
    with app.db() as con:con.execute('UPDATE room_types SET max_guests=2 WHERE id=?',(rt,))
    data=body();data['guest_count']=5
    data['allocations']=[{'unit_id':u[0],'date_from':data['arrival_date'],'date_to':data['departure_date']} for u in units[2:]]
    response=client.post('/api/reservations',json=data)
    assert response.status_code==200,response.text
    rid=response.json()['id']
    assert len(client.get(f'/api/reservations/{rid}/allocations').json()['active'])==2
