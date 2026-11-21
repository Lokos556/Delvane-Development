"""Physical inventory is explicit and versioned; aggregate channel stock is untouched."""
from datetime import date
import uuid
from zoneinfo import ZoneInfo
from fastapi import APIRouter, Cookie, HTTPException, Request
from pydantic import BaseModel, ConfigDict, Field
from ntak_contracts import contracts, XSD


def migrate(con, now):
    con.executescript('''
    CREATE TABLE IF NOT EXISTS physical_units (
      id TEXT PRIMARY KEY, organization_id TEXT NOT NULL REFERENCES organizations(id),
      property_id TEXT NOT NULL REFERENCES properties(id), created_at TEXT NOT NULL
    );
    CREATE INDEX IF NOT EXISTS idx_physical_property ON physical_units(organization_id,property_id);
    CREATE TABLE IF NOT EXISTS physical_unit_versions (
      unit_id TEXT NOT NULL REFERENCES physical_units(id), effective_from TEXT NOT NULL,
      room_type_id TEXT NOT NULL REFERENCES room_types(id), building TEXT NOT NULL,
      unit_number TEXT NOT NULL, classification TEXT NOT NULL,
      single_beds INTEGER NOT NULL CHECK(single_beds>=0),
      double_beds INTEGER NOT NULL CHECK(double_beds>=0),
      extra_beds INTEGER NOT NULL CHECK(extra_beds>=0),
      active INTEGER NOT NULL CHECK(active IN (0,1)), reason TEXT NOT NULL,
      recorded_at TEXT NOT NULL, recorded_by TEXT NOT NULL,
      CHECK(single_beds+2*double_beds>0),
      PRIMARY KEY(unit_id,effective_from)
    );
    CREATE TABLE IF NOT EXISTS physical_unit_periods (
      id TEXT PRIMARY KEY, unit_id TEXT NOT NULL REFERENCES physical_units(id),
      state TEXT NOT NULL CHECK(state IN ('OOO','OOS')),
      date_from TEXT NOT NULL, date_to TEXT NOT NULL, reason TEXT NOT NULL,
      recorded_at TEXT NOT NULL, recorded_by TEXT NOT NULL,
      cancelled_from TEXT, cancelled_at TEXT, cancelled_by TEXT, cancellation_reason TEXT,
      CHECK(date_from<=date_to)
    );
    ''')
    con.execute('INSERT OR IGNORE INTO schema_migrations(version,name,applied_at) VALUES (?,?,?)',
                (3074,'physical_units_and_operational_periods',now))


def migrate_stock_reconciliation(con, now):
    con.executescript('''
    CREATE TABLE IF NOT EXISTS historical_room_stock (
      organization_id TEXT NOT NULL REFERENCES organizations(id),
      property_id TEXT NOT NULL REFERENCES properties(id),
      room_type_id TEXT NOT NULL REFERENCES room_types(id),
      business_date TEXT NOT NULL,
      revision INTEGER NOT NULL CHECK(revision>0),
      inventory_count INTEGER NOT NULL CHECK(inventory_count BETWEEN 0 AND 500),
      reason TEXT NOT NULL, recorded_at TEXT NOT NULL, recorded_by TEXT NOT NULL,
      PRIMARY KEY(organization_id,property_id,business_date,room_type_id,revision)
    );
    ''')
    con.execute('INSERT OR IGNORE INTO schema_migrations(version,name,applied_at) VALUES (?,?,?)',
                (3090, 'historical_room_stock_reconciliation', now))


class UnitDetails(BaseModel):
    model_config=ConfigDict(extra='forbid',str_strip_whitespace=True)
    effective_from: date
    room_type_id: str
    building: str=Field(min_length=1,max_length=50)
    unit_number: str=Field(min_length=1,max_length=50)
    classification: str
    single_beds: int=Field(strict=True,ge=0,le=10000)
    double_beds: int=Field(strict=True,ge=0,le=10000)
    extra_beds: int=Field(strict=True,ge=0,le=10000)
    active: bool=True
    reason: str=Field(min_length=3,max_length=500)


class Period(BaseModel):
    model_config=ConfigDict(extra='forbid',str_strip_whitespace=True)
    state: str
    date_from: date
    date_to: date
    reason: str=Field(min_length=3,max_length=500)


class CancelPeriod(BaseModel):
    model_config=ConfigDict(extra='forbid',str_strip_whitespace=True)
    effective_from: date
    reason: str=Field(min_length=3,max_length=500)


class HistoricalStock(BaseModel):
    model_config = ConfigDict(extra='forbid', str_strip_whitespace=True)
    business_date: date
    inventory_count: int = Field(strict=True, ge=0, le=500)
    reason: str = Field(min_length=3, max_length=500)


