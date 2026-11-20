"""Transactional offline VIZA capture. No signing, network, retry worker or sender."""
from datetime import datetime
import json,uuid
import viza_identity


def migrate(con,now):
    first=not con.execute('SELECT 1 FROM schema_migrations WHERE version=3086').fetchone()
    con.executescript('''CREATE TABLE IF NOT EXISTS viza_captured_events(event_id TEXT PRIMARY KEY REFERENCES stay_events(id),origin TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS viza_visits (
      arrival_uuid TEXT PRIMARY KEY,organization_id TEXT NOT NULL,property_id TEXT NOT NULL,
      reservation_id TEXT NOT NULL,guest_record_id TEXT NOT NULL REFERENCES guest_records(id),
      arrival_event_id TEXT NOT NULL REFERENCES stay_events(id),departure_event_id TEXT,
      active INTEGER NOT NULL,retired INTEGER NOT NULL DEFAULT 0,created_at TEXT NOT NULL);
    CREATE UNIQUE INDEX IF NOT EXISTS idx_viza_active_visit ON viza_visits(guest_record_id) WHERE active=1;
    CREATE TABLE IF NOT EXISTS viza_jobs (
      id TEXT PRIMARY KEY REFERENCES government_outbox(id),event_id TEXT NOT NULL REFERENCES stay_events(id),
      batch_number INTEGER NOT NULL,revision INTEGER NOT NULL,organization_id TEXT NOT NULL,property_id TEXT NOT NULL,
      kind TEXT NOT NULL,encrypted_facts TEXT NOT NULL,blockers_json TEXT NOT NULL,state TEXT NOT NULL,
      attempts INTEGER NOT NULL DEFAULT 0,predecessor_id TEXT,created_at TEXT NOT NULL,
      UNIQUE(event_id,batch_number,revision));
    CREATE TABLE IF NOT EXISTS viza_visit_holds (arrival_uuid TEXT NOT NULL REFERENCES viza_visits(arrival_uuid),event_id TEXT NOT NULL REFERENCES stay_events(id),blocker TEXT NOT NULL,PRIMARY KEY(arrival_uuid,event_id));
    CREATE TABLE IF NOT EXISTS viza_job_guests (
      job_id TEXT NOT NULL REFERENCES viza_jobs(id),arrival_uuid TEXT NOT NULL REFERENCES viza_visits(arrival_uuid),
      PRIMARY KEY(job_id,arrival_uuid));
''')
    if first:con.execute("INSERT INTO viza_captured_events(event_id,origin) SELECT id,'legacy_excluded_no_inferred_uuid' FROM stay_events")
    if con.backend=='sqlite':
        con.raw.execute("CREATE TRIGGER IF NOT EXISTS viza_facts_immutable BEFORE UPDATE OF encrypted_facts,event_id ON viza_jobs BEGIN SELECT RAISE(ABORT,'VIZA facts are immutable'); END")
    else:
        con.raw.execute("CREATE OR REPLACE FUNCTION viza_facts_no_update() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'VIZA facts are immutable'; END; $$")
        con.raw.execute('DROP TRIGGER IF EXISTS viza_facts_immutable ON viza_jobs')
        con.raw.execute('CREATE TRIGGER viza_facts_immutable BEFORE UPDATE OF encrypted_facts,event_id ON viza_jobs FOR EACH ROW EXECUTE FUNCTION viza_facts_no_update()')
    con.execute('INSERT OR IGNORE INTO schema_migrations(version,name,applied_at) VALUES (3086,?,?)',('viza_actual_visit_capture',now))


