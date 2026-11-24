"""Source-aware actual occupancy. Planned bookings and registration never imply arrival."""
from datetime import datetime,date,timedelta,timezone
from zoneinfo import ZoneInfo
import hashlib
import json
import uuid
from fastapi import APIRouter,Cookie,HTTPException,Request
from pydantic import BaseModel,ConfigDict,Field
import guest_reporting
import physical_units
import reservation_allocations as allocations
import ntak_reporting
from ntak_protocol import ReportingBlocked
from ntak_contracts import ContractError


def migrate(con,now):
    con.executescript('''CREATE TABLE IF NOT EXISTS stay_events (
      id TEXT PRIMARY KEY,organization_id TEXT NOT NULL,property_id TEXT NOT NULL,
      reservation_id TEXT NOT NULL REFERENCES reservations(id),request_id TEXT NOT NULL,
      request_hash TEXT NOT NULL,kind TEXT NOT NULL,occurred_at TEXT NOT NULL,
      business_date TEXT NOT NULL,timezone TEXT NOT NULL,source TEXT NOT NULL,
      actor_id TEXT NOT NULL,reason TEXT NOT NULL,correction_of TEXT,
      encrypted_facts TEXT NOT NULL,reporting_exclusions_json TEXT NOT NULL DEFAULT '[]',reporting_job_id TEXT,reporting_blocker TEXT,recovery_checked_at TEXT,created_at TEXT NOT NULL,
      sequence INTEGER NOT NULL,UNIQUE(organization_id,request_id),UNIQUE(reservation_id,sequence));
    CREATE TABLE IF NOT EXISTS stay_event_guests (
      event_id TEXT NOT NULL REFERENCES stay_events(id),guest_id TEXT NOT NULL REFERENCES guest_records(id),
      PRIMARY KEY(event_id,guest_id));
    CREATE TABLE IF NOT EXISTS guest_occupancy (
      id TEXT PRIMARY KEY,reservation_id TEXT NOT NULL REFERENCES reservations(id),
      guest_id TEXT NOT NULL REFERENCES guest_records(id),unit_id TEXT NOT NULL REFERENCES physical_units(id),
      started_at TEXT NOT NULL,ended_at TEXT,arrival_event_id TEXT NOT NULL REFERENCES stay_events(id),
      departure_event_id TEXT,voided INTEGER NOT NULL DEFAULT 0);
    CREATE INDEX IF NOT EXISTS idx_actual_unit ON guest_occupancy(unit_id,started_at,ended_at);
    ''')
    con.execute('INSERT OR IGNORE INTO schema_migrations(version,name,applied_at) VALUES (?,?,?)',(3078,'actual_guest_stay_lifecycle',now))


class StayAction(BaseModel):
    model_config=ConfigDict(extra='forbid',str_strip_whitespace=True)
    request_id:uuid.UUID
    kind:str
    guest_ids:list[str]=Field(min_length=1,max_length=100)
    occurred_at:datetime
    unit_id:str|None=None
    reason:str=Field(min_length=3,max_length=500)
    correction_of:str|None=None
    corrected_at:datetime|None=None


def stamp(value):return value.astimezone(timezone.utc).isoformat()


def context(backend,con,org,rid):
    row=con.execute('SELECT * FROM reservations WHERE id=? AND organization_id=?',(rid,org)).fetchone()
    if not row:raise HTTPException(404,'Reservation not found')
    con.execute('UPDATE properties SET id=id WHERE id=? AND organization_id=?',(row['property_id'],org))
    backend._lock_reservation(con,rid,org)
    row=dict(con.execute('SELECT * FROM reservations WHERE id=?',(rid,)).fetchone())
    settings=con.execute('SELECT timezone FROM organization_settings WHERE organization_id=?',(org,)).fetchone()
    calendar=con.execute('SELECT timezone FROM business_day_settings WHERE property_id=? AND organization_id=?',(row['property_id'],org)).fetchone()
    return row,ZoneInfo(calendar['timezone'] if calendar else settings['timezone'] if settings else 'Europe/Budapest')


def unit_on(con,r,uid,day):
    found=next((u for u in physical_units.units_on(con,r['organization_id'],r['property_id'],day) if u['id']==uid),None)
    if not found or not found['active']:raise HTTPException(409,{'code':'stay_unit_unavailable'})
    if con.execute('''SELECT id FROM physical_unit_periods WHERE unit_id=? AND date_from<=? AND date_to>=?
      AND (cancelled_from IS NULL OR cancelled_from>?)''',(uid,str(day),str(day),str(day))).fetchone():raise HTTPException(409,{'code':'stay_unit_unavailable'})
    return found