def reconciliation_date_allowed(backend, con, org, prop, day):
    import business_days
    calendar = business_days.settings(con, org, prop)
    organization = con.execute('SELECT timezone FROM organization_settings WHERE organization_id=?', (org,)).fetchone()
    tz = calendar or organization
    return day < backend.datetime.now(ZoneInfo(tz['timezone'] if tz else 'Europe/Budapest')).date()


def units_on(con,org,prop,day):
    return [dict(x) for x in con.execute('''SELECT u.id,u.property_id,v.* FROM physical_units u
      JOIN physical_unit_versions v ON v.unit_id=u.id
      WHERE u.organization_id=? AND u.property_id=? AND v.effective_from=(
        SELECT MAX(v2.effective_from) FROM physical_unit_versions v2 WHERE v2.unit_id=u.id AND v2.effective_from<=?)
      ORDER BY v.building,v.unit_number,u.id''',(org,prop,str(day)))]


def capacity(con,org,prop,day):
    units=units_on(con,org,prop,day)
    counts={key:{'units':0,'regular_places':0,'extra_places':0} for key in ('total','OOO','OOS','available')}
    details=[]
    for unit in units:
        if not unit['active']:continue
        period=con.execute('''SELECT id,state FROM physical_unit_periods WHERE unit_id=? AND date_from<=? AND date_to>=?
          AND (cancelled_from IS NULL OR cancelled_from>?)''',(unit['id'],str(day),str(day),str(day))).fetchone()
        state=period['state'] if period else 'available'
        regular=unit['single_beds']+2*unit['double_beds']
        for key in ('total',state):
            counts[key]['units']+=1;counts[key]['regular_places']+=regular;counts[key]['extra_places']+=unit['extra_beds']
        details.append({**unit,'operational_state':state,'regular_places':regular})
    aggregate_types=con.execute('SELECT id,inventory_count FROM room_types WHERE organization_id=? AND property_id=? AND active=1',(org,prop)).fetchall()
    represented={r['id']:sum(1 for u in details if u['room_type_id']==r['id']) for r in aggregate_types}
    # A prior date's documented stock does not redefine live selling stock.
    history = {}
    for record in con.execute('''SELECT room_type_id, inventory_count, revision, recorded_at
        FROM historical_room_stock WHERE organization_id=? AND property_id=? AND business_date=?
        ORDER BY revision''', (org, prop, str(day))):
        history[record['room_type_id']] = dict(record)
    comparison = []
    for room in aggregate_types:
        room_id = room['id']
        historical = history.get(room_id)
        count = historical['inventory_count'] if historical else room['inventory_count']
        comparison.append({'room_type_id': room_id, 'aggregate_inventory_count': count,
                           'physical_unit_count': represented[room_id], 'matches': count == represented[room_id],
                           'selling_inventory_count': room['inventory_count'], 'historical_stock': historical})
    return {'business_date':str(day),'physical_inventory_only':True,'allocation_supported':False,
            'capacity_basis':'regular_places_exclude_extra_beds',
            'availability_basis':'operational_only_not_reservation_availability',
            'aggregate_comparison':comparison,
            'counts':counts,'units':details}


