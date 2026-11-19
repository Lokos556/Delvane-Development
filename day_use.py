"""Explicit same-day stays. Direct time windows are distinct from channel-night stock."""
from datetime import date,datetime,timedelta,time,timezone
from zoneinfo import ZoneInfo
import uuid
from fastapi import HTTPException
import physical_units


def migrate(backend,con):
    for name,ddl in [('stay_type',"TEXT NOT NULL DEFAULT 'overnight'"),('planned_arrival_time','TEXT'),('planned_departure_time','TEXT')]:backend.add_column_if_missing(con,'reservations',name,ddl)
    con.executescript('''CREATE TABLE IF NOT EXISTS day_use_allocations (
      id TEXT PRIMARY KEY,reservation_id TEXT NOT NULL REFERENCES reservations(id),organization_id TEXT NOT NULL,property_id TEXT NOT NULL,
      unit_id TEXT NOT NULL REFERENCES physical_units(id),room_type_id TEXT NOT NULL REFERENCES room_types(id),
      date_from TEXT NOT NULL,date_to TEXT NOT NULL,booking_from TEXT NOT NULL,booking_to TEXT NOT NULL,
      planned_start_at TEXT NOT NULL,planned_end_at TEXT NOT NULL,
      state TEXT NOT NULL CHECK(state IN ('active','superseded','cancelled')),
      created_at TEXT NOT NULL,created_by TEXT NOT NULL,reason TEXT NOT NULL,retired_at TEXT,retired_reason TEXT,
      CHECK(date_from=date_to),CHECK(planned_start_at<planned_end_at));
      CREATE INDEX IF NOT EXISTS idx_day_use_unit ON day_use_allocations(unit_id,state,planned_start_at,planned_end_at);
    ''')
    con.execute('INSERT OR IGNORE INTO schema_migrations(version,name,applied_at) VALUES (?,?,?)',(3080,'explicit_day_use_reservations',backend.now_iso()))


def validate(arrival,departure,kind='overnight',start=None,end=None):
    try:
        a,b=date.fromisoformat(arrival),date.fromisoformat(departure)
        if kind=='day_use':
            if a!=b:raise ValueError()
            if not start or not end or len(start)!=5 or len(end)!=5 or time.fromisoformat(start)>=time.fromisoformat(end):raise ValueError()
        elif kind!='overnight' or b<=a:raise ValueError()
    except (ValueError,TypeError):raise HTTPException(422,{'code':'invalid_stay_window'}) from None


def window(con,r):
    p=con.execute('SELECT checkin_time,checkout_time FROM properties WHERE id=?',(r['property_id'],)).fetchone()
    s=con.execute('SELECT timezone FROM organization_settings WHERE organization_id=?',(r['organization_id'],)).fetchone()
    tz=ZoneInfo(s['timezone'] if s else 'Europe/Budapest')
    day_use=r.get('stay_type')=='day_use' if isinstance(r,dict) else r['stay_type']=='day_use'
    start=r['planned_arrival_time'] if day_use else p['checkin_time']
    end=r['planned_departure_time'] if day_use else p['checkout_time']
    def local(value):
        naive=datetime.fromisoformat(value);aware=naive.replace(tzinfo=tz)
        if aware.astimezone(timezone.utc).astimezone(tz).replace(tzinfo=None)!=naive or aware.utcoffset()!=naive.replace(tzinfo=tz,fold=1).utcoffset():
            raise HTTPException(422,'Planned local time is ambiguous or nonexistent at a timezone transition')
        return aware.astimezone(timezone.utc)
    return local(r['arrival_date']+'T'+start),local(r['departure_date']+'T'+end)


def allocated_window(con,r,a):
    if r['stay_type']=='day_use':return window(con,r)
    copy=dict(r);copy['arrival_date']=a['date_from'];copy['departure_date']=a['date_to']
    return window(con,copy)


def physical_conflict(con,r,uid,start,end):
    for table in ('reservation_unit_allocations','day_use_allocations'):
        for a in con.execute('''SELECT a.* FROM '''+table+''' a JOIN reservations r ON r.id=a.reservation_id
          WHERE a.unit_id=? AND a.state='active' AND r.status='confirmed' AND a.reservation_id!=?''',(uid,r['id'])):
            other=con.execute('SELECT * FROM reservations WHERE id=?',(a['reservation_id'],)).fetchone()
            lo,hi=allocated_window(con,other,a)
            if lo<end and hi>start:raise HTTPException(409,{'code':'physical_time_conflict'})
    for v in con.execute('SELECT * FROM guest_occupancy WHERE unit_id=? AND reservation_id!=? AND voided=0',(uid,r['id'])):
        if datetime.fromisoformat(v['started_at'])<end and (v['ended_at'] is None or datetime.fromisoformat(v['ended_at'])>start):raise HTTPException(409,{'code':'actual_occupancy_conflict'})


