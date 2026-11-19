"""Property operating calendar and immutable operational daily snapshots. Offline by default."""
import json
from datetime import date,datetime,time,timedelta,timezone
from decimal import Decimal
from zoneinfo import ZoneInfo
import hashlib
import uuid
from fastapi import Cookie,HTTPException
from pydantic import BaseModel,ConfigDict,Field
import financial_ledger as ledger
import guest_reporting
import physical_units
import guest_stays
import ntak_reporting
from ntak_protocol import ReportingBlocked
from ntak_countries import COUNTRIES

REASONS={'VENDEG_VAGY_IFA_JAVITAS','SZOBA_VAGY_FEROHELY_MOD','TERHELES_VAGY_KOLTES_JAV','SZAMLAMODOSITAS','TECH_HIBA_ADATJAVITAS','ELLENORZES_ELTERES_JAV','ELOZO_BEKULDES_NEM_TELJES','EGYEB'}


def mark_dirty(con,org,prop,day,actor,reason):
    # Imported lazily by normal source mutations, including pre-calendar legacy records.
    con.execute("UPDATE business_days SET dirty=1 WHERE organization_id=? AND property_id=? AND business_date=? AND state='closed'",(org,prop,str(day)))


def dirty_range(con,org,prop,first,actor,reason):
    con.execute("UPDATE business_days SET dirty=1 WHERE organization_id=? AND property_id=? AND business_date>=? AND state='closed'",(org,prop,str(first)))


def migrate(backend,con):
    con.executescript('''CREATE TABLE IF NOT EXISTS business_days (
      organization_id TEXT NOT NULL,property_id TEXT NOT NULL REFERENCES properties(id),business_date TEXT NOT NULL,
      operating INTEGER NOT NULL,state TEXT NOT NULL,revision INTEGER NOT NULL DEFAULT 0,dirty INTEGER NOT NULL DEFAULT 0,
      actor_id TEXT NOT NULL,reason TEXT NOT NULL,updated_at TEXT NOT NULL,
      PRIMARY KEY(organization_id,property_id,business_date));
    CREATE TABLE IF NOT EXISTS business_day_settings (
      property_id TEXT PRIMARY KEY REFERENCES properties(id),organization_id TEXT NOT NULL,start_date TEXT NOT NULL,
      timezone TEXT NOT NULL,automatic INTEGER NOT NULL DEFAULT 0,closing_hour INTEGER NOT NULL,
      actor_id TEXT NOT NULL,reason TEXT NOT NULL,updated_at TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS business_day_history (
      id TEXT PRIMARY KEY,organization_id TEXT NOT NULL,property_id TEXT NOT NULL,business_date TEXT NOT NULL,
      action TEXT NOT NULL,actor_id TEXT NOT NULL,reason TEXT NOT NULL,created_at TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS daily_snapshots (
      id TEXT PRIMARY KEY,organization_id TEXT NOT NULL,property_id TEXT NOT NULL,business_date TEXT NOT NULL,
      revision INTEGER NOT NULL,encrypted_facts TEXT NOT NULL,fingerprint TEXT NOT NULL,
      classification TEXT NOT NULL,correction_reason TEXT,protocol_id TEXT,job_id TEXT,blocker TEXT,
      source TEXT NOT NULL,actor_id TEXT NOT NULL,reason TEXT NOT NULL,created_at TEXT NOT NULL,
      UNIQUE(organization_id,property_id,business_date,revision));
    CREATE TABLE IF NOT EXISTS property_ifa_rates (
      id TEXT PRIMARY KEY,organization_id TEXT NOT NULL,property_id TEXT NOT NULL,effective_from TEXT NOT NULL,
      tax_type TEXT NOT NULL,rate TEXT NOT NULL,actor_id TEXT NOT NULL,reason TEXT NOT NULL,created_at TEXT NOT NULL,
      UNIQUE(property_id,effective_from));
    ''')
    con.execute('INSERT OR IGNORE INTO schema_migrations(version,name,applied_at) VALUES (?,?,?)',(3082,'operating_calendar_and_daily_snapshots',backend.now_iso()))
    con.executescript('''CREATE TABLE IF NOT EXISTS property_ifa_rate_corrections (
      id TEXT PRIMARY KEY,original_id TEXT NOT NULL REFERENCES property_ifa_rates(id),revision INTEGER NOT NULL,
      tax_type TEXT NOT NULL,rate TEXT NOT NULL,actor_id TEXT NOT NULL,reason TEXT NOT NULL,created_at TEXT NOT NULL,
      UNIQUE(original_id,revision));''')
    con.execute('INSERT OR IGNORE INTO schema_migrations(version,name,applied_at) VALUES (?,?,?)',(3083,'historical_ifa_rate_corrections',backend.now_iso()))
    backend.add_column_if_missing(con,'daily_snapshots','recovery_checked_at','TEXT')


