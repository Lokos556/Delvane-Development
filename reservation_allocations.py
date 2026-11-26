"""Physical assignments replace a booking's one-unit aggregate demand, never add to it."""
from datetime import date,datetime,timedelta
from typing import Literal
import json
import uuid
from fastapi import APIRouter,Cookie,HTTPException,Query,Request
from pydantic import BaseModel,ConfigDict,Field
import physical_units


def migrate(con,now):
    con.executescript('''CREATE TABLE IF NOT EXISTS reservation_unit_allocations (
      id TEXT PRIMARY KEY, reservation_id TEXT NOT NULL REFERENCES reservations(id),
      organization_id TEXT NOT NULL, property_id TEXT NOT NULL,
      unit_id TEXT NOT NULL REFERENCES physical_units(id), room_type_id TEXT NOT NULL REFERENCES room_types(id),
      date_from TEXT NOT NULL,date_to TEXT NOT NULL, booking_from TEXT NOT NULL, booking_to TEXT NOT NULL, state TEXT NOT NULL CHECK(state IN ('active','superseded','cancelled')),
      created_at TEXT NOT NULL,created_by TEXT NOT NULL,reason TEXT NOT NULL,
      retired_at TEXT,retired_reason TEXT,CHECK(date_from<date_to));
      CREATE INDEX IF NOT EXISTS idx_allocation_conflict ON reservation_unit_allocations(unit_id,state,date_from,date_to);
      CREATE INDEX IF NOT EXISTS idx_allocation_reservation ON reservation_unit_allocations(reservation_id,state);''')
    con.execute('INSERT OR IGNORE INTO schema_migrations(version,name,applied_at) VALUES (?,?,?)',(3075,'reservation_physical_allocations',now))


class Assignment(BaseModel):
    model_config=ConfigDict(extra='forbid')
    unit_id:str
    date_from:date
    date_to:date


class Replace(BaseModel):
    model_config=ConfigDict(extra='forbid',str_strip_whitespace=True)
    allocations:list[Assignment]=Field(max_length=100)
    reason:str=Field(min_length=3,max_length=500)


class SelectUnit(BaseModel):
    model_config = ConfigDict(extra='forbid', str_strip_whitespace=True)
    mode: Literal['automatic', 'specific']
    unit_id: str | None = None
    expected_active_ids: list[str] = Field(max_length=100)


def active(con,rid):
    return [dict(x) for table in ('reservation_unit_allocations','day_use_allocations') for x in con.execute("SELECT * FROM "+table+" WHERE reservation_id=? AND state='active' ORDER BY date_from,unit_id",(rid,))]


def label(unit):
    return ' · '.join(part for part in (unit['building'], unit['unit_number']) if part)


def display_allocations(con, reservation, assignments=None):
    result = []
    for item in active(con, reservation['id']) if assignments is None else assignments:
        unit = next((unit for unit in physical_units.units_on(
            con, reservation['organization_id'], item['property_id'], item['date_from'])
            if unit['id'] == item['unit_id']), None)
        result.append({**item, 'label': label(unit) if unit else None})
    return result


def full_stay(reservation, unit_id):
    return {'unit_id': unit_id, 'date_from': reservation['arrival_date'],
            'date_to': reservation['departure_date']}


def single_unit_candidates(con, reservation):
    """Stable ordering reserves larger units for parties that need them."""
    if reservation['stay_type'] != 'overnight' or not reservation['room_type_id']:
        return []
    return sorted(
        (unit for unit in physical_units.units_on(
            con, reservation['organization_id'], reservation['property_id'], reservation['arrival_date'])
         if unit['active'] and unit['room_type_id'] == reservation['room_type_id']),
        key=lambda unit: (
            unit['single_beds'] + 2 * unit['double_beds'] + unit['extra_beds'],
            unit['building'], unit['unit_number'], unit['id'],
        ),
    )


def suitable_units(con, reservation, candidates):
    for unit in candidates:
        row = full_stay(reservation, unit['id'])
        try:
            check(con, reservation, [row])
        except HTTPException as exc:
            if exc.status_code not in (409, 422):
                raise
        else:
            yield unit


