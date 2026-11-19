from datetime import timedelta,timezone
import app
import day_use
from test_flutter_reservation_reception import client,body,login
from test_reservation_allocations import setup
from test_actual_stays import act


def make(client,units,start='10:00',end='13:00',offset=0):
    p=body();p['arrival_date']=p['departure_date']=str(app.date.today()+timedelta(days=offset))
    p.update(stay_type='day_use',planned_arrival_time=start,planned_departure_time=end,total_huf=62500)
    p['allocations']=[{'unit_id':u[0],'date_from':p['arrival_date'],'date_to':p['departure_date']} for u in units]
    return client.post('/api/reservations',json=p),p


def test_same_day_multi_unit_true_dates_zero_nights_actual_stays_cleaning(client):
    rt,units=setup(client);made,p=make(client,units[2:],offset=-1)
    assert made.status_code==200,made.text
    rid=made.json()['id']
    with app.db() as con:
        r=con.execute('SELECT * FROM reservations WHERE id=?',(rid,)).fetchone()
        assert r['arrival_date']==r['departure_date'] and r['total_huf']==62500
        gids=[g['id'] for g in con.execute('SELECT id FROM guest_records WHERE reservation_id=? ORDER BY id',(rid,))]
        assert con.execute("SELECT COUNT(*) c FROM work_tasks WHERE previous_reservation_id=? AND source_key LIKE 'day-use-cleaning:%'",(rid,)).fetchone()['c']==2
        day_use.migrate(app,con);day_use.migrate(app,con)
    tz=timezone(timedelta(hours=1));at=app.datetime.fromisoformat(p['arrival_date']+'T10:30:00').replace(tzinfo=tz)
    for gid,unit in zip(gids,units[2:]):
        result,_=act(client,rid,[gid],at,uid=unit[0]);assert result.status_code==200,result.text
        result,_=act(client,rid,[gid],at+timedelta(hours=2),kind='depart');assert result.status_code==200,result.text
    result=client.get(f'/api/reservations/{rid}/actual-stay').json()
    assert result['actual_occupants']==0 and len(result['events'])==4
    assert all(v['started_at'][:10]==v['ended_at'][:10] for g in result['guests'] for v in g['history'])


def test_day_use_conflicts_adjacency_overnight_coexistence_and_stock(client):
    rt,units=setup(client);first,p=make(client,[units[2]])
    assert first.status_code==200,first.text
    overlap,_=make(client,[units[2]],start='12:00',end='14:00');assert overlap.status_code==409
    adjacent,_=make(client,[units[2]],start='13:00',end='14:00');assert adjacent.status_code==200,adjacent.text
    overnight=body();overnight['arrival_date']=p['arrival_date'];overnight['departure_date']=str(app.date.today()+timedelta(days=1))
    overnight['allocations']=[{'unit_id':units[2][0],'date_from':overnight['arrival_date'],'date_to':overnight['departure_date']}]
    good=client.post('/api/reservations',json=overnight);assert good.status_code==200,good.text
    bad,_=make(client,[units[2]],start='16:00',end='18:00');assert bad.status_code==409
    with app.db() as con:
        # Two nonoverlapping direct uses still conservatively consume two channel-day units.
        assert app._reservation_availability(con,'org_casa_rosa','prop_flora',app.date.today(),rt)==1


def test_invalid_day_use_and_no_implicit_overnight_conversion(client):
    rt,units=setup(client)
    assert make(client,[],start='10:00',end='13:00')[0].status_code==422
    assert make(client,units[2:],start='14:00',end='12:00')[0].status_code==422
    p=body();p['departure_date']=p['arrival_date']
    assert client.post('/api/reservations',json=p).status_code in (400,422)
    made,p=make(client,[units[2]])
    assert made.status_code==200
    rid=made.json()['id']
    assert client.delete('/api/reservations/'+rid).status_code==200
    assert not client.get(f'/api/reservations/{rid}/allocations').json()['active']
    with app.db() as con:
        assert con.execute("SELECT COUNT(*) c FROM day_use_allocations WHERE reservation_id=? AND state='cancelled'",(rid,)).fetchone()['c']==1


def test_nonexistent_dst_time_is_rejected(client):
    rt,units=setup(client)
    with app.db() as con:
        r={'property_id':'prop_flora','organization_id':'org_casa_rosa','stay_type':'day_use','arrival_date':'2026-03-29','departure_date':'2026-03-29','planned_arrival_time':'02:30','planned_departure_time':'04:00'}
        import pytest
        with pytest.raises(app.HTTPException):day_use.window(con,r)