class CalendarSettings(BaseModel):
    model_config=ConfigDict(extra='forbid',str_strip_whitespace=True)
    start_date:date
    timezone:str='Europe/Budapest'
    automatic:bool=False
    closing_hour:int=Field(default=10,ge=0,le=23)
    reason:str=Field(min_length=3,max_length=500)


class DayState(BaseModel):
    model_config=ConfigDict(extra='forbid',str_strip_whitespace=True)
    operating:bool
    reason:str=Field(min_length=3,max_length=500)


class Close(BaseModel):
    model_config=ConfigDict(extra='forbid',str_strip_whitespace=True)
    reason:str=Field(min_length=3,max_length=500)
    correction_reason:str|None=None


class TaxRate(BaseModel):
    model_config=ConfigDict(extra='forbid',str_strip_whitespace=True)
    effective_from:date
    tax_type:str
    rate:str
    reason:str=Field(min_length=3,max_length=500)


def scope(con,org,prop):
    if not con.execute('SELECT id FROM properties WHERE id=? AND organization_id=?',(prop,org)).fetchone():raise HTTPException(404,'Property not found')
    con.execute('UPDATE properties SET id=id WHERE id=? AND organization_id=?',(prop,org))


def history(backend,con,org,prop,day,action,actor,reason):
    con.execute('INSERT INTO business_day_history VALUES (?,?,?,?,?,?,?,?)',(str(uuid.uuid4()),org,prop,str(day),action,actor,reason,backend.now_iso()))


def settings(con,org,prop):
    r=con.execute('SELECT * FROM business_day_settings WHERE property_id=? AND organization_id=?',(prop,org)).fetchone()
    return dict(r) if r else None