def queue(backend,con,event,kind,members,blockers=(),revision=1):
    result=[]
    for n,start in enumerate(range(0,len(members),10)):
        batch=members[start:start+10];jid=str(uuid.uuid4())
        errors=set(blockers)|{'Q2_outer_ws_security_unresolved','official_transmission_disabled','property_configuration_not_bound'}
        for m in batch:
            for hold in con.execute('SELECT blocker FROM viza_visit_holds WHERE arrival_uuid=?',(m.get('arrival_uuid'),)):errors.add(hold['blocker'])
        for m in batch:errors.update(m.get('blockers',[]))
        facts={'event_id':event['id'],'occurred_at':event['occurred_at'],'timezone':event['timezone'],'kind':kind,'guests':batch}
        # Generic outbox stores only routing identifiers; identity is encrypted once.
        con.execute('''INSERT INTO government_outbox(id,organization_id,property_id,reservation_id,system,event_type,payload_json,status,attempts,created_at)
          VALUES (?,?,?,?,'VIZA',?,?,'viza_capture_blocked',0,?)''',(jid,event['organization_id'],event['property_id'],event['reservation_id'],
          'viza.actual_'+kind,json.dumps({'viza_job_id':jid,'event_id':event['id']}),backend.now_iso()))
        con.execute('INSERT INTO viza_jobs VALUES (?,?,?,?,?,?,?,?,?,?,0,NULL,?)',(jid,event['id'],n,revision,event['organization_id'],event['property_id'],kind,
          backend.encrypt_json(facts),json.dumps(sorted(errors)),'blocked',backend.now_iso()))
        for m in batch:
            if m['arrival_uuid'] is not None:con.execute('INSERT INTO viza_job_guests VALUES (?,?)',(jid,m['arrival_uuid']))
        if kind=='departure':
            predecessors=[r['job_id'] for m in batch for r in con.execute("SELECT g.job_id FROM viza_job_guests g JOIN viza_jobs j ON j.id=g.job_id WHERE g.arrival_uuid=? AND j.kind='arrival' AND j.state!='superseded_before_submission' ORDER BY j.revision DESC",(m['arrival_uuid'],))]
            if predecessors:con.execute('UPDATE viza_jobs SET predecessor_id=? WHERE id=?',(predecessors[0],jid))
        result.append(jid)
    return result


def visit(con,gid,*,active=False):
    return con.execute('SELECT v.* FROM viza_visits v JOIN stay_events e ON e.id=v.arrival_event_id WHERE v.guest_record_id=? '+('AND v.active=1 ' if active else '')+'ORDER BY e.sequence DESC LIMIT 1',(gid,)).fetchone()