def aggregate_check(con,r,counts):
    import reservation_allocations as ra
    start,end=window(con,r)
    for rt,count in counts.items():
        room=con.execute('SELECT inventory_count FROM room_types WHERE id=? AND organization_id=? AND property_id=? AND active=1',(rt,r['organization_id'],r['property_id'])).fetchone()
        if not room:raise HTTPException(409,'Room type is unavailable')
        points=[(start,count),(end,-count)]
        for other in con.execute("SELECT * FROM reservations WHERE property_id=? AND organization_id=? AND status='confirmed' AND id!=? AND arrival_date<=? AND departure_date>=?",(r['property_id'],r['organization_id'],r['id'],r['departure_date'],r['arrival_date'])):
            assigned=ra.active(con,other['id'])
            if assigned:
                for a in assigned:
                    if a['room_type_id']!=rt:continue
                    lo,hi=allocated_window(con,other,a)
                    if lo<end and hi>start:points.extend([(max(lo,start),1),(min(hi,end),-1)])
            elif other['room_type_id']==rt:
                lo,hi=window(con,other)
                if lo<end and hi>start:points.extend([(max(lo,start),1),(min(hi,end),-1)])
        used=0
        for _,delta in sorted(points,key=lambda v:(v[0],v[1])):
            used+=delta
            if used>room['inventory_count']:raise HTTPException(409,{'code':'aggregate_time_conflict'})


def replace(con,r,rows,actor,reason,now):
    import reservation_allocations as ra
    if r['status']=='confirmed' and not rows:raise HTTPException(409,'Day-use bookings require explicit physical units')
    if r['status']!='confirmed' and rows:raise HTTPException(409,'Only confirmed stays can be allocated')
    validate(r['arrival_date'],r['departure_date'],'day_use',r['planned_arrival_time'],r['planned_departure_time'])
    start,end=window(con,r);day=date.fromisoformat(r['arrival_date']);unique=set();capacity=0;counts={}
    for a in rows:
        if a['date_from']!=r['arrival_date'] or a['date_to']!=r['departure_date']:raise HTTPException(422,'Day-use allocation dates must match the same booking day')
        if a['unit_id'] in unique:raise HTTPException(409,'Duplicate unit')
        unique.add(a['unit_id'])
        unit=next((u for u in physical_units.capacity(con,r['organization_id'],r['property_id'],day)['units'] if u['id']==a['unit_id']),None)
        if not unit or unit['operational_state']!='available':raise HTTPException(409,{'code':'stay_unit_unavailable'})
        physical_conflict(con,r,a['unit_id'],start,end)
        a.update(room_type_id=unit['room_type_id'],planned_start_at=start.isoformat(),planned_end_at=end.isoformat())
        capacity+=unit['single_beds']+2*unit['double_beds']+unit['extra_beds'];counts[unit['room_type_id']]=counts.get(unit['room_type_id'],0)+1
    if rows and r['guest_count']>capacity:raise HTTPException(409,'Insufficient day-use sleeping capacity')
    aggregate_check(con,r,counts)
    old=ra.active(con,r['id'])
    shape=lambda values:sorted((a['unit_id'],a['date_from'],a['date_to'],a.get('planned_start_at'),a.get('planned_end_at')) for a in values)
    if shape(old)==shape(rows):return False
    con.execute("UPDATE day_use_allocations SET state='superseded',retired_at=?,retired_reason=? WHERE reservation_id=? AND state='active'",(now,reason,r['id']))
    for a in rows:
        con.execute('''INSERT INTO day_use_allocations(id,reservation_id,organization_id,property_id,unit_id,room_type_id,date_from,date_to,booking_from,booking_to,planned_start_at,planned_end_at,state,created_at,created_by,reason)
          VALUES (?,?,?,?,?,?,?,?,?,?,?,?,'active',?,?,?)''',(str(uuid.uuid4()),r['id'],r['organization_id'],r['property_id'],a['unit_id'],a['room_type_id'],a['date_from'],a['date_to'],r['arrival_date'],r['departure_date'],a['planned_start_at'],a['planned_end_at'],now,actor,reason))
    return True


