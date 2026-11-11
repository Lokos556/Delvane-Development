import json
import sqlite3
import sys
from datetime import date, timedelta
from pathlib import Path

from fastapi.testclient import TestClient

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import app as rosa


def fresh(tmp_path, monkeypatch):
    db_file=tmp_path/'v299.db'
    monkeypatch.setattr(rosa,'DB_PATH',db_file)
    monkeypatch.setattr(rosa,'CHANNEX_API_KEY','shared-test-key')
    rosa.init_db(reset=True)
    client=TestClient(rosa.app)
    login=client.post('/api/login',json={'email':'owner@demo.rosa','password':'rosa-owner'})
    assert login.status_code==200,login.text
    client.headers.update({'X-Rosa-CSRF':login.json()['csrf_token']})
    with sqlite3.connect(db_file) as con:
        con.row_factory=sqlite3.Row
        row=con.execute("""SELECT i.id,i.property_id FROM integrations i JOIN properties p ON p.id=i.property_id
                           WHERE p.name='Aqua' AND i.provider='Booking.com'""").fetchone()
        cfg={'adapter':'channex_channel_manager','provider_property_id':'bridge-casa',
             'channex_room_type_id':'room-aqua','channex_rate_plan_id':'rate-aqua',
             'commercial':True,'customer_handles_api_keys':False,'connector_core_version':'2.10.2'}
        con.execute("UPDATE integrations SET public_config_json=?,status='staging_ready' WHERE id=?",(json.dumps(cfg),row['id']))
        return client,db_file,row['id'],row['property_id']


def outbox_values(db_file):
    with sqlite3.connect(db_file) as con:
        rows=con.execute("SELECT payload_json FROM channel_ari_outbox WHERE endpoint='/api/v1/availability' ORDER BY created_at,id").fetchall()
    return [value for row in rows for value in json.loads(row[0])['values']]


def test_booking_closes_nights_and_cancellation_reopens_them(tmp_path,monkeypatch):
    client,db_file,_integration_id,property_id=fresh(tmp_path,monkeypatch)
    monkeypatch.setattr(rosa,'_channex_request',lambda *args,**kwargs:{'data':[{'id':'availability-task'}]})
    arrival=date.today()+timedelta(days=180)
    departure=arrival+timedelta(days=3)
    created=client.post('/api/reservations',json={
        'property_id':property_id,'guest_name':'Availability Test','arrival_date':str(arrival),
        'departure_date':str(departure),'guest_count':2,'total_huf':126000,'source':'Direct',
    })
    assert created.status_code==200,created.text
    closed=outbox_values(db_file)[0]
    assert closed=={'property_id':'bridge-casa','room_type_id':'room-aqua','date_from':str(arrival),'date_to':str(departure-timedelta(days=1)),'availability':0}
    with sqlite3.connect(db_file) as con:
        assert con.execute("SELECT COUNT(*) FROM channel_ari_values WHERE stay_date=?",(str(departure),)).fetchone()[0]==0

    cancelled=client.delete('/api/reservations/'+created.json()['id'])
    assert cancelled.status_code==200,cancelled.text
    reopened=next(x for x in reversed(outbox_values(db_file)) if x['availability']==1)
    assert reopened['date_from']==str(arrival)
    assert reopened['date_to']==str(departure-timedelta(days=1))


def test_manual_closure_survives_booking_cancellation(tmp_path,monkeypatch):
    client,db_file,integration_id,property_id=fresh(tmp_path,monkeypatch)
    monkeypatch.setattr(rosa,'_channex_request',lambda *args,**kwargs:{'data':[{'id':'availability-task'}]})
    stay=date.today()+timedelta(days=210)
    manual=client.put(f'/api/integrations/{integration_id}/channex/ari',json={
        'date_from':str(stay),'date_to':str(stay),'availability':0,
    })
    assert manual.status_code==200,manual.text
    created=client.post('/api/reservations',json={
        'property_id':property_id,'guest_name':'Manual Closure Test','arrival_date':str(stay),
        'departure_date':str(stay+timedelta(days=1)),'guest_count':1,'total_huf':42000,'source':'Direct',
    })
    assert created.status_code==200,created.text
    assert client.delete('/api/reservations/'+created.json()['id']).status_code==200
    with sqlite3.connect(db_file) as con:
        row=con.execute("SELECT availability,manual_availability,reservation_availability FROM channel_ari_values WHERE integration_id=? AND stay_date=?",(integration_id,str(stay))).fetchone()
        jobs=con.execute("SELECT COUNT(*) FROM channel_ari_outbox WHERE endpoint='/api/v1/availability'",()).fetchone()[0]
    assert row==(0,0,1)
    assert jobs==1


def test_modification_reopens_old_dates_and_closes_new_dates(tmp_path,monkeypatch):
    client,db_file,_integration_id,property_id=fresh(tmp_path,monkeypatch)
    monkeypatch.setattr(rosa,'_channex_request',lambda *args,**kwargs:{'data':[{'id':'availability-task'}]})
    old_arrival=date.today()+timedelta(days=240)
    old_departure=old_arrival+timedelta(days=2)
    created=client.post('/api/reservations',json={
        'property_id':property_id,'guest_name':'Move Test','arrival_date':str(old_arrival),
        'departure_date':str(old_departure),'guest_count':1,'total_huf':84000,'source':'Direct',
    })
    new_arrival=old_arrival+timedelta(days=4)
    new_departure=new_arrival+timedelta(days=2)
    changed=client.patch('/api/reservations/'+created.json()['id'],json={
        'arrival_date':str(new_arrival),'departure_date':str(new_departure),
    })
    assert changed.status_code==200,changed.text
    values=outbox_values(db_file)
    assert any(x['availability']==1 and x['date_from']==str(old_arrival) and x['date_to']==str(old_departure-timedelta(days=1)) for x in values)
    assert any(x['availability']==0 and x['date_from']==str(new_arrival) and x['date_to']==str(new_departure-timedelta(days=1)) for x in values)