def capture(backend,con,event):
    # Existing NTAK recovery may call capture again. Events and batches are idempotent.
    if con.execute('SELECT 1 FROM viza_captured_events WHERE event_id=?',(event['id'],)).fetchone():return
    con.execute("INSERT INTO viza_captured_events(event_id,origin) VALUES (?,'actual_stay_transaction')",(event['id'],))
    kind=event['kind']
    if kind=='transfer':return  # physical segments change; the logical visit does not
    gids=[r['guest_id'] for r in con.execute('SELECT guest_id FROM stay_event_guests WHERE event_id=? ORDER BY guest_id',(event['id'],))]
    if kind not in ('arrive','depart','undo_arrival','undo_departure','timestamp_counter','timestamp_replacement'):return
    members=[];blockers=[]
    r=con.execute('SELECT * FROM reservations WHERE id=?',(event['reservation_id'],)).fetchone()
    if kind in ('undo_departure','timestamp_counter','timestamp_replacement'):
        targets=con.execute('SELECT * FROM viza_jobs WHERE event_id=?',(event['correction_of'],)).fetchall()
        sent=any(j['attempts']>0 or j['state'] in ('accepted','uncertain','correction_blocked') for j in targets)
        for j in targets:
            if j['state']=='superseded_before_submission':continue
            source=backend.decrypt_json(j['encrypted_facts'])
            if not any(m['guest_id'] in set(gids) for m in source['guests']):continue
            remainder=[m for m in source['guests'] if m['guest_id'] not in set(gids)]
            if not sent:
                con.execute("UPDATE viza_jobs SET state='superseded_before_submission' WHERE id=?",(j['id'],))
                con.execute("UPDATE government_outbox SET status='superseded_before_submission' WHERE id=?",(j['id'],))
                if remainder:
                    revision=con.execute('SELECT MAX(revision)+1 n FROM viza_jobs WHERE event_id=?',(j['event_id'],)).fetchone()['n']
                    original_event=dict(con.execute('SELECT * FROM stay_events WHERE id=?',(j['event_id'],)).fetchone())
                    queue(backend,con,original_event,j['kind'],remainder,revision=revision)
        if kind=='timestamp_counter' and not sent:return
        target=con.execute('SELECT * FROM stay_events WHERE id=?',(event['correction_of'],)).fetchone()
        for gid in gids:
            v=visit(con,gid)
            if not v:continue
            if sent:con.execute('INSERT OR IGNORE INTO viza_visit_holds VALUES (?,?,?)',(v['arrival_uuid'],event['id'],'Q5_submitted_correction_unresolved'))
            if kind=='undo_departure':
                con.execute('UPDATE viza_visits SET active=1,departure_event_id=NULL WHERE arrival_uuid=? AND retired=0',(v['arrival_uuid'],))
                member={'guest_id':gid,'arrival_uuid':v['arrival_uuid'],'blockers':[]}
            elif target and target['kind']=='arrive':
                from zoneinfo import ZoneInfo
                day=datetime.fromisoformat(event['occurred_at']).astimezone(ZoneInfo(event['timezone'])).date()
                identity=viza_identity.readiness(backend,con,gid,day)
                member={'guest_id':gid,'arrival_uuid':v['arrival_uuid'],'identity':identity,'expected_departure':r['departure_date'],'blockers':identity['blockers']}
                if r['departure_date']<=str(day):member['blockers'].append('Q6_same_day_expected_departure_unresolved')
            else:member={'guest_id':gid,'arrival_uuid':v['arrival_uuid'],'blockers':[]}
            members.append(member)
        if members and (sent or kind=='timestamp_replacement'):
            report_kind='correction' if sent else 'arrival' if target['kind']=='arrive' else 'departure'
            queue(backend,con,event,report_kind,members,['Q5_submitted_correction_unresolved'] if sent else [])
        return
    unsent_voids=set()
    if kind=='undo_arrival':
        prior=con.execute("SELECT DISTINCT j.* FROM viza_jobs j JOIN viza_job_guests g ON g.job_id=j.id JOIN viza_visits v ON v.arrival_uuid=g.arrival_uuid WHERE v.arrival_event_id=? AND j.kind='arrival' AND j.state!='superseded_before_submission'",(event['correction_of'],)).fetchall()
        for old in prior:
            if old['attempts'] or old['state'] in ('accepted','uncertain'):continue
            source=backend.decrypt_json(old['encrypted_facts'])
            affected=[m for m in source['guests'] if m['guest_id'] in gids]
            if not affected:continue
            unsent_voids.update(m['guest_id'] for m in affected)
            remainder=[m for m in source['guests'] if m['guest_id'] not in gids]
            con.execute("UPDATE viza_jobs SET state='superseded_before_submission' WHERE id=?",(old['id'],))
            con.execute("UPDATE government_outbox SET status='superseded_before_submission' WHERE id=?",(old['id'],))
            if remainder:
                original_event=dict(con.execute('SELECT * FROM stay_events WHERE id=?',(old['event_id'],)).fetchone())
                revision=con.execute('SELECT MAX(revision)+1 n FROM viza_jobs WHERE event_id=?',(old['event_id'],)).fetchone()['n']
                queue(backend,con,original_event,'arrival',remainder,revision=revision)
    for gid in gids:
        if kind=='arrive':
            uid=str(uuid.uuid4())
            con.execute('INSERT INTO viza_visits VALUES (?,?,?,?,?,?,NULL,1,0,?)',(uid,event['organization_id'],event['property_id'],event['reservation_id'],gid,event['id'],backend.now_iso()))
            from zoneinfo import ZoneInfo
            day=datetime.fromisoformat(event['occurred_at']).astimezone(ZoneInfo(event['timezone'])).date()
            identity=viza_identity.readiness(backend,con,gid,day)
            member={'guest_id':gid,'arrival_uuid':uid,'identity':identity,'expected_departure':r['departure_date'],'blockers':identity['blockers']}
            if r['departure_date']<=str(day):member['blockers'].append('Q6_same_day_expected_departure_unresolved')
            members.append(member)
        else:
            v=visit(con,gid,active=True)
            if not v:
                # Pre-migration occupancy is not evidence of an original arrival UUID.
                blockers.append('legacy_arrival_uuid_unknown');continue
            con.execute('UPDATE viza_visits SET active=0,retired=?,departure_event_id=? WHERE arrival_uuid=?',(int(kind=='undo_arrival'),event['id'],v['arrival_uuid']))
            arrival_time=con.execute('SELECT occurred_at FROM stay_events WHERE id=?',(v['arrival_event_id'],)).fetchone()['occurred_at']
            restrictions=['departure_not_after_arrival'] if datetime.fromisoformat(event['occurred_at'])<=datetime.fromisoformat(arrival_time) else []
            if gid in unsent_voids:restrictions.append('never_sent_arrival_voided_no_submission')
            if kind=='undo_arrival' and con.execute("SELECT 1 FROM viza_jobs j JOIN viza_job_guests g ON g.job_id=j.id WHERE g.arrival_uuid=? AND j.kind='arrival' AND (j.state='uncertain' OR j.attempts>0 AND j.state!='accepted')",(v['arrival_uuid'],)).fetchone():restrictions.append('Q7_uncertain_arrival_closure')
            members.append({'guest_id':gid,'arrival_uuid':v['arrival_uuid'],'erroneous_arrival':kind=='undo_arrival','blockers':restrictions})
    if not members and gids:
        # Visible blocker without manufacturing an arrival UUID for legacy occupancy.
        members=[{'guest_id':gid,'arrival_uuid':None,'blockers':['legacy_arrival_uuid_unknown']} for gid in gids]
        queue_legacy(backend,con,event,members,blockers);return
    if members:queue(backend,con,event,'arrival' if kind=='arrive' else 'departure',members,blockers)