def install(backend):
    router=APIRouter(prefix='/api/properties/{property_id}/physical-units')
    def authorize(con,session,prop,write=False):
        user=backend.require_user(session);backend.require_roles(user,*(['owner'] if write else ['owner','manager']))
        if not con.execute('SELECT id FROM properties WHERE id=? AND organization_id=?',(prop,user['organization_id'])).fetchone():
            raise HTTPException(404,'Property not found')
        if write:
            # Property lock serializes name uniqueness, effective versions and periods.
            con.execute('UPDATE properties SET id=id WHERE id=? AND organization_id=?',(prop,user['organization_id']))
        return user
    def unit_access(con,user,prop,uid):
        if not con.execute('SELECT id FROM physical_units WHERE id=? AND organization_id=? AND property_id=?',(uid,user['organization_id'],prop)).fetchone():
            raise HTTPException(404,'Physical unit not found')
    def audit(con,user,prop,uid,action,request):
        import business_days
        business_days.dirty_range(con,user['organization_id'],prop,'0001-01-01',user['id'],'Physical inventory source updated')
        backend.audit_event(con,user['organization_id'],'physical_unit.'+action,'Physical unit inventory updated.',actor_user_id=user['id'],entity_type='physical_unit',entity_id=uid,metadata={'property_id':prop},request=request)
    def save_version(con,user,prop,uid,body):
        if body.single_beds+2*body.double_beds<1:raise HTTPException(422,'Regular sleeping capacity must be positive')
        schema=contracts()['daily_close'][1]
        values=schema.xpath('./xs:simpleType[@name="LakoegysegTipusType"]//xs:enumeration/@value',namespaces={'xs':XSD})
        if body.classification not in values:raise HTTPException(422,'Invalid official unit classification')
        if not con.execute('SELECT id FROM room_types WHERE id=? AND organization_id=? AND property_id=? AND active=1',(body.room_type_id,user['organization_id'],prop)).fetchone():
            raise HTTPException(422,'Active room type must belong to this property')
        previous=con.execute('SELECT MAX(effective_from) d FROM physical_unit_versions WHERE unit_id=?',(uid,)).fetchone()['d']
        if previous and str(body.effective_from)<=previous:raise HTTPException(409,'New version must follow existing versions; historical versions cannot be overwritten')
        # Names are reserved across history: reusing one would obscure identity.
        if con.execute('''SELECT u.id FROM physical_units u JOIN physical_unit_versions v ON v.unit_id=u.id
          WHERE u.organization_id=? AND u.property_id=? AND u.id!=? AND v.building=? AND v.unit_number=? LIMIT 1''',
          (user['organization_id'],prop,uid,body.building,body.unit_number)).fetchone():raise HTTPException(409,'Building/unit identifier is already reserved')
        if not body.active and con.execute('''SELECT id FROM physical_unit_periods WHERE unit_id=? AND date_to>=?
          AND (cancelled_from IS NULL OR cancelled_from>?) LIMIT 1''',(uid,str(body.effective_from),str(body.effective_from))).fetchone():
            raise HTTPException(409,'End or cancel operational periods before deactivation')
        fields=body.model_dump();fields['effective_from']=str(body.effective_from);fields['active']=int(body.active)
        con.execute('''INSERT INTO physical_unit_versions(unit_id,effective_from,room_type_id,building,unit_number,classification,single_beds,double_beds,extra_beds,active,reason,recorded_at,recorded_by)
          VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)''',(uid,*[fields[k] for k in ('effective_from','room_type_id','building','unit_number','classification','single_beds','double_beds','extra_beds','active','reason')],backend.now_iso(),user['id']))

    @router.get('/capacity')
    def get_capacity(property_id:str,business_date:date,rosa_session:str|None=Cookie(default=None)):
        with backend.db() as con:
            user=authorize(con,rosa_session,property_id)
            org = user['organization_id']
            return {**capacity(con,org,property_id,business_date),
                    'historical_stock_editable': user['role']=='owner' and
                    reconciliation_date_allowed(backend,con,org,property_id,business_date)}

    @router.put('/historical-stock/{room_type_id}')
    def reconcile_stock(property_id: str, room_type_id: str, body: HistoricalStock, request: Request,
                        rosa_session: str | None = Cookie(default=None)):
        with backend.db() as con:
            user = authorize(con, rosa_session, property_id, True)
            org = user['organization_id']
            if not reconciliation_date_allowed(backend, con, org, property_id, body.business_date):
                raise HTTPException(422, 'Select a past business date to correct historical room stock')
            stock = next((row for row in capacity(con, org, property_id, body.business_date)['aggregate_comparison']
                          if row['room_type_id'] == room_type_id), None)
            if stock is None:
                raise HTTPException(404, 'Active room type not found in this property')
            if body.inventory_count != stock['physical_unit_count']:
                raise HTTPException(409, 'Enter the count of active physical units for this room type and date')
            previous = stock['historical_stock']
            if previous and previous['inventory_count'] == body.inventory_count:
                return {'ok': True, 'duplicate': True, 'revision': previous['revision']}
            revision = previous['revision'] + 1 if previous else 1
            day = str(body.business_date)
            con.execute('''INSERT INTO historical_room_stock
                (organization_id,property_id,room_type_id,business_date,revision,inventory_count,reason,recorded_at,recorded_by)
                VALUES (?,?,?,?,?,?,?,?,?)''', (org, property_id, room_type_id, day, revision,
                                               body.inventory_count, body.reason, backend.now_iso(), user['id']))
            import business_days
            business_days.mark_dirty(con, org, property_id, day, user['id'], body.reason)
            backend.audit_event(con, org, 'physical_unit.historical_stock_corrected',
                                'Historical room stock reconciled with physical inventory.', actor_user_id=user['id'],
                                entity_type='room_type', entity_id=room_type_id, request=request,
                                metadata={'property_id': property_id, 'business_date': day, 'revision': revision,
                                          'prior_count': stock['aggregate_inventory_count'], 'count': body.inventory_count})
            return {'ok': True, 'duplicate': False, 'revision': revision}

    @router.get('')
    def get_units(property_id:str,business_date:date,rosa_session:str|None=Cookie(default=None)):
        with backend.db() as con:
            user=authorize(con,rosa_session,property_id)
            return {'units':units_on(con,user['organization_id'],property_id,business_date)}

    @router.post('')
    def create(property_id:str,body:UnitDetails,request:Request,rosa_session:str|None=Cookie(default=None)):
        with backend.db() as con:
            user=authorize(con,rosa_session,property_id,True);uid=str(uuid.uuid4())
            con.execute('INSERT INTO physical_units(id,organization_id,property_id,created_at) VALUES (?,?,?,?)',(uid,user['organization_id'],property_id,backend.now_iso()))
            save_version(con,user,property_id,uid,body);audit(con,user,property_id,uid,'created',request)
            return {'id':uid}

    @router.put('/{unit_id}')
    def edit(property_id:str,unit_id:str,body:UnitDetails,request:Request,rosa_session:str|None=Cookie(default=None)):
        with backend.db() as con:
            user=authorize(con,rosa_session,property_id,True);unit_access(con,user,property_id,unit_id)
            save_version(con,user,property_id,unit_id,body)
            import reservation_allocations
            reservation_allocations.validate_unit_change(con,user["organization_id"],property_id,backend.now_iso())
            audit(con,user,property_id,unit_id,'version_created',request)
            return {'ok':True}

    @router.get('/{unit_id}/history')
    def history(property_id:str,unit_id:str,rosa_session:str|None=Cookie(default=None)):
        with backend.db() as con:
            user=authorize(con,rosa_session,property_id);unit_access(con,user,property_id,unit_id)
            return {'versions':[dict(x) for x in con.execute('SELECT * FROM physical_unit_versions WHERE unit_id=? ORDER BY effective_from',(unit_id,))],
                    'periods':[dict(x) for x in con.execute('SELECT * FROM physical_unit_periods WHERE unit_id=? ORDER BY date_from,id',(unit_id,))]}

    @router.post('/{unit_id}/periods')
    def period_create(property_id:str,unit_id:str,body:Period,request:Request,rosa_session:str|None=Cookie(default=None)):
        if body.state not in ('OOO','OOS') or body.date_to<body.date_from:raise HTTPException(422,'Invalid state or date interval')
        with backend.db() as con:
            user=authorize(con,rosa_session,property_id,True);unit_access(con,user,property_id,unit_id)
            versions=con.execute('SELECT * FROM physical_unit_versions WHERE unit_id=? ORDER BY effective_from',(unit_id,)).fetchall()
            start=[v for v in versions if v['effective_from']<=str(body.date_from)]
            if not start or not start[-1]['active'] or any(not v['active'] and str(body.date_from)<v['effective_from']<=str(body.date_to) for v in versions):
                raise HTTPException(409,'Unit must be active throughout the period')
            if con.execute('''SELECT id FROM physical_unit_periods WHERE unit_id=? AND date_from<=? AND date_to>=?
              AND (cancelled_from IS NULL OR (cancelled_from>? AND cancelled_from>date_from)) LIMIT 1''',(unit_id,str(body.date_to),str(body.date_from),str(body.date_from))).fetchone():
                raise HTTPException(409,'Operational periods cannot overlap')
            pid=str(uuid.uuid4())
            con.execute('INSERT INTO physical_unit_periods(id,unit_id,state,date_from,date_to,reason,recorded_at,recorded_by) VALUES (?,?,?,?,?,?,?,?)',
                        (pid,unit_id,body.state,str(body.date_from),str(body.date_to),body.reason,backend.now_iso(),user['id']))
            import reservation_allocations
            reservation_allocations.validate_unit_change(con,user['organization_id'],property_id,backend.now_iso())
            audit(con,user,property_id,unit_id,'period_created',request);return {'id':pid}

    @router.post('/{unit_id}/periods/{period_id}/cancel')
    def period_cancel(property_id:str,unit_id:str,period_id:str,body:CancelPeriod,request:Request,rosa_session:str|None=Cookie(default=None)):
        with backend.db() as con:
            user=authorize(con,rosa_session,property_id,True);unit_access(con,user,property_id,unit_id)
            p=con.execute('SELECT * FROM physical_unit_periods WHERE unit_id=? AND id=?',(unit_id,period_id)).fetchone()
            if not p:raise HTTPException(404,'Operational period not found')
            if p['cancelled_from']:raise HTTPException(409,'Period already has a cancellation record')
            if not p['date_from']<=str(body.effective_from)<=p['date_to']:raise HTTPException(422,'Cancellation date must fall within the period')
            con.execute('UPDATE physical_unit_periods SET cancelled_from=?,cancelled_at=?,cancelled_by=?,cancellation_reason=? WHERE id=?',
                        (str(body.effective_from),backend.now_iso(),user['id'],body.reason,period_id))
            audit(con,user,property_id,unit_id,'period_cancelled',request);return {'ok':True}
    backend.app.include_router(router)