def options(con, reservation, assignments=()):
    blocker = None
    if reservation['status'] != 'confirmed':
        blocker = 'stay_booking_not_confirmed'
    elif reservation['stay_type'] != 'overnight' or len(assignments) > 1 or any(
        (item['date_from'], item['date_to']) != (reservation['arrival_date'], reservation['departure_date'])
        or item['room_type_id'] != reservation['room_type_id'] for item in assignments
    ):
        blocker = 'unit_plan_requires_review'
    elif con.execute('SELECT 1 FROM guest_occupancy WHERE reservation_id=? AND voided=0 LIMIT 1',
                     (reservation['id'],)).fetchone():
        blocker = 'unit_assignment_has_actual_stay'
    choices = []
    if blocker is None:
        candidates = single_unit_candidates(con, reservation)
        choices = [{'unit_id': unit['id'], 'label': label(unit)}
                   for unit in suitable_units(con, reservation, candidates)]
        if not choices:
            blocker = 'no_eligible_unit' if candidates else 'no_configured_unit'
    return {'options': choices, 'blocker': blocker,
            'expected_active_ids': sorted(item['id'] for item in assignments)}


def auto_assign(con, reservation, actor, now):
    if (reservation['status'] != 'confirmed' or reservation['stay_type'] != 'overnight'
            or active(con, reservation['id'])):
        return False
    unit = next(suitable_units(con, reservation, single_unit_candidates(con, reservation)), None)
    if unit is None:
        return False
    return replace(con, reservation, [full_stay(reservation, unit['id'])], actor,
                   'Automatic full-stay room assignment', now)


def demand(con,reservation,day):
    rows=active(con,reservation['id'])
    present=[x for x in rows if (x['date_from']<=str(day)<x['date_to'] or x['date_from']==x['date_to']==str(day))]
    if not present:return {reservation['room_type_id']:1}
    result={}
    for row in present:result[row['room_type_id']]=result.get(row['room_type_id'],0)+1
    return result


def occupied(con,org,prop,day,room_type,ignore=None,include_day_use=False):
    rows=con.execute("SELECT * FROM reservations WHERE organization_id=? AND property_id=? AND status='confirmed' AND arrival_date<=? AND (departure_date>? OR (stay_type='day_use' AND arrival_date=?))",(org,prop,str(day),str(day),str(day))).fetchall()
    return sum(demand(con,r,day).get(room_type,0) for r in rows if r['id']!=ignore and (include_day_use or r['stay_type']!='day_use'))