def unit_xml(unit):
    return {'epulet':unit['building'],'szobaszam':unit['unit_number'],'tipus':unit['classification'],
            'egyfosAgySzam':unit['single_beds'],'ketfosAgySzam':unit['double_beds'],'potAgySzam':unit['extra_beds']}


def current(con,gid):
    return con.execute('SELECT * FROM guest_occupancy WHERE guest_id=? AND ended_at IS NULL AND voided=0',(gid,)).fetchone()


def collect_guests(backend,con,r,gids,day):
    result=[]
    for gid in gids:
        g=con.execute('SELECT * FROM guest_records WHERE id=? AND reservation_id=? AND organization_id=?',(gid,r['id'],r['organization_id'])).fetchone()
        if not g:raise HTTPException(404,'Guest record not found')
        profile,_=guest_reporting.profile_on(backend,con,gid,day)
        result.append({'guest_id':gid,'profile':profile,'nationality':g['nationality']})
    return result


def capture(backend,con,event):
    import viza_reporting
    viza_reporting.capture(backend,con,event)
    con.execute('UPDATE stay_events SET recovery_checked_at=? WHERE id=?',(ntak_reporting.stamp(),event['id']))
    if event.get('reporting_blocker') in ('superseded_before_submission','original_not_submitted_no_counter_needed'):return None
    if event['kind'] in ('undo_arrival','undo_departure','timestamp_counter') and event['correction_of']:
        original=con.execute('''SELECT e.id,e.reporting_job_id,j.state,j.attempts FROM stay_events e
          LEFT JOIN ntak_jobs j ON j.id=e.reporting_job_id WHERE e.id=?''',(event['correction_of'],)).fetchone()
        if original and (original['reporting_job_id'] is None or (original['state'] in ('ready','blocked') and original['attempts']==0)):
            original_event=dict(con.execute('SELECT * FROM stay_events WHERE id=?',(original['id'],)).fetchone())
            excluded=set(json.loads(original_event['reporting_exclusions_json']))
            excluded.update(g['guest_id'] for g in con.execute('SELECT guest_id FROM stay_event_guests WHERE event_id=?',(event['id'],)))
            members={g['guest_id'] for g in con.execute('SELECT guest_id FROM stay_event_guests WHERE event_id=?',(original['id'],))}
            if members-excluded:
                con.execute('UPDATE stay_events SET reporting_exclusions_json=?,reporting_blocker=NULL WHERE id=?',(json.dumps(sorted(excluded)),original['id']))
                if original['reporting_job_id']:
                    con.execute("UPDATE ntak_jobs SET state='blocked',error_code='partial_unsent_correction_requires_rebuild' WHERE id=?",(original['reporting_job_id'],))
                # Rebuild only the valid remainder; the immutable original facts
                # and the explicit per-guest correction remain in the audit chain.
                capture(backend,con,dict(con.execute('SELECT * FROM stay_events WHERE id=?',(original['id'],)).fetchone()))
                con.execute("UPDATE stay_events SET reporting_blocker='original_not_submitted_no_counter_needed' WHERE id=?",(event['id'],))
                return None
            if original['reporting_job_id']:
                con.execute("UPDATE ntak_jobs SET state='superseded_before_submission' WHERE id=?",(original['reporting_job_id'],))
                con.execute("UPDATE government_outbox SET status='superseded_before_submission' WHERE id=?",(original['reporting_job_id'],))
            con.execute("UPDATE stay_events SET reporting_blocker='superseded_before_submission' WHERE id=?",(original['id'],))
            con.execute("UPDATE stay_events SET reporting_blocker='original_not_submitted_no_counter_needed' WHERE id=?",(event['id'],))
            return None
    config=ntak_reporting.configuration(con,event['organization_id'],event['property_id'])
    if not config or not config.get('enabled'):
        con.execute("UPDATE stay_events SET reporting_blocker='reporting_not_enabled' WHERE id=?",(event['id'],))
        return None
    facts=backend.decrypt_json(event['encrypted_facts'])
    excluded=set(json.loads(event.get('reporting_exclusions_json') or '[]'))
    facts['guests']=[g for g in facts['guests'] if g['guest_id'] not in excluded]
    blocked=None
    try:
        guests=[]
        for g in facts['guests']:
            identity=guest_reporting.identity_for_submission(backend,con,event['organization_id'],event['property_id'],g['guest_id'])
            p=g['profile']
            if not p:p,_=guest_reporting.profile_on(backend,con,g['guest_id'],event['business_date'])
            if not p:raise ReportingBlocked('missing_guest_reporting_profile',['guest_profile'])
            from ntak_countries import COUNTRIES
            nationality=g['nationality'] if g['nationality'] in COUNTRIES else p.get('nationality_country')
            if nationality not in COUNTRIES:raise ReportingBlocked('nationality_country_mapping_required',['nationality'])
            guests.append({'vendegId':identity,'szuletesiEv':date.fromisoformat(p['date_of_birth']).year,
              'nem':p['sex'],'allampolgarsagOrszagKod':nationality,'lakohelyOrszagKod':p['country_of_residence'],
              'lakohelyIranyitoszam':p['postal_code'],'ifaStatusz':p['ifa_status']})
        data={'idopont':event['occurred_at'],'foglalasiSzam':facts['booking_id'],'vendegek':guests}
        if facts['report_kind']=='lakoegysegetCserelt':data.update(elhagyottLakoegyseg=facts['old_unit'],elfoglaltLakoegyseg=facts['unit'])
        else:data['lakoegyseg']=facts['unit']
        payload={'esemenyek':{facts['report_kind']:[data]}}
    except ReportingBlocked as exc:
        blocked=exc;payload={'stay_event_id':event['id'],'kind':event['kind'],'occurred_at':event['occurred_at']}
    key='actual-stay:'+event['id']
    if excluded:key+=':remainder:'+hashlib.sha256(json.dumps(sorted(excluded)).encode()).hexdigest()[:12]
    previous=con.execute('SELECT * FROM ntak_jobs WHERE id=?',(event['reporting_job_id'],)).fetchone() if event['reporting_job_id'] else None
    if previous:
        if previous['state']!='blocked' or blocked:return previous['id']
        key+=':resolved'
    job=ntak_reporting.enqueue(con,event['organization_id'],event['property_id'],config,'stay',key,payload,reservation_id=event['reservation_id'],blocked=blocked)
    con.execute('UPDATE stay_events SET reporting_job_id=?,reporting_blocker=NULL WHERE id=?',(job,event['id']))
    predecessor=con.execute('''SELECT e.reporting_job_id FROM stay_events e JOIN stay_event_guests g ON g.event_id=e.id
      WHERE e.reservation_id=? AND e.sequence<? AND e.reporting_job_id IS NOT NULL
      AND (e.reporting_blocker IS NULL OR e.reporting_blocker!='superseded_before_submission')
      AND g.guest_id IN (SELECT guest_id FROM stay_event_guests WHERE event_id=?) ORDER BY e.sequence DESC LIMIT 1''',(event['reservation_id'],event['sequence'],event['id'])).fetchone()
    if predecessor:con.execute('UPDATE ntak_jobs SET predecessor_job_id=? WHERE id=?',(predecessor['reporting_job_id'],job))
    for member in con.execute('SELECT guest_id FROM stay_event_guests WHERE event_id=?',(event['id'],)):
        prior=con.execute('''SELECT e.reporting_job_id FROM stay_events e JOIN stay_event_guests g ON g.event_id=e.id
          WHERE e.reservation_id=? AND g.guest_id=? AND e.sequence<? AND e.reporting_job_id IS NOT NULL
          AND (e.reporting_blocker IS NULL OR e.reporting_blocker!='superseded_before_submission') ORDER BY e.sequence DESC LIMIT 1''',(event['reservation_id'],member['guest_id'],event['sequence'])).fetchone()
        if prior:con.execute('INSERT OR IGNORE INTO ntak_job_predecessors(job_id,predecessor_job_id) VALUES (?,?)',(job,prior['reporting_job_id']))
    if previous:
        con.execute('UPDATE ntak_jobs SET predecessor_job_id=? WHERE predecessor_job_id=?',(job,previous['id']))
        for successor in con.execute('SELECT job_id FROM ntak_job_predecessors WHERE predecessor_job_id=?',(previous['id'],)).fetchall():
            con.execute('INSERT OR IGNORE INTO ntak_job_predecessors(job_id,predecessor_job_id) VALUES (?,?)',(successor['job_id'],job))
        con.execute('DELETE FROM ntak_job_predecessors WHERE predecessor_job_id=?',(previous['id'],))
    if previous:ntak_reporting.set_state(con,previous,'replaced_by_recovery',None,backend.datetime.now(timezone.utc))
    return job