def collect(backend,con,org,prop,day):
    """Derive one local calendar night's facts. Planned stays never create occupancy."""
    cfg=settings(con,org,prop);blocks=[]
    tz=ZoneInfo(cfg['timezone'] if cfg else 'Europe/Budapest')
    if not cfg:blocks.append('operating_calendar_not_configured')
    d=str(day);end=datetime.combine(day+timedelta(days=1),time.min,tzinfo=tz)
    state=con.execute('SELECT * FROM business_days WHERE organization_id=? AND property_id=? AND business_date=?',(org,prop,d)).fetchone()
    if not state:blocks.append('operating_day_not_confirmed')
    operating=bool(state['operating']) if state else True
    capacity=physical_units.capacity(con,org,prop,day)
    if not capacity['units']:blocks.append('physical_inventory_missing')
    if any(not c['matches'] for c in capacity['aggregate_comparison']):blocks.append('physical_inventory_reconciliation_required')
    units={u['id']:u for u in capacity['units']};groups={};departure_groups={};guest_sources={}
    # Projection is made solely from audited actual events, including their corrections.
    rows=con.execute('''SELECT o.*,r.stay_type,r.ntak_booking_id,r.status FROM guest_occupancy o JOIN reservations r ON r.id=o.reservation_id
      WHERE r.organization_id=? AND r.property_id=? AND o.voided=0 ORDER BY o.started_at,o.id''',(org,prop)).fetchall()
    for row in rows:
        start=datetime.fromisoformat(row['started_at']).astimezone(tz)
        finish=datetime.fromisoformat(row['ended_at']).astimezone(tz) if row['ended_at'] else None
        night=start<end and (finish is None or finish>=end)
        day_use=row['stay_type']=='day_use' and start.date()==day and finish is not None and finish.date()==day
        checkout=finish is not None and finish.date()==day
        if not (night or day_use or checkout):continue
        if row['unit_id'] not in units:blocks.append('historical_unit_missing');continue
        key=(row['reservation_id'],row['unit_id'],day_use)
        if night or day_use:groups.setdefault(key,set()).add(row['guest_id'])
        if checkout:departure_groups.setdefault((row['reservation_id'],row['unit_id']),set()).add(row['guest_id'])
        if units[row['unit_id']]['operational_state']!='available':blocks.append('actual_occupancy_maintenance_conflict')
        profile,revision=guest_reporting.profile_on(backend,con,row['guest_id'],day)
        g=con.execute('SELECT nationality FROM guest_records WHERE id=?',(row['guest_id'],)).fetchone()
        frozen=con.execute('SELECT reporting_id FROM ntak_guest_ids WHERE guest_record_id=? AND property_id=? AND organization_id=?',(row['guest_id'],prop,org)).fetchone()
        guest_sources[row['guest_id']]={'profile':profile,'profile_revision':revision['id'] if revision else None,'nationality':g['nationality'],'reporting_id':frozen['reporting_id'] if frozen else None}
        if not profile:blocks.append('missing_guest_reporting_profile')
    sold={uid for rid,uid,du in groups if not du}
    nights=sum(len(gids) for (rid,uid,du),gids in groups.items() if not du)
    # A transfer must not count the same guest/unit twice at the night boundary.
    night_guests=[gid for (_,_,du),gids in groups.items() if not du for gid in gids]
    if len(night_guests)!=len(set(night_guests)):blocks.append('duplicate_actual_guest_night')
    for uid in sold:
        parties={rid for rid,unit,du in groups if unit==uid and not du}
        if len(parties)>1:blocks.append('contradictory_actual_unit_occupancy')
    entries=ledger.active(con,org,prop,day=day)
    involved={rid for rid,uid,du in groups}|{rid for rid,uid in departure_groups}
    for r in con.execute("SELECT id FROM reservations WHERE organization_id=? AND property_id=? AND status='confirmed' AND arrival_date<=? AND departure_date>?",(org,prop,d,d)):
        if r['id'] not in involved:blocks.append('planned_stay_requires_actual_review')
    for rid in involved:
        if not ledger.managed(con,rid):blocks.append('reservation_folio_not_itemized')
    rate=con.execute('SELECT * FROM property_ifa_rates WHERE organization_id=? AND property_id=? AND effective_from<=? ORDER BY effective_from DESC LIMIT 1',(org,prop,d)).fetchone()
    if rate:
        rate=dict(rate)
        fix=con.execute('SELECT * FROM property_ifa_rate_corrections WHERE original_id=? ORDER BY revision DESC LIMIT 1',(rate['id'],)).fetchone()
        if fix:rate.update(tax_type=fix['tax_type'],rate=fix['rate'],correction_id=fix['id'])
    if operating and not rate:blocks.append('effective_ifa_rate_missing')
    if not operating and (groups or entries or departure_groups):blocks.append('closed_property_has_activity')
    counts=capacity['counts'];beds_sold=sum(units[u]['regular_places'] for u in sold)
    snapshot={'business_date':d,'timezone':str(tz),'operating':operating,'capacity':capacity,'guest_nights':nights,'sold_units':len(sold),'sold_regular_places':beds_sold,
      'groups':[{'reservation_id':rid,'unit_id':uid,'day_use':du,'guest_ids':sorted(gids)} for (rid,uid,du),gids in sorted(groups.items())],
      'departures':[{'reservation_id':rid,'unit_id':uid,'guest_ids':sorted(gids)} for (rid,uid),gids in sorted(departure_groups.items())],
      'guests':guest_sources,'entries':entries,'totals':ledger.totals(entries),'ifa_rate':dict(rate) if rate else None,'reservations':{},'blockers':sorted(set(blocks))}
    for rid in involved|{e['reservation_id'] for e in entries if e['reservation_id']}:
        r=dict(con.execute('SELECT * FROM reservations WHERE id=? AND organization_id=?',(rid,org)).fetchone())
        facts=con.execute('SELECT facts_json FROM ntak_reservation_facts WHERE reservation_id=? AND organization_id=?',(rid,org)).fetchone()
        visits=[v for v in rows if v['reservation_id']==rid]
        latest=max((v['ended_at'] for v in visits if v['ended_at']),default=None)
        all_departed=bool(visits) and all(v['ended_at'] for v in visits)
        snapshot['reservations'][rid]={'booking_id':r['ntak_booking_id'] or rid,'facts':json.loads(facts['facts_json']) if facts else {},'post_stay':all_departed and datetime.fromisoformat(latest).astimezone(tz).date()<day,'departure_date':str(datetime.fromisoformat(latest).astimezone(tz).date()) if latest else None}
    taxable=sum(1 for (rid,uid,du),gids in groups.items() if not du for gid in gids if guest_sources[gid]['profile'] and guest_sources[gid]['profile']['ifa_status']=='KOTELES')
    snapshot['ifa_taxable_guest_nights']=taxable
    snapshot['ifa_exempt_guest_nights']=nights-taxable
    obligation=Decimal(0)
    if rate and rate['tax_type']=='TETELES':obligation=Decimal(rate['rate'])*taxable
    elif rate and rate['tax_type']=='SZAZALEKOS':
        for (rid,uid,du),gids in groups.items():
            if du:continue
            liable=sum(guest_sources[g]['profile'] is not None and guest_sources[g]['profile']['ifa_status']=='KOTELES' for g in gids)
            base=[e for e in entries if e['kind']=='charge' and e['category']=='SZALLASDIJ' and e['reservation_id']==rid and (e['unit_id']==uid or e['unit_id'] is None and sum(k[0]==rid for k in groups)==1)]
            if liable and not base:blocks.append('percentage_ifa_base_missing')
            net=sum((Decimal(e['total_huf'])/(1+Decimal(e['vat'])/100) for e in base),Decimal(0))
            obligation+=net*Decimal(rate['rate'])/100*Decimal(liable)/len(gids)
    snapshot['ifa_obligation_huf']=ledger.money(obligation)
    snapshot['blockers']=sorted(set(blocks))
    return snapshot