def queue_legacy(backend,con,event,members,blockers):
    # A non-protocol local diagnostic; excluded from visit/member table and transport.
    jid=str(uuid.uuid4());errors=sorted(set(blockers)|{'legacy_arrival_uuid_unknown','official_transmission_disabled'})
    con.execute('''INSERT INTO government_outbox(id,organization_id,property_id,reservation_id,system,event_type,payload_json,status,attempts,created_at)
      VALUES (?,?,?,?,'VIZA','viza.legacy_blocker',?,'viza_capture_blocked',0,?)''',(jid,event['organization_id'],event['property_id'],event['reservation_id'],json.dumps({'viza_job_id':jid}),backend.now_iso()))
    con.execute('INSERT INTO viza_jobs VALUES (?,?,0,1,?,?,?, ?,?,?,0,NULL,?)',(jid,event['id'],event['organization_id'],event['property_id'],'legacy_blocker',
        backend.encrypt_json({'guests':members}),json.dumps(errors),'blocked',backend.now_iso()))


def overview(con,org,rid):
    return [{**dict(r),'blockers':json.loads(r['blockers_json'])} for r in con.execute('''SELECT j.id,j.event_id,j.kind,j.state,j.attempts,j.blockers_json,j.created_at
      FROM viza_jobs j JOIN stay_events e ON e.id=j.event_id WHERE j.organization_id=? AND e.reservation_id=? ORDER BY e.sequence,j.batch_number,j.revision''',(org,rid))]