def apply(backend,con,org,rid,action,actor,*,source='owner_review'):
    """Reusable trusted-service boundary. HTTP never accepts source/actor overrides."""
    if source not in ('owner_review','authorized_self_confirmation','verified_access_integration'):raise HTTPException(403,'Untrusted stay source')
    r,tz=context(backend,con,org,rid)
    if r['status']!='confirmed':raise HTTPException(409,{'code':'stay_booking_not_confirmed'})
    if action.occurred_at.tzinfo is None or action.occurred_at.utcoffset() is None:raise HTTPException(422,'An explicit timestamp offset is required')
    at=action.occurred_at.astimezone(timezone.utc)
    if at>backend.datetime.now(timezone.utc):raise HTTPException(422,'Actual events cannot be in the future')
    day=at.astimezone(tz).date()
    digest=hashlib.sha256(ntak_reporting.dump(action.model_dump(mode='json')).encode()).hexdigest()
    existing=con.execute('SELECT * FROM stay_events WHERE organization_id=? AND request_id=?',(org,str(action.request_id))).fetchone()
    if existing:
        if existing['request_hash']!=digest or existing['reservation_id']!=rid:raise HTTPException(409,'Stay action identifier was reused for another action')
        return {'ok':True,'id':existing['id'],'duplicate':True}
    gids=sorted(set(action.guest_ids))
    if len(gids)!=len(action.guest_ids):raise HTTPException(422,'Guest selection contains duplicates')
    if action.kind in ('undo_arrival','undo_departure','transfer','correct_timestamp'):
        return extended(backend,con,r,tz,action,actor,source,at,day,digest,gids)
    if action.kind not in ('arrive','depart'):raise HTTPException(422,'Unsupported stay action')
    guests=collect_guests(backend,con,r,gids,day)
    occupied=[current(con,g) for g in gids]
    if action.kind=='arrive':
        if any(occupied):raise HTTPException(409,{'code':'guest_already_arrived'})
        possible=[a for a in allocations.active(con,rid) if (a['date_from']<=str(day)<a['date_to'] or a['date_from']==a['date_to']==str(day))]
        uid=action.unit_id
        if uid is None and len({a['unit_id'] for a in possible})==1:uid=possible[0]['unit_id']
        if not uid or not any(a['unit_id']==uid for a in possible):raise HTTPException(409,{'code':'stay_allocation_required'})
        if r['stay_type']=='day_use':
            import day_use
            lo,hi=day_use.window(con,r)
            if not lo<=at<hi:raise HTTPException(409,'Arrival must be within the planned day-use window')
        unit=unit_on(con,r,uid,day)
        others=con.execute('SELECT * FROM guest_occupancy WHERE unit_id=? AND voided=0 AND (ended_at IS NULL OR ended_at>?)',(uid,stamp(at))).fetchall()
        if any(o['reservation_id']!=rid for o in others):raise HTTPException(409,{'code':'actual_occupancy_conflict'})
        if len(others)+len(gids)>unit['single_beds']+2*unit['double_beds']+unit['extra_beds']:raise HTTPException(409,{'code':'actual_capacity_exceeded'})
    else:
        if any(o is None for o in occupied):raise HTTPException(409,{'code':'guest_not_arrived'})
        if len({o['unit_id'] for o in occupied})!=1:raise HTTPException(409,{'code':'stay_group_unit_context'})
        uid=occupied[0]['unit_id']
        # Departure is permitted from a unit later taken out of service.
        unit=next(u for u in physical_units.units_on(con,org,r['property_id'],day) if u['id']==uid)
    for gid in gids:
        last=con.execute('''SELECT e.occurred_at FROM stay_events e JOIN stay_event_guests g ON g.event_id=e.id
          WHERE g.guest_id=? ORDER BY e.sequence DESC LIMIT 1''',(gid,)).fetchone()
        if last and at<datetime.fromisoformat(last['occurred_at']):raise HTTPException(409,'Stay chronology cannot move backwards')
    eid=str(uuid.uuid4());seq=con.execute('SELECT COALESCE(MAX(sequence),0)+1 n FROM stay_events WHERE reservation_id=?',(rid,)).fetchone()['n']
    facts={'booking_id':r['ntak_booking_id'] or rid,'guests':guests,'unit':unit_xml(unit),'report_kind':'erkezett' if action.kind=='arrive' else 'tavozott'}
    con.execute('''INSERT INTO stay_events(id,organization_id,property_id,reservation_id,request_id,request_hash,kind,occurred_at,business_date,timezone,source,actor_id,reason,correction_of,encrypted_facts,created_at,sequence)
      VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)''',(eid,org,r['property_id'],rid,str(action.request_id),digest,action.kind,stamp(at),str(day),str(tz),source,actor,action.reason,None,backend.encrypt_json(facts),backend.now_iso(),seq))
    for gid in gids:
        con.execute('INSERT INTO stay_event_guests(event_id,guest_id) VALUES (?,?)',(eid,gid))
        if action.kind=='arrive':con.execute('INSERT INTO guest_occupancy(id,reservation_id,guest_id,unit_id,started_at,arrival_event_id) VALUES (?,?,?,?,?,?)',(str(uuid.uuid4()),rid,gid,uid,stamp(at),eid))
        else:con.execute('UPDATE guest_occupancy SET ended_at=?,departure_event_id=? WHERE guest_id=? AND ended_at IS NULL AND voided=0',(stamp(at),eid,gid))
    event=dict(con.execute('SELECT * FROM stay_events WHERE id=?',(eid,)).fetchone());job=capture(backend,con,event)
    if r['stay_type']=='overnight':
        backend._refresh_overnight_cleaning(con, org, r['property_id'])
    elif action.kind=='depart':
        import day_use
        day_use.refresh_cleaning(backend,con,org)
    import business_days
    business_days.dirty_range(con,org,r['property_id'],r['arrival_date'],actor,action.reason)
    backend.audit_event(con,org,'guest.actual_'+action.kind,'Actual stay operation recorded.',actor_user_id=actor,entity_type='reservation',entity_id=rid,metadata={'event_id':eid,'source':source,'guest_count':len(gids),'unit_id':uid})
    return {'ok':True,'id':eid,'reporting_job_id':job,'duplicate':False}