def guest_xml(con,org,prop,gid,source):
    p=source['profile']
    if not p:raise ReportingBlocked('missing_guest_reporting_profile')
    identity=source['reporting_id']
    if not identity:
        frozen=con.execute('SELECT reporting_id FROM ntak_guest_ids WHERE organization_id=? AND property_id=? AND guest_record_id=?',(org,prop,gid)).fetchone()
        if not frozen:raise ReportingBlocked('identity_normalization_unresolved')
        identity=frozen['reporting_id']
    country=source['nationality'] if source['nationality'] in COUNTRIES else p.get('nationality_country')
    if country not in COUNTRIES:raise ReportingBlocked('nationality_country_mapping_required')
    return {'vendegId':identity,'szuletesiEv':date.fromisoformat(p['date_of_birth']).year,'nem':p['sex'],'allampolgarsagOrszagKod':country,'lakohelyOrszagKod':p['country_of_residence'],'lakohelyIranyitoszam':p['postal_code'],'ifaStatusz':p['ifa_status']}


def financial_xml(entry):
    if entry['kind']=='payment':
        result={'osszeg':entry['total_huf'],'koltesTipus':entry['payment_method']}
        if entry['payment_subtype']:result['koltesAlTipus']=entry['payment_subtype']
    else:
        result={'osszeg':entry['total_huf'],'fokategoria':entry['category'],'afaKulcs':{'szazalek':int(entry['vat'])}}
        if entry['subcategory']:result['alkategoria']=entry['subcategory']
    return result