def check(con,r,assignments):
    if r['status']!='confirmed' and assignments:raise HTTPException(409,'Only confirmed reservations can be allocated')
    for a in assignments:
        if not r['arrival_date']<=a['date_from']<a['date_to']<=r['departure_date']:raise HTTPException(422,'Allocation must be an overnight interval inside the reservation')
        u=con.execute('SELECT id FROM physical_units WHERE id=? AND property_id=? AND organization_id=?',(a['unit_id'],r['property_id'],r['organization_id'])).fetchone()
        if not u:raise HTTPException(404,'Physical unit not found in reservation property')
        types=set()
        day=date.fromisoformat(a['date_from'])
        while str(day)<a['date_to']:
            unit=next((v for v in physical_units.units_on(con,r['organization_id'],r['property_id'],day) if v['id']==a['unit_id']),None)
            if not unit or not unit['active']:raise HTTPException(409,'Unit is not active throughout allocation')
            types.add(unit['room_type_id'])
            if len(types)>1:raise HTTPException(409,'Split allocation at effective room-type change')
            blocked=con.execute('''SELECT id FROM physical_unit_periods WHERE unit_id=? AND date_from<=? AND date_to>=?
              AND (cancelled_from IS NULL OR cancelled_from>?)''',(a['unit_id'],str(day),str(day),str(day))).fetchone()
            if blocked:raise HTTPException(409,'Unit is OOO/OOS on an allocated night')
            day+=timedelta(days=1)
        resolved=next(iter(types))
        if a.get('id') and a['room_type_id']!=resolved:raise HTTPException(409,'Remove allocations before changing the physical unit room type')
        a['room_type_id']=resolved
        import day_use
        lo,hi=day_use.allocated_window(con,r,a)
        day_use.physical_conflict(con,r,a['unit_id'],lo,hi)
        conflict=con.execute('''SELECT a.id FROM reservation_unit_allocations a JOIN reservations r ON r.id=a.reservation_id
          WHERE a.unit_id=? AND a.state='active' AND r.status='confirmed' AND a.reservation_id!=?
          AND a.date_from<? AND a.date_to>? LIMIT 1''',(a['unit_id'],r['id'],a['date_to'],a['date_from'])).fetchone()
        if conflict:raise HTTPException(409,'Physical unit already allocated')
    day=date.fromisoformat(r['arrival_date'])
    while str(day)<r['departure_date']:
        present=[a for a in assignments if a['date_from']<=str(day)<a['date_to']]
        if len({a['unit_id'] for a in present})!=len(present):raise HTTPException(409,'Duplicate overlapping unit allocation')
        needed={}
        if present:
            capacity=0
            for a in present:
                unit=next(u for u in physical_units.units_on(con,r['organization_id'],r['property_id'],day) if u['id']==a['unit_id'])
                capacity+=unit['single_beds']+2*unit['double_beds']+unit['extra_beds']
                needed[a['room_type_id']]=needed.get(a['room_type_id'],0)+1
            if r['guest_count']>capacity:raise HTTPException(409,'Allocated sleeping capacity is insufficient')
        else:needed={r['room_type_id']:1}
        for rt,count in needed.items():
            room=con.execute('SELECT inventory_count,max_guests FROM room_types WHERE id=? AND organization_id=? AND property_id=? AND active=1',(rt,r['organization_id'],r['property_id'])).fetchone()
            if not room:raise HTTPException(409,'Allocation room type is unavailable')
            if not present and r['guest_count']>room['max_guests']:raise HTTPException(409,'Unallocated reservation exceeds its primary room-type capacity')
            used=occupied(con,r['organization_id'],r['property_id'],day,rt,r['id'])
            if used+count>room['inventory_count']:raise HTTPException(409,'Physical allocation conflicts with aggregate inventory')
            physical=physical_units.capacity(con,r['organization_id'],r['property_id'],day)
            available=sum(1 for u in physical['units'] if u['room_type_id']==rt and u['operational_state']=='available')
            if present and used+count>available:raise HTTPException(409,'Aggregate reservations exceed operational physical availability; reconcile inventory')
        day+=timedelta(days=1)

    if assignments and con.execute("SELECT id FROM reservations WHERE property_id=? AND stay_type='day_use' AND status='confirmed' LIMIT 1",(r['property_id'],)).fetchone():
        import day_use
        counts={}
        for a in assignments:counts[a['room_type_id']]=max(counts.get(a['room_type_id'],0),sum(b['room_type_id']==a['room_type_id'] and b['date_from']<=a['date_from']<b['date_to'] for b in assignments))
        day_use.aggregate_check(con,r,counts)


def protect_actual_occupancy(con, reservation, assignments):
    visits = con.execute('''SELECT unit_id, started_at FROM guest_occupancy
        WHERE reservation_id=? AND ended_at IS NULL AND voided=0''', (reservation['id'],)).fetchall()
    if not visits:
        return
    from guest_stays import stay_timezone
    tz = stay_timezone(con, reservation['organization_id'], reservation['property_id'])
    for visit in visits:
        day = str(datetime.fromisoformat(visit['started_at']).astimezone(tz).date())
        if not any(a['unit_id'] == visit['unit_id'] and (
                a['date_from'] <= day < a['date_to'] or a['date_from'] == a['date_to'] == day
        ) for a in assignments):
            raise HTTPException(409, {'code':'unit_assignment_has_actual_stay'})


def replace(con,r,assignments,actor,reason,now,state='superseded',*,actual_transfer=False):
    if not actual_transfer:
        protect_actual_occupancy(con,r,assignments)
    if r['stay_type']=='day_use':
        import day_use
        return day_use.replace(con,r,assignments,actor,reason,now)
    check(con,r,assignments)
    old=active(con,r['id'])
    shape=lambda rows:sorted((a['unit_id'],a['date_from'],a['date_to']) for a in rows)
    if shape(old)==shape(assignments):return False
    con.execute("UPDATE reservation_unit_allocations SET state=?,retired_at=?,retired_reason=? WHERE reservation_id=? AND state='active'",(state,now,reason,r['id']))
    for a in assignments:
        con.execute('''INSERT INTO reservation_unit_allocations(id,reservation_id,organization_id,property_id,unit_id,room_type_id,date_from,date_to,booking_from,booking_to,state,created_at,created_by,reason)
          VALUES (?,?,?,?,?,?,?,?,?,?,'active',?,?,?)''',(str(uuid.uuid4()),r['id'],r['organization_id'],r['property_id'],a['unit_id'],a['room_type_id'],a['date_from'],a['date_to'],r['arrival_date'],r['departure_date'],now,actor,reason))
    return True