def save_extended_event(backend,con,r,tz,action,actor,source,at,kind,facts,digest,correction=None,request_id=None):
    eid=str(uuid.uuid4());seq=con.execute('SELECT COALESCE(MAX(sequence),0)+1 n FROM stay_events WHERE reservation_id=?',(r['id'],)).fetchone()['n']
    con.execute('''INSERT INTO stay_events(id,organization_id,property_id,reservation_id,request_id,request_hash,kind,occurred_at,business_date,timezone,source,actor_id,reason,correction_of,encrypted_facts,created_at,sequence)
       VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)''',(eid,r['organization_id'],r['property_id'],r['id'],str(request_id or action.request_id),digest,kind,stamp(at),str(at.astimezone(tz).date()),str(tz),source,actor,action.reason,correction,backend.encrypt_json(facts),backend.now_iso(),seq))
    for gid in action.guest_ids:con.execute('INSERT INTO stay_event_guests(event_id,guest_id) VALUES (?,?)',(eid,gid))
    event=dict(con.execute('SELECT * FROM stay_events WHERE id=?',(eid,)).fetchone());capture(backend,con,event)
    import business_days
    business_days.dirty_range(con,r['organization_id'],r['property_id'],r['arrival_date'],actor,action.reason)
    backend.audit_event(con,r['organization_id'],'guest.actual_'+kind,'Actual stay correction or transfer recorded.',actor_user_id=actor,entity_type='reservation',entity_id=r['id'],metadata={'event_id':eid,'correction_of':correction,'source':source})
    return eid