def payload(con,org,prop,facts,classification,protocol_id=None,reason=None,closed_at=None):
    counts=facts['capacity']['counts'];total=counts['total'];closed=not facts['operating']
    rooms={'osszesSzoba':total['units'],'oooSzobak':total['units'] if closed else counts['OOO']['units'],'oosSzobak':0 if closed else counts['OOS']['units'],'kiadottSzobak':0 if closed else facts['sold_units'],'kiadhatoSzobak':0 if closed else counts['available']['units']}
    beds={'osszesFerohelyKapacitas':total['regular_places'],'oooFerohelyKapacitas':total['regular_places'] if closed else counts['OOO']['regular_places'],'oosFerohelyKapacitas':0 if closed else counts['OOS']['regular_places'],'kiadottFerohelyKapacitas':0 if closed else facts['sold_regular_places'],'kiadhatoFerohelyKapacitas':0 if closed else counts['available']['regular_places']}
    cls={'besorolas':classification}
    if classification=='MODOSITO':cls.update(jegyzokonyvAzonosito=protocol_id,indoklas=reason)
    data={'lezartNap':facts['business_date'],'napiZarasBesorolas':cls,'lezarasIdopont':closed_at,'szallashelyNemUzemel':closed,'szobaAdatok':rooms,'ferohelyAdatok':beds}
    rate=facts['ifa_rate']
    if rate:data['ifaAdatok']={'ifaTipusa':rate['tax_type'],'ifaMertek':rate['rate']}
    units={u['id']:u for u in facts['capacity']['units']}
    unavailable=[guest_stays.unit_xml(u) for u in units.values() if closed or u['operational_state']!='available']
    if unavailable:data['uzemenKivuliSzobak']={'lakoegyseg':unavailable}
    targets={};night_rows=[];checkout=[]
    def sold(rid,uid):
        r=facts['reservations'][rid];f=r['facts']
        if not f.get('piaciSzegmens') or not f.get('ertekesitesiCsatorna'):raise ReportingBlocked('reservation_classification_missing')
        return {'lakoegyseg':guest_stays.unit_xml(units[uid]),'foglalasiSzam':r['booking_id'],'piaciSzegmens':f['piaciSzegmens'],'ertekesitesiCsatorna':f['ertekesitesiCsatorna']}
    for g in facts['groups']:
        s=sold(g['reservation_id'],g['unit_id']);targets[(g['reservation_id'],g['unit_id'])]=s
        night_rows.append({'ertekesitettLakoegyseg':s,'vendegek':{'vendeg':[guest_xml(con,org,prop,gid,facts['guests'][gid]) for gid in g['guest_ids']]},'nappaliHasznalat':g['day_use']})
    for g in facts['departures']:
        key=(g['reservation_id'],g['unit_id'])
        if key not in targets:
            s=sold(*key);targets[key]=s;checkout.append({'ertekesitettLakoegyseg':s})
    for e in facts['entries']:
        value=financial_xml(e);kind=e['kind'];rid=e['reservation_id']
        if kind=='payment' and e['direction']=='refund':raise ReportingBlocked('refund_requires_original_day_correction')
        if not rid:
            if kind=='charge' and e['category'] in ('IFA','SZALLASDIJ'):raise ReportingBlocked('charge_requires_booking_unit')
            group,member=('egyebTerhelesek','egyebTerheles') if kind=='charge' else ('egyebKoltesek','egyebKoltes')
            data.setdefault(group,{member:[]})[member].append(value);continue
        reservation=facts['reservations'][rid]
        if reservation['post_stay']:
            if kind=='charge' and e['category']=='IFA':raise ReportingBlocked('post_stay_ifa_requires_original_day_correction')
            if kind=='payment' and not e['document_date']:raise ReportingBlocked('post_stay_payment_document_date_missing')
            group,member=('tartozkodastKovetoTerhelesek','tartozkodastKovetoTerheles') if kind=='charge' else ('tartozkodastKovetoKoltesek','tartozkodastKovetoKoltes')
            data.setdefault(group,{member:[]})[member].append({'foglalasiSzam':reservation['booking_id'],'datum':reservation['departure_date'] if kind=='charge' else e['document_date'],'terheles' if kind=='charge' else 'koltes':value});continue
        candidates=[(key,s) for key,s in targets.items() if key[0]==rid and (not e['unit_id'] or key[1]==e['unit_id'])]
        if len(candidates)!=1:raise ReportingBlocked('financial_unit_assignment_required')
        target=candidates[0][1]
        if kind=='payment':target.setdefault('koltesek',{'koltes':[]})['koltes'].append(value)
        else:
            if e['category']=='EGYEB' and e['subcategory']=='EGYEB_VENDEGLATAS':raise ReportingBlocked('charge_category_not_allowed_for_accommodation')
            inside=bool(e['in_package']);group,member=('csomagbeliTerhelesek','csomagbeliTerheles') if inside else ('csomagonkivuliTerhelesek','csomagonkivuliTerheles')
            if e['category']=='SZALLASDIJ' and target in [c['ertekesitettLakoegyseg'] for c in checkout]:raise ReportingBlocked('accommodation_charge_requires_guest_night')
            target.setdefault('terhelesek',{}).setdefault(group,{member:[]})[member].append(value)
    if night_rows:data['lakoegysegEjszakak']={'lakoegysegEjszaka':night_rows}
    if checkout:data['kijelentkezesNapiErtekesitesek']=checkout
    return {'napiFeltoltes':data}


def classification(con,org,prop,day):
    # A synchronous receipt is never proof of acceptance. Search older successful
    # versions too: a rejected correction does not erase the accepted initial day.
    jobs=con.execute('''SELECT j.state,j.error_code,j.attempts FROM daily_snapshots s JOIN ntak_jobs j ON j.id=s.job_id
      WHERE s.organization_id=? AND s.property_id=? AND s.business_date=? ORDER BY s.revision DESC''',(org,prop,str(day))).fetchall()
    if any(j['state'] in ('accepted','sending','uncertain','retry','resend_required') for j in jobs):raise ReportingBlocked('prior_closing_outcome_pending')
    if any(j['state']=='succeeded' or j['state']=='review_required' and j['error_code'] is None for j in jobs):return 'MODOSITO'
    return 'UJ'