def sync_change(con,old,new,now,*,validate_existing=False):
    rows=active(con,old['id'])
    if not rows:return
    if not validate_existing and all(old[key] == new[key] for key in (
        'status','property_id','room_type_id','arrival_date','departure_date','guest_count',
        'stay_type','planned_arrival_time','planned_departure_time',
    )):
        return
    if new['status']!='confirmed' and con.execute('SELECT id FROM guest_occupancy WHERE reservation_id=? AND ended_at IS NULL AND voided=0',(old['id'],)).fetchone():raise HTTPException(409,'Record actual departures before cancelling an occupied booking')
    import day_use
    if old['stay_type']=='day_use':return day_use.reconcile(con,old,new,now)
    if new['stay_type']!='overnight':raise HTTPException(409,'Remove overnight allocations before changing stay type')
    if new['status']!='confirmed':
        con.execute("UPDATE reservation_unit_allocations SET state='cancelled',retired_at=?,retired_reason='Reservation no longer confirmed' WHERE reservation_id=? AND state='active'",(now,old['id']));return
    if old['property_id']!=new['property_id'] or old['room_type_id']!=new['room_type_id']:
        raise HTTPException(409,'Remove physical allocations before changing reservation property or primary room type')
    changed=old['arrival_date']!=new['arrival_date'] or old['departure_date']!=new['departure_date']
    if changed:
        if any(a['date_from']!=old['arrival_date'] or a['date_to']!=old['departure_date'] for a in rows):
            raise HTTPException(409,'Remove split allocations before changing reservation dates')
        for a in rows:a['date_from']=new['arrival_date'];a['date_to']=new['departure_date']
    replace(con,new,rows,'reservation_operation','Reservation details changed',now)