def reconcile(con,old,new,now):
    import reservation_allocations as ra
    rows=ra.active(con,old['id'])
    if not rows:return
    if new['status']!='confirmed':
        con.execute("UPDATE day_use_allocations SET state='cancelled',retired_at=?,retired_reason='Reservation no longer confirmed' WHERE reservation_id=? AND state='active'",(now,new['id']));return
    if old['property_id']!=new['property_id'] or new['stay_type']!='day_use':raise HTTPException(409,'Cannot change the property or type of an allocated day-use booking')
    for a in rows:a['date_from']=new['arrival_date'];a['date_to']=new['departure_date']
    replace(con,new,rows,'reservation_operation','Day-use booking changed',now)


def refresh_cleaning(backend,con,org):
    for r in con.execute("SELECT * FROM reservations WHERE organization_id=? AND stay_type='day_use'",(org,)).fetchall():
        for a in con.execute("SELECT * FROM day_use_allocations WHERE reservation_id=? AND state='active'",(r['id'],)).fetchall():
            key='day-use-cleaning:'+r['id']+':'+a['unit_id']
            last=con.execute('SELECT MAX(ended_at) at FROM guest_occupancy WHERE reservation_id=? AND unit_id=? AND voided=0',(r['id'],a['unit_id'])).fetchone()['at']
            earliest=r['planned_departure_time']
            if last:
                settings=con.execute('SELECT timezone FROM organization_settings WHERE organization_id=?',(org,)).fetchone()
                local=datetime.fromisoformat(last).astimezone(ZoneInfo(settings['timezone'] if settings else 'Europe/Budapest'))
                if str(local.date())==r['departure_date']:earliest=max(earliest,local.strftime('%H:%M'))
            if r['status']!='confirmed':continue
            _,expected_end=window(con,r)
            next_starts=[]
            for table in ('reservation_unit_allocations','day_use_allocations'):
                for other in con.execute('SELECT a.* FROM '+table+" a JOIN reservations r ON r.id=a.reservation_id WHERE a.unit_id=? AND a.state='active' AND r.status='confirmed' AND r.id!=?",(a['unit_id'],r['id'])):
                    other_r=con.execute('SELECT * FROM reservations WHERE id=?',(other['reservation_id'],)).fetchone()
                    lo,_=allocated_window(con,other_r,other)
                    if lo>=expected_end:next_starts.append(lo)
            settings=con.execute('SELECT timezone FROM organization_settings WHERE organization_id=?',(org,)).fetchone()
            tz=ZoneInfo(settings['timezone'] if settings else 'Europe/Budapest')
            nxt=min(next_starts).astimezone(tz) if next_starts else None
            deadline=nxt.strftime('%H:%M') if nxt and str(nxt.date())==r['departure_date'] else None
            existing=con.execute('SELECT id FROM work_tasks WHERE source_key=?',(key,)).fetchone()
            if existing:
                con.execute('UPDATE work_tasks SET scheduled_date=?,earliest_time=? WHERE source_key=?',(r['departure_date'],earliest,key))
            else:
                con.execute('''INSERT INTO work_tasks(id,organization_id,property_id,task_type,title,detail,scheduled_date,earliest_time,priority,status,source_key,previous_reservation_id,created_at)
                  VALUES (?,?,?,'cleaning','Day-use cleaning',?,?,?,'normal','open',?,?,?)''',
                  (str(uuid.uuid4()),org,r['property_id'],'Physical unit '+a['unit_id'],r['departure_date'],earliest,key,r['id'],backend.now_iso()))
            con.execute('UPDATE work_tasks SET deadline_time=?,priority=? WHERE source_key=?',(deadline,'high' if deadline else 'normal',key))
    for task in con.execute("SELECT id FROM work_tasks WHERE organization_id=? AND source_key LIKE 'day-use-cleaning:%'",(org,)).fetchall():backend.ensure_task_checklist(con,org,task['id'])
    for task in con.execute("SELECT id,previous_reservation_id,source_key FROM work_tasks WHERE organization_id=? AND source_key LIKE 'day-use-cleaning:%' AND status NOT IN ('complete','cancelled')",(org,)).fetchall():
        uid=task['source_key'].rsplit(':',1)[-1]
        if not con.execute("SELECT a.id FROM day_use_allocations a JOIN reservations r ON r.id=a.reservation_id WHERE r.id=? AND r.status='confirmed' AND a.state='active' AND a.unit_id=?",(task['previous_reservation_id'],uid)).fetchone():
            con.execute("UPDATE work_tasks SET status='cancelled' WHERE id=?",(task['id'],))