def capture(backend,con,snapshot):
    con.execute('UPDATE daily_snapshots SET recovery_checked_at=? WHERE id=?',(backend.now_iso(),snapshot['id']))
    org,prop=snapshot['organization_id'],snapshot['property_id'];cfg=ntak_reporting.configuration(con,org,prop)
    facts=backend.decrypt_json(snapshot['encrypted_facts']);blocked=None;content={'snapshot_id':snapshot['id']}
    previous=con.execute('SELECT * FROM ntak_jobs WHERE id=?',(snapshot['job_id'],)).fetchone() if snapshot['job_id'] else None
    if previous and previous['state'] not in ('blocked',):return previous['id']
    try:
        cls=classification(con,org,prop,snapshot['business_date'])
        if cls=='MODOSITO' and snapshot['correction_reason'] not in REASONS:raise ReportingBlocked('closing_correction_reason_required')
        content=payload(con,org,prop,facts,cls,snapshot['protocol_id'],snapshot['correction_reason'],snapshot['created_at'])
        if facts['blockers']:raise ReportingBlocked(facts['blockers'][0])
    except ReportingBlocked as exc:blocked=exc;cls='PENDING' if exc.code=='prior_closing_outcome_pending' else snapshot['classification']
    if not cfg or not cfg.get('enabled'):
        con.execute('UPDATE daily_snapshots SET blocker=? WHERE id=?',('reporting_not_enabled',snapshot['id']));return None
    if previous and blocked and previous['error_code']==blocked.code:return previous['id']
    # Supersede obsolete factual versions only when no transmission was attempted.
    # Retain every snapshot and job as evidence; do not transmit an old false version.
    for old in con.execute('''SELECT j.id FROM daily_snapshots s JOIN ntak_jobs j ON j.id=s.job_id
      WHERE s.organization_id=? AND s.property_id=? AND s.business_date=? AND s.revision<?
      AND j.attempts=0 AND j.state IN ('ready','blocked')''',(org,prop,snapshot['business_date'],snapshot['revision'])).fetchall():
        con.execute("UPDATE ntak_jobs SET state='superseded',error_code='replaced_by_source_correction' WHERE id=?",(old['id'],))
        con.execute("UPDATE government_outbox SET status='superseded' WHERE id=?",(old['id'],))
    logical='operational-daily:'+snapshot['id']+(':recovery:'+str(uuid.uuid4()) if previous else '')
    job=ntak_reporting.enqueue(con,org,prop,cfg,'daily_close',logical,content,blocked=blocked)
    if previous:
        con.execute("UPDATE ntak_jobs SET state='superseded',error_code='replaced_by_recovery' WHERE id=?",(previous['id'],))
        con.execute("UPDATE government_outbox SET status='superseded' WHERE id=?",(previous['id'],))
    con.execute('UPDATE daily_snapshots SET job_id=?,blocker=?,classification=? WHERE id=?',(job,blocked.code if blocked else None,cls,snapshot['id']))
    return job


def close(backend,con,org,prop,day,body,actor,source='owner_review'):
    scope(con,org,prop);cfg=settings(con,org,prop)
    if not cfg:raise HTTPException(409,{'code':'operating_calendar_not_configured'})
    today=backend.datetime.now(ZoneInfo(cfg['timezone'])).date()
    if day>=today or day<date.fromisoformat(cfg['start_date']):raise HTTPException(422,{'code':'invalid_closing_date'})
    # Chronological operational closing, independent of reporting start-date ambiguity.
    if day>date.fromisoformat(cfg['start_date']):
        previous=con.execute('SELECT state FROM business_days WHERE organization_id=? AND property_id=? AND business_date=?',(org,prop,str(day-timedelta(days=1)))).fetchone()
        if not previous or previous['state']!='closed':raise HTTPException(409,{'code':'previous_business_day_not_closed'})
    row=con.execute('SELECT * FROM business_days WHERE organization_id=? AND property_id=? AND business_date=?',(org,prop,str(day))).fetchone()
    if row and row['state']=='closed' and not row['dirty']:return {'duplicate':True,'revision':row['revision']}
    facts=collect(backend,con,org,prop,day)
    if facts['blockers']:raise HTTPException(409,{'code':'closing_not_ready','blockers':facts['blockers']})
    if row and row['state']=='closed' and body.correction_reason not in REASONS:raise HTTPException(422,{'code':'closing_correction_reason_required'})
    revision=(row['revision'] if row else 0)+1;sid=str(uuid.uuid4());now=backend.now_iso()
    try:cls=classification(con,org,prop,day)
    except ReportingBlocked:cls='PENDING'
    con.execute('INSERT INTO daily_snapshots(id,organization_id,property_id,business_date,revision,encrypted_facts,fingerprint,classification,correction_reason,protocol_id,source,actor_id,reason,created_at) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
      (sid,org,prop,str(day),revision,backend.encrypt_json(facts),hashlib.sha256(ntak_reporting.dump(facts).encode()).hexdigest(),cls,body.correction_reason,uuid.uuid4().hex[:25],source,actor,body.reason,now))
    con.execute("UPDATE business_days SET state='closed',revision=?,dirty=0,actor_id=?,reason=?,updated_at=? WHERE organization_id=? AND property_id=? AND business_date=?",(revision,actor,body.reason,now,org,prop,str(day)))
    history(backend,con,org,prop,day,'corrected' if revision>1 else 'closed',actor,body.reason)
    snapshot=dict(con.execute('SELECT * FROM daily_snapshots WHERE id=?',(sid,)).fetchone());job=capture(backend,con,snapshot)
    return {'id':sid,'revision':revision,'job_id':job,'duplicate':False}