def install(backend):
    router=APIRouter(prefix='/api/reservations/{reservation_id}/allocations')
    def load(con,rid,session,write=False):
        user=backend.require_user(session);backend.require_roles(user,'owner','manager')
        if write:
            backend._lock_reservation(con, rid, user['organization_id'])
        row=con.execute('SELECT * FROM reservations WHERE id=? AND organization_id=?',(rid,user['organization_id'])).fetchone()
        if not row:raise HTTPException(404,'Reservation not found')
        return user,dict(row)
    @router.get('')
    def get(reservation_id:str,include_options:bool=False,rosa_session:str|None=Cookie(default=None)):
        with backend.db() as con:
            user,r=load(con,reservation_id,rosa_session)
            current = active(con, reservation_id)
            return {'active':display_allocations(con,r,current),
                    'history':[dict(x) for table in ('reservation_unit_allocations','day_use_allocations') for x in con.execute('SELECT * FROM '+table+' WHERE reservation_id=? ORDER BY created_at,id',(reservation_id,))],
                    **(options(con,r,current) if include_options else {})}
    @router.put('')
    def put(reservation_id:str,body:Replace|SelectUnit,request:Request,rosa_session:str|None=Cookie(default=None)):
        with backend.db() as con:
            user,r=load(con,reservation_id,rosa_session,True)
            previous=active(con,reservation_id)
            if isinstance(body, SelectUnit):
                if sorted(body.expected_active_ids) != sorted(a['id'] for a in previous):
                    raise HTTPException(409, {'code':'unit_assignment_changed'})
                if (body.mode == 'specific') != bool(body.unit_id):
                    raise HTTPException(422, {'code':'invalid_unit_selection'})
                choices = options(con, r, previous)
                if choices['blocker']:
                    raise HTTPException(409, {'code':choices['blocker']})
                unit_id = body.unit_id
                if body.mode == 'automatic':
                    # Keep an already suitable assignment when automatic is retried.
                    unit_id = previous[0]['unit_id'] if previous and any(
                        unit['unit_id'] == previous[0]['unit_id'] for unit in choices['options']
                    ) else choices['options'][0]['unit_id']
                if not any(unit['unit_id'] == unit_id for unit in choices['options']):
                    raise HTTPException(409, {'code':'no_eligible_unit'})
                rows = [full_stay(r, unit_id)]
                reason = 'Automatic full-stay room assignment' if body.mode == 'automatic' else 'Operator selected a full-stay room'
            else:
                rows = [a.model_dump(mode='json') for a in body.allocations]
                reason = body.reason
            changed=replace(con,r,rows,user['id'],reason,backend.now_iso())
            # Recalculate existing ARI for every affected type, replacing the primary
            # default demand. Same-type reassignments have no inventory change.
            def profile(items):
                if not items and r['stay_type']=='overnight':
                    return [(r['room_type_id'],r['arrival_date'],r['departure_date'])]
                return sorted((a['room_type_id'],a['date_from'],a['date_to']) for a in items)
            if profile(previous)!=profile(rows):
                ids=[]
                for rt in {r['room_type_id']}|{a['room_type_id'] for a in previous+rows}:
                    ids+=backend._queue_reservation_availability(con,user['organization_id'],r['property_id'],r['arrival_date'],r['departure_date'],reason='Reservation unit demand changed',force=True,room_type_id=rt)
                backend._merge_channex_availability_outboxes(con,ids)
            if changed:backend.audit_event(con,user['organization_id'],'reservation.allocations_changed','Physical reservation allocations updated.',actor_user_id=user['id'],entity_type='reservation',entity_id=reservation_id,metadata={'reason':reason},request=request)
            if changed:
                import ntak_reporting
                ntak_reporting.capture_reservation(con,user['organization_id'],reservation_id)
                if r['stay_type']=='overnight':
                    backend._refresh_overnight_cleaning(con, user['organization_id'], r['property_id'])
        return {'ok':True,'changed':changed}
    backend.app.include_router(router)

    @backend.app.get('/api/properties/{property_id}/physical-units/assignment-options')
    def preview(property_id:str,room_type_id:str,arrival_date:date,departure_date:date,
                guest_count:int=Query(ge=1),rosa_session:str|None=Cookie(default=None)):
        user=backend.require_user(rosa_session)
        backend.require_roles(user,'owner','manager')
        start,end = str(arrival_date), str(departure_date)
        backend.validate_reservation_dates(start,end)
        with backend.db() as con:
            if not con.execute('''SELECT 1 FROM room_types
                WHERE id=? AND property_id=? AND organization_id=? AND active=1''',
                (room_type_id,property_id,user['organization_id'])).fetchone():
                raise HTTPException(404,'Room type unavailable')
            return options(con, {'id':'', 'organization_id':user['organization_id'],
                                 'property_id':property_id, 'room_type_id':room_type_id,
                                 'arrival_date':start, 'departure_date':end, 'guest_count':guest_count,
                                 'status':'confirmed', 'stay_type':'overnight'})


def reconcile_property(con,org,prop,now,*,validate_existing=True):
    for ref in con.execute("SELECT reservation_id FROM reservation_unit_allocations WHERE organization_id=? AND property_id=? AND state='active' UNION SELECT reservation_id FROM day_use_allocations WHERE organization_id=? AND property_id=? AND state='active'",(org,prop,org,prop)).fetchall():
        r=dict(con.execute('SELECT * FROM reservations WHERE id=?',(ref['reservation_id'],)).fetchone())
        rows=active(con,r['id']);old={**r,'property_id':rows[0]['property_id'],'arrival_date':rows[0]['booking_from'],'departure_date':rows[0]['booking_to']}
        # ARI publication projects already validated demand. A different open
        # stay can temporarily overlap a future allocation before its checkout.
        if not validate_existing and r['status']=='confirmed' and old==r:
            continue
        sync_change(con,old,r,now,validate_existing=validate_existing)


def validate_unit_change(con,org,prop,now):
    reconcile_property(con,org,prop,now)
    for v in con.execute('''SELECT o.unit_id,COUNT(*) count FROM guest_occupancy o JOIN reservations r ON r.id=o.reservation_id
      WHERE r.organization_id=? AND r.property_id=? AND o.ended_at IS NULL AND o.voided=0 GROUP BY o.unit_id''',(org,prop)).fetchall():
        unit=next((u for u in physical_units.capacity(con,org,prop,now[:10])['units'] if u['id']==v['unit_id']),None)
        if not unit or unit['operational_state']!='available' or unit['regular_places']+unit['extra_beds']<v['count']:raise HTTPException(409,'Physical change conflicts with actual occupancy')