def check_destination(con,r,unit,gids,at):
    other=con.execute('SELECT * FROM guest_occupancy WHERE unit_id=? AND voided=0 AND (ended_at IS NULL OR ended_at>?)',(unit['id'],stamp(at))).fetchall()
    other=[o for o in other if o['guest_id'] not in gids]
    if any(o['reservation_id']!=r['id'] for o in other):raise HTTPException(409,{'code':'actual_occupancy_conflict'})
    if len(other)+len(gids)>unit['single_beds']+2*unit['double_beds']+unit['extra_beds']:raise HTTPException(409,{'code':'actual_capacity_exceeded'})


def extended(backend,con,r,tz,action,actor,source,at,day,digest,gids):
    target=None
    if action.kind!='transfer':
        target=con.execute('SELECT * FROM stay_events WHERE id=? AND reservation_id=?',(action.correction_of,r['id'])).fetchone()
        if not target:raise HTTPException(404,'Original stay event not found')
        for gid in gids:
            last=con.execute('''SELECT e.* FROM stay_events e JOIN stay_event_guests g ON g.event_id=e.id
               WHERE g.guest_id=? ORDER BY e.sequence DESC LIMIT 1''',(gid,)).fetchone()
            if not last or last['id']!=target['id']:raise HTTPException(409,'Only the latest affected guest event can be corrected')
        if at<datetime.fromisoformat(target['occurred_at']):raise HTTPException(409,'Correction cannot precede the original event')
    visits=[current(con,gid) for gid in gids]
    if action.kind=='transfer':
        if any(v is None for v in visits) or len({v['unit_id'] for v in visits})!=1:raise HTTPException(409,{'code':'stay_group_unit_context'})
        origin=visits[0]['unit_id']
        if not action.unit_id or action.unit_id==origin:raise HTTPException(422,'Select a different destination unit')
        for v in visits:
            if at<datetime.fromisoformat(v['started_at']):raise HTTPException(409,'Transfer cannot precede occupancy')
        unit=unit_on(con,r,action.unit_id,day);check_destination(con,r,unit,gids,at)
        old_unit=next(u for u in physical_units.units_on(con,r['organization_id'],r['property_id'],day) if u['id']==origin)
        rows=allocations.active(con,r['id'])
        if not any(a['unit_id']==origin and (a['date_from']<=str(day)<a['date_to'] or a['date_from']==a['date_to']==str(day)) for a in rows):raise HTTPException(409,'Origin requires a current planned allocation')
        all_present=[v['guest_id'] for v in con.execute('SELECT guest_id FROM guest_occupancy WHERE unit_id=? AND ended_at IS NULL AND voided=0',(origin,))]
        moving_all=set(all_present)==set(gids)
        planned=[]
        for a in rows:
            if moving_all and a['unit_id']==origin and (a['date_from']<=str(day)<a['date_to'] or a['date_from']==a['date_to']==str(day)):
                if a['date_from']<str(day):planned.append({**a,'date_to':str(day)})
            else:planned.append(dict(a))
        if not any(a['unit_id']==action.unit_id and (a['date_from']<=str(day)<a['date_to'] or a['date_from']==a['date_to']==str(day)) for a in planned):
            planned.append({'unit_id':action.unit_id,'date_from':str(day),'date_to':r['departure_date']})
        allocations.replace(con,r,planned,actor,'Actual room transfer: '+action.reason,backend.now_iso())
        facts={'booking_id':r['ntak_booking_id'] or r['id'],'guests':collect_guests(backend,con,r,gids,day),'old_unit':unit_xml(old_unit),'unit':unit_xml(unit),'report_kind':'lakoegysegetCserelt'}
        eid=save_extended_event(backend,con,r,tz,action,actor,source,at,'transfer',facts,digest)
        for v in visits:
            con.execute('UPDATE guest_occupancy SET ended_at=?,departure_event_id=? WHERE id=?',(stamp(at),eid,v['id']))
            con.execute('INSERT INTO guest_occupancy(id,reservation_id,guest_id,unit_id,started_at,arrival_event_id) VALUES (?,?,?,?,?,?)',(str(uuid.uuid4()),r['id'],v['guest_id'],unit['id'],stamp(at),eid))
        for rt in {a['room_type_id'] for a in rows}|{unit['room_type_id']}:
            backend._queue_reservation_availability(con,r['organization_id'],r['property_id'],r['arrival_date'],r['departure_date'],reason='Actual room transfer planned demand',force=True,room_type_id=rt)
        ntak_reporting.capture_reservation(con,r['organization_id'],r['id'])
        if r['stay_type']=='day_use':
            import day_use
            day_use.refresh_cleaning(backend,con,r['organization_id'])
    else:
        expected='arrive' if action.kind=='undo_arrival' else 'depart' if action.kind=='undo_departure' else target['kind']
        if target['kind'] not in ('arrive','depart') or target['kind']!=expected:raise HTTPException(409,'This event cannot be corrected by the selected operation')
        facts=backend.decrypt_json(target['encrypted_facts']);facts['guests']=[g for g in facts['guests'] if g['guest_id'] in gids]
        original_guests={g['guest_id'] for g in facts['guests']}
        if original_guests!=set(gids):raise HTTPException(409,'Correction guests do not match the original event')
        records=[con.execute('SELECT * FROM guest_occupancy WHERE '+('arrival_event_id' if target['kind']=='arrive' else 'departure_event_id')+'=? AND guest_id=? AND voided=0',(target['id'],gid)).fetchone() for gid in gids]
        if any(v is None for v in records):raise HTTPException(409,'Original occupancy is no longer reversible')
        if target['kind']=='arrive' and any(v['ended_at'] is not None for v in records):raise HTTPException(409,'Reverse later departures first')
        if target['kind']=='depart':
            for v in records:
                unit=unit_on(con,r,v['unit_id'],day);check_destination(con,r,unit,gids,datetime.fromisoformat(v['ended_at']))
        facts['report_kind']='tavozott' if target['kind']=='arrive' else 'erkezett'
        if action.kind=='correct_timestamp':
            corrected=action.corrected_at
            if corrected is None or corrected.tzinfo is None or corrected>at:raise HTTPException(422,'Corrected timestamp must include an offset and not be in the future')
            # Latest-event only; never rewrite a previously chained occupancy.
            for v in records:
                previous_event=con.execute('''SELECT e.occurred_at FROM stay_events e JOIN stay_event_guests g ON g.event_id=e.id
                  WHERE g.guest_id=? AND e.sequence<? ORDER BY e.sequence DESC LIMIT 1''',(v['guest_id'],target['sequence'])).fetchone()
                if previous_event and corrected<datetime.fromisoformat(previous_event['occurred_at']):raise HTTPException(409,'Corrected timestamp would reorder earlier guest history')
                if target['kind']=='depart' and corrected<datetime.fromisoformat(v['started_at']):raise HTTPException(409,'Departure cannot precede arrival')
                if target['kind']=='arrive':
                    if not (r['arrival_date']<=str(corrected.astimezone(tz).date())<r['departure_date'] or r['stay_type']=='day_use' and str(corrected.astimezone(tz).date())==r['arrival_date']):raise HTTPException(409,'Corrected arrival must be within the booking')
                    unit=unit_on(con,r,v['unit_id'],corrected.astimezone(tz).date());check_destination(con,r,unit,gids,corrected)
            eid=save_extended_event(backend,con,r,tz,action,actor,source,datetime.fromisoformat(target['occurred_at']),'timestamp_counter',facts,digest,target['id'])
            replacement={**facts,'report_kind':'erkezett' if target['kind']=='arrive' else 'tavozott'}
            second=save_extended_event(backend,con,r,tz,action,actor,source,corrected,'timestamp_replacement',replacement,digest,target['id'],uuid.uuid5(action.request_id,'replacement'))
            for v in records:
                field='started_at' if target['kind']=='arrive' else 'ended_at'
                con.execute('UPDATE guest_occupancy SET '+field+'=? WHERE id=?',(stamp(corrected),v['id']))
        else:
            eid=save_extended_event(backend,con,r,tz,action,actor,source,at,action.kind,facts,digest,target['id'])
            for v in records:
                if action.kind=='undo_arrival':con.execute('UPDATE guest_occupancy SET voided=1,ended_at=?,departure_event_id=? WHERE id=?',(stamp(at),eid,v['id']))
                else:con.execute('UPDATE guest_occupancy SET ended_at=NULL,departure_event_id=NULL WHERE id=?',(v['id'],))
    if r['stay_type']=='overnight':
        backend._refresh_overnight_cleaning(con, r['organization_id'], r['property_id'])
    return {'ok':True,'id':eid,'duplicate':False}