def recover(backend,con,limit=20):
    rows=con.execute('''SELECT s.* FROM daily_snapshots s LEFT JOIN ntak_jobs j ON j.id=s.job_id
      WHERE (s.job_id IS NULL OR j.state='blocked') AND s.revision=(SELECT MAX(s2.revision) FROM daily_snapshots s2
        WHERE s2.property_id=s.property_id AND s2.business_date=s.business_date) ORDER BY COALESCE(s.recovery_checked_at,''),s.created_at LIMIT ?''',(limit,)).fetchall()
    for row in rows:capture(backend,con,dict(row))


def automatic(backend,con,limit=10):
    """Durable due dates derive from settings + closed rows; restart needs no timer state."""
    done=0
    for cfg in con.execute('SELECT * FROM business_day_settings WHERE automatic=1 ORDER BY property_id').fetchall():
        local=backend.datetime.now(ZoneInfo(cfg['timezone']))
        last=local.date()-timedelta(days=1 if local.hour>=cfg['closing_hour'] else 2)
        day=date.fromisoformat(cfg['start_date'])
        while day<=last and done<limit:
            row=con.execute('SELECT state,dirty FROM business_days WHERE organization_id=? AND property_id=? AND business_date=?',(cfg['organization_id'],cfg['property_id'],str(day))).fetchone()
            if row and row['state']=='closed':
                if row['dirty']:break  # Never auto-approve a historical correction.
                day+=timedelta(days=1);continue
            if not row:break  # An operator must explicitly confirm each day's operating state.
            try:close(backend,con,cfg['organization_id'],cfg['property_id'],day,Close(reason='Configured automatic closing'),cfg['actor_id'],'automatic')
            except HTTPException:break
            done+=1;day+=timedelta(days=1)
    return done