def recover(backend,con,event):
    """Explicit normal-workflow recovery creates immutable revisions, never resends."""
    from zoneinfo import ZoneInfo
    if event['kind']!='arrive':return []
    rows=con.execute("SELECT * FROM viza_jobs WHERE event_id=? AND state='blocked' AND attempts=0 ORDER BY batch_number,revision DESC",(event['id'],)).fetchall()
    latest={}
    for row in rows:latest.setdefault(row['batch_number'],row)
    result=[]
    day=datetime.fromisoformat(event['occurred_at']).astimezone(ZoneInfo(event['timezone'])).date()
    for old in latest.values():
        facts=backend.decrypt_json(old['encrypted_facts']);members=[]
        for member in facts['guests']:
            identity=viza_identity.readiness(backend,con,member['guest_id'],day)
            updated={**member,'identity':identity,'blockers':list(identity['blockers'])}
            if updated['expected_departure']<=str(day):updated['blockers'].append('Q6_same_day_expected_departure_unresolved')
            members.append(updated)
        if members==facts['guests']:continue
        # Rebuild one full event revision; this also handles 10+ guest batches consistently.
        all_members=[]
        for batch in latest.values():
            for member in backend.decrypt_json(batch['encrypted_facts'])['guests']:
                identity=viza_identity.readiness(backend,con,member['guest_id'],day)
                updated={**member,'identity':identity,'blockers':list(identity['blockers'])}
                if updated['expected_departure']<=str(day):updated['blockers'].append('Q6_same_day_expected_departure_unresolved')
                all_members.append(updated)
        revision=max(j['revision'] for j in latest.values())+1
        for batch in latest.values():
            con.execute("UPDATE viza_jobs SET state='superseded_before_submission' WHERE id=?",(batch['id'],))
            con.execute("UPDATE government_outbox SET status='superseded_before_submission' WHERE id=?",(batch['id'],))
        result=queue(backend,con,event,'arrival',all_members,revision=revision)
        break
    return result

def unsigned_request(backend,con,job_id,header):
    """Build body for offline inspection only. Property signature belongs to V05."""
    import viza_contracts as c
    job=con.execute('SELECT * FROM viza_jobs WHERE id=?',(job_id,)).fetchone()
    if not job:raise c.ContractError('job_not_found')
    if job['state']!='blocked' or job['attempts']:raise c.ContractError('submission_state_held')
    return request_for_snapshot(backend,dict(job),header)


def request_for_snapshot(backend,job,header):
    import viza_contracts as c
    holds=set(json.loads(job['blockers_json']))-{'Q2_outer_ws_security_unresolved','official_transmission_disabled','property_configuration_not_bound'}
    if holds:raise c.ContractError('reporting_facts_blocked')
    facts=backend.decrypt_json(job['encrypted_facts']);guests=[]
    from zoneinfo import ZoneInfo
    observed=datetime.fromisoformat(facts['occurred_at']).astimezone(ZoneInfo(facts['timezone']))
    for member in facts['guests']:
        if not member.get('arrival_uuid'):raise c.ContractError('legacy_arrival_uuid_unknown')
        if job['kind']=='arrival':
            identity=member['identity']
            if identity['blockers']:raise c.ContractError('identity_not_ready')
            groups={}
            for source,name in (('original','okmanybolBeolvasottAdat'),('manual','manualisanRogzitettAdat')):
                values={k:v for k,v in identity[source].items() if k in c.FIELDS}
                if values:
                    if values.get('allampolgarsagKod'):
                        try:values['allampolgarsagKod']=c.country(values['allampolgarsagKod'])
                        except c.ContractError:
                            # An explicit manual two-letter review can resolve a reader code ambiguity.
                            values['allampolgarsagKod']=c.country(identity['effective'].get('allampolgarsagKod'))
                    groups[name]=c.Person(**values)
            extra={k:identity['effective'].get(k) if identity['third_country_applicable'] else None for k in viza_identity.EXTRA}
            guests.append(c.Arrival(erkezesAzonosito=member['arrival_uuid'],erkezesIdeje=observed,tavozasVarhatoDatuma=member['expected_departure'],**groups,**extra))
        elif job['kind']=='departure':guests.append(c.Departure(erkezesAzonosito=member['arrival_uuid'],tavozasIdeje=observed))
        else:raise c.ContractError('correction_protocol_held')
    cls=c.ArrivalRequest if job['kind']=='arrival' else c.DepartureRequest
    dto=cls(**header,**{'erkezoVendeg' if job['kind']=='arrival' else 'tavozoVendeg':guests})
    return c.serialize('erkezesiAdatokBekuldese' if job['kind']=='arrival' else 'tavozasiAdatokBekuldese',dto,now=backend.datetime.now(__import__('datetime').timezone.utc),exact_report_timestamp=header.get('bejelentesIdopontja') if isinstance(header.get('bejelentesIdopontja'),str) else None)