def overview(con,org,rid):
    r=con.execute('SELECT * FROM reservations WHERE id=? AND organization_id=?',(rid,org)).fetchone()
    if not r:raise HTTPException(404,'Reservation not found')
    settings=con.execute('SELECT timezone FROM organization_settings WHERE organization_id=?',(org,)).fetchone()
    tz=ZoneInfo(settings['timezone'] if settings else 'Europe/Budapest')
    guests=[]
    for g in con.execute('SELECT g.id,g.full_name,g.completeness,v.status verification_status FROM guest_records g LEFT JOIN guest_identity_verifications v ON v.guest_record_id=g.id WHERE g.reservation_id=? ORDER BY g.id',(rid,)):
        present=current(con,g['id'])
        visits=[dict(v) for v in con.execute('SELECT * FROM guest_occupancy WHERE guest_id=? ORDER BY started_at,id',(g['id'],))]
        for v in visits:
            v['guest_nights']=max(0,(datetime.fromisoformat(v['ended_at']).astimezone(tz).date()-datetime.fromisoformat(v['started_at']).astimezone(tz).date()).days) if v['ended_at'] and not v['voided'] else None
        guests.append({**dict(g),'registration_state':'complete' if g['completeness']=='complete' and g['verification_status']=='verified' else 'needs_review' if g['completeness']=='complete' else 'incomplete','actual_state':'arrived' if present else 'departed' if any(not v['voided'] for v in visits) else 'expected','occupancy':dict(present) if present else None,'history':visits})
    events=[]
    for e in con.execute('''SELECT e.id,e.kind,e.occurred_at,e.business_date,e.timezone,e.source,e.actor_id,e.reason,e.correction_of,e.sequence,j.state reporting_state,COALESCE(j.error_code,e.reporting_blocker) error_code
       FROM stay_events e LEFT JOIN ntak_jobs j ON j.id=e.reporting_job_id WHERE e.reservation_id=? ORDER BY e.sequence''',(rid,)):
        events.append({**dict(e),'guest_ids':[g['guest_id'] for g in con.execute('SELECT guest_id FROM stay_event_guests WHERE event_id=?',(e['id'],))]})
    return {'stay_type':r['stay_type'],'day_use_overnight_mismatch':r['stay_type']=='day_use' and any((v['guest_nights'] or 0)>0 for g in guests for v in g['history']),'guests':guests,'events':events,'planned_allocations':allocations.active(con,rid),'actual_occupants':sum(g['actual_state']=='arrived' for g in guests)}