def install(backend):
    def authorize(con,session,prop):
        user=backend.require_user(session);backend.require_roles(user,'owner','manager');scope(con,user['organization_id'],prop);return user
    @backend.app.put('/api/properties/{property_id}/business-calendar')
    def configure(property_id:str,body:CalendarSettings,rosa_session:str|None=Cookie(default=None)):
        with backend.db() as con:
            u=authorize(con,rosa_session,property_id)
            try:ZoneInfo(body.timezone)
            except Exception:raise HTTPException(422,'Invalid timezone') from None
            old=settings(con,u['organization_id'],property_id)
            if not old:
                prior=con.execute('SELECT timezone FROM stay_events WHERE organization_id=? AND property_id=? LIMIT 1',(u['organization_id'],property_id)).fetchone()
                if prior and prior['timezone']!=body.timezone:raise HTTPException(409,'Preserve the timezone of existing actual events when initializing the closing calendar')
            if old and (old['start_date']!=str(body.start_date) or old['timezone']!=body.timezone) and con.execute('SELECT id FROM daily_snapshots WHERE property_id=? LIMIT 1',(property_id,)).fetchone():raise HTTPException(409,'Closing calendar boundaries are frozen after the first snapshot')
            con.execute('''INSERT INTO business_day_settings VALUES (?,?,?,?,?,?,?,?,?) ON CONFLICT(property_id) DO UPDATE SET
              start_date=excluded.start_date,timezone=excluded.timezone,automatic=excluded.automatic,closing_hour=excluded.closing_hour,actor_id=excluded.actor_id,reason=excluded.reason,updated_at=excluded.updated_at''',
              (property_id,u['organization_id'],str(body.start_date),body.timezone,int(body.automatic),body.closing_hour,u['id'],body.reason,backend.now_iso()))
            return {'ok':True}
    @backend.app.put('/api/properties/{property_id}/ifa-rates')
    def tax(property_id:str,body:TaxRate,rosa_session:str|None=Cookie(default=None)):
        with backend.db() as con:
            u=authorize(con,rosa_session,property_id);rate=ledger.dec(body.rate)
            if body.tax_type not in ledger.enum('IfaTipusaType') or body.tax_type=='NINCS' and rate!=0:raise HTTPException(422,'Invalid IFA rate')
            old=con.execute('SELECT * FROM property_ifa_rates WHERE property_id=? AND effective_from=?',(property_id,str(body.effective_from))).fetchone()
            if old:
                fix=con.execute('SELECT * FROM property_ifa_rate_corrections WHERE original_id=? ORDER BY revision DESC LIMIT 1',(old['id'],)).fetchone()
                latest=fix or old
                if latest['tax_type']==body.tax_type and Decimal(latest['rate'])==rate:return {'duplicate':True}
                con.execute('INSERT INTO property_ifa_rate_corrections VALUES (?,?,?,?,?,?,?,?)',(str(uuid.uuid4()),old['id'],fix['revision']+1 if fix else 1,body.tax_type,ledger.money(rate),u['id'],body.reason,backend.now_iso()))
                dirty_range(con,u['organization_id'],property_id,body.effective_from,u['id'],body.reason)
                return {'ok':True,'corrected':True}
            con.execute('INSERT INTO property_ifa_rates VALUES (?,?,?,?,?,?,?,?,?)',(str(uuid.uuid4()),u['organization_id'],property_id,str(body.effective_from),body.tax_type,ledger.money(rate),u['id'],body.reason,backend.now_iso()))
            dirty_range(con,u['organization_id'],property_id,body.effective_from,u['id'],body.reason);return {'ok':True}
    @backend.app.put('/api/properties/{property_id}/business-days/{business_date}')
    def calendar_day(property_id:str,business_date:date,body:DayState,rosa_session:str|None=Cookie(default=None)):
        with backend.db() as con:
            u=authorize(con,rosa_session,property_id)
            con.execute('''INSERT INTO business_days(organization_id,property_id,business_date,operating,state,actor_id,reason,updated_at) VALUES (?,?,?,?,'open',?,?,?)
              ON CONFLICT(organization_id,property_id,business_date) DO UPDATE SET operating=excluded.operating,dirty=CASE WHEN business_days.state='closed' THEN 1 ELSE 0 END,actor_id=excluded.actor_id,reason=excluded.reason,updated_at=excluded.updated_at''',
              (u['organization_id'],property_id,str(business_date),int(body.operating),u['id'],body.reason,backend.now_iso()))
            history(backend,con,u['organization_id'],property_id,business_date,'operating_state',u['id'],body.reason);return {'ok':True}
    @backend.app.get('/api/properties/{property_id}/business-days/{business_date}')
    def readiness(property_id:str,business_date:date,rosa_session:str|None=Cookie(default=None)):
        with backend.db() as con:
            u=authorize(con,rosa_session,property_id);facts=collect(backend,con,u['organization_id'],property_id,business_date)
            snaps=[dict(r) for r in con.execute('''SELECT s.id,s.business_date,s.revision,s.classification,s.correction_reason,s.protocol_id,s.job_id,s.blocker,s.created_at,j.state reporting_state,j.error_code
              FROM daily_snapshots s LEFT JOIN ntak_jobs j ON j.id=s.job_id WHERE s.organization_id=? AND s.property_id=? AND s.business_date=? ORDER BY revision''',(u['organization_id'],property_id,str(business_date)))]
            row=con.execute('SELECT * FROM business_days WHERE organization_id=? AND property_id=? AND business_date=?',(u['organization_id'],property_id,str(business_date))).fetchone()
            return {'settings':settings(con,u['organization_id'],property_id),'day':dict(row) if row else None,'business_date':str(business_date),'ready':not facts['blockers'],'blockers':facts['blockers'],'guest_nights':facts['guest_nights'],'sold_units':facts['sold_units'],'ifa_obligation_huf':facts['ifa_obligation_huf'],'ifa_taxable_guest_nights':facts['ifa_taxable_guest_nights'],'totals':facts['totals'],'snapshots':snaps,'correction_reasons':sorted(REASONS)}
    @backend.app.post('/api/properties/{property_id}/business-days/{business_date}/close')
    def close_day(property_id:str,business_date:date,body:Close,rosa_session:str|None=Cookie(default=None)):
        with backend.db() as con:
            u=authorize(con,rosa_session,property_id);return close(backend,con,u['organization_id'],property_id,business_date,body,u['id'])
    @backend.app.post('/api/properties/{property_id}/business-days/{business_date}/reporting-recovery')
    def recovery(property_id:str,business_date:date,rosa_session:str|None=Cookie(default=None)):
        with backend.db() as con:
            u=authorize(con,rosa_session,property_id)
            row=con.execute('SELECT * FROM daily_snapshots WHERE organization_id=? AND property_id=? AND business_date=? ORDER BY revision DESC LIMIT 1',(u['organization_id'],property_id,str(business_date))).fetchone()
            if not row:raise HTTPException(404,'Snapshot not found')
            return {'job_id':capture(backend,con,dict(row))}