def recover_pending(backend,con,limit=20):
    rows=con.execute('''SELECT e.* FROM stay_events e LEFT JOIN ntak_jobs j ON j.id=e.reporting_job_id
      WHERE (e.reporting_job_id IS NULL OR j.state='blocked') AND (e.reporting_blocker IS NULL OR e.reporting_blocker NOT IN ('superseded_before_submission','original_not_submitted_no_counter_needed'))
      ORDER BY COALESCE(e.recovery_checked_at,''),e.sequence LIMIT ?''',(limit,)).fetchall()
    for row in rows:capture(backend,con,dict(row))


def install(backend):
    router=APIRouter(prefix='/api/reservations/{reservation_id}/actual-stay')
    @backend.app.get('/api/operations/actual-occupancy')
    def operational_summary(rosa_session:str|None=Cookie(default=None)):
        user=backend.require_user(rosa_session);backend.require_roles(user,'owner','manager')
        with backend.db() as con:
            s=con.execute('SELECT timezone FROM organization_settings WHERE organization_id=?',(user['organization_id'],)).fetchone()
            day=str(backend.datetime.now(ZoneInfo(s['timezone'] if s else 'Europe/Budapest')).date())
            rows=con.execute('''SELECT r.id,r.guest_name,p.name property_name,r.guest_count,r.stay_type
              FROM reservations r JOIN properties p ON p.id=r.property_id WHERE r.organization_id=? AND
              ((r.status='confirmed' AND r.arrival_date<=? AND r.departure_date>=?) OR EXISTS (
                SELECT 1 FROM guest_occupancy o WHERE o.reservation_id=r.id AND o.ended_at IS NULL AND o.voided=0)) ORDER BY p.name,r.id''',(user['organization_id'],day,day)).fetchall()
            return {'business_date':day,'reservations':[{**dict(r),'actual_occupants':con.execute('SELECT COUNT(*) n FROM guest_occupancy WHERE reservation_id=? AND ended_at IS NULL AND voided=0',(r['id'],)).fetchone()['n']} for r in rows]}
    @router.get('')
    def get(reservation_id:str,rosa_session:str|None=Cookie(default=None)):
        user=backend.require_user(rosa_session);backend.require_roles(user,'owner','manager')
        with backend.db() as con:
            import viza_reporting
            result=overview(con,user['organization_id'],reservation_id)
            result['viza_reporting']=viza_reporting.overview(con,user['organization_id'],reservation_id)
            return result
    @router.post('')
    def post(reservation_id:str,body:StayAction,request:Request,rosa_session:str|None=Cookie(default=None)):
        user=backend.require_user(rosa_session);backend.require_roles(user,'owner','manager')
        with backend.db() as con:return apply(backend,con,user['organization_id'],reservation_id,body,user['id'])
    @router.post('/reporting-recovery/{event_id}')
    def recover(reservation_id:str,event_id:str,rosa_session:str|None=Cookie(default=None)):
        user=backend.require_user(rosa_session);backend.require_roles(user,'owner','manager')
        with backend.db() as con:
            r,tz=context(backend,con,user['organization_id'],reservation_id)
            event=con.execute('SELECT * FROM stay_events WHERE id=? AND reservation_id=?',(event_id,reservation_id)).fetchone()
            if not event:raise HTTPException(404,'Stay event not found')
            result=capture(backend,con,dict(event))
            import viza_reporting
            jobs=viza_reporting.recover(backend,con,dict(event))
            return {'job_id':result,'viza_job_ids':jobs}
    backend.app.include_router(router)
