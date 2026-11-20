"""Durable, tenant/property/environment-bound NTAK reporting state.

Uses the existing government outbox and attempts. No operational database is
opened at import. The normal worker cannot contact official endpoints.
"""
from datetime import date, datetime, timedelta, timezone
from zoneinfo import ZoneInfo
import hashlib
import json
import uuid
import ntak_diagnostics
import ntak_evidence
from ntak_contracts import ContractError
from ntak_protocol import ReportingBlocked, request_xml, reservation_payload, response, validate_business
from ntak_transport import UnresolvedOfficialTransport, require_resolved_operation


def stamp(now=None):
    return (now or datetime.now(timezone.utc)).isoformat()


def dump(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(',', ':'), allow_nan=False)


def migrate(con):
    con.executescript('''
    CREATE TABLE IF NOT EXISTS ntak_jobs (
      id TEXT PRIMARY KEY REFERENCES government_outbox(id) ON DELETE CASCADE,
      organization_id TEXT NOT NULL, property_id TEXT NOT NULL, environment TEXT NOT NULL,
      operation TEXT NOT NULL, logical_key TEXT NOT NULL, message_id TEXT NOT NULL,
      configuration_json TEXT NOT NULL, payload_json TEXT NOT NULL, state TEXT NOT NULL,
      error_code TEXT, missing_fields_json TEXT NOT NULL DEFAULT '[]', processing_id TEXT,
      next_attempt_at TEXT NOT NULL, lease_until TEXT, lease_token TEXT,
      attempts INTEGER NOT NULL DEFAULT 0, retries INTEGER NOT NULL DEFAULT 0,
      protocol_resends INTEGER NOT NULL DEFAULT 0,
      accepted_at TEXT, created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
      UNIQUE(organization_id,property_id,environment,logical_key)
    );
    CREATE INDEX IF NOT EXISTS idx_ntak_due ON ntak_jobs(state,next_attempt_at);
    CREATE TABLE IF NOT EXISTS ntak_reservation_facts (
      reservation_id TEXT PRIMARY KEY REFERENCES reservations(id) ON DELETE CASCADE,
      organization_id TEXT NOT NULL, property_id TEXT NOT NULL,
      facts_json TEXT NOT NULL, updated_at TEXT NOT NULL
    );
    CREATE TABLE IF NOT EXISTS ntak_reservation_versions (
      reservation_id TEXT PRIMARY KEY REFERENCES reservations(id) ON DELETE CASCADE,
      fingerprint TEXT NOT NULL, revision INTEGER NOT NULL
    );
    CREATE TABLE IF NOT EXISTS ntak_day_facts (
      organization_id TEXT NOT NULL, property_id TEXT NOT NULL REFERENCES properties(id) ON DELETE CASCADE,
      business_date TEXT NOT NULL, revision INTEGER NOT NULL, payload_json TEXT NOT NULL,
      confirmed_by TEXT NOT NULL, confirmed_at TEXT NOT NULL,
      PRIMARY KEY(organization_id,property_id,business_date)
    );
    CREATE TABLE IF NOT EXISTS ntak_daily_requirements (
      organization_id TEXT NOT NULL, property_id TEXT NOT NULL REFERENCES properties(id) ON DELETE CASCADE,
      business_date TEXT NOT NULL, state TEXT NOT NULL, job_id TEXT,
      PRIMARY KEY(organization_id,property_id,business_date)
    );
    CREATE TABLE IF NOT EXISTS ntak_guest_ids (
      organization_id TEXT NOT NULL, property_id TEXT NOT NULL REFERENCES properties(id) ON DELETE CASCADE,
      guest_record_id TEXT NOT NULL REFERENCES guest_records(id) ON DELETE CASCADE,
      reporting_id TEXT NOT NULL, created_at TEXT NOT NULL,
      PRIMARY KEY(organization_id,property_id,guest_record_id)
    );
    ''')
    con.execute('INSERT OR IGNORE INTO schema_migrations(version,name,applied_at) VALUES (?,?,?)',
                (3073, 'ntak_v9_durable_reporting', stamp()))


def configuration(con, org, prop):
    row = con.execute("SELECT public_config_json FROM government_connections WHERE organization_id=? AND property_id=? AND system='NTAK'", (org, prop)).fetchone()
    return json.loads(row['public_config_json']).get('ntak_v9') if row else None


def enqueue(con, org, prop, config, operation, logical_key, payload, *, reservation_id=None, now=None, blocked=None):
    now = now or datetime.now(timezone.utc)
    environment = config['environment']
    con.execute("UPDATE government_connections SET id=id WHERE organization_id=? AND property_id=? AND system='NTAK'", (org,prop))
    existing = con.execute('SELECT * FROM ntak_jobs WHERE organization_id=? AND property_id=? AND environment=? AND logical_key=?', (org, prop, environment, logical_key)).fetchone()
    if existing:
        if existing['payload_json'] != dump(payload):
            raise ReportingBlocked('logical_event_conflict')
        return existing['id']
    identity = {k: config.get(k) for k in ('registration_id','provider_vat','software_id','software_version','environment')}
    job, message_id = str(uuid.uuid4()), str(uuid.uuid4())
    state, code, fields = 'ready', None, []
    try:
        if blocked:
            raise blocked
        require_resolved_operation(operation)
        validate_business(operation, payload, now.astimezone(ZoneInfo(config.get('timezone', 'Europe/Budapest'))).date())
        request_xml(operation, identity, payload, message_id, stamp(now))
    except (ReportingBlocked, ContractError) as exc:
        state, code, fields = 'blocked', getattr(exc, 'code', 'schema_validation_failed'), getattr(exc, 'fields', [])
    created = stamp(now)
    con.execute('''INSERT INTO government_outbox(id,organization_id,property_id,reservation_id,system,event_type,payload_json,status,attempts,created_at)
                   VALUES (?,?,?,?,'NTAK',?,?,?,0,?)''', (job,org,prop,reservation_id,operation,dump({'logical_key':logical_key,'reporting_payload':payload}),state,created))
    con.execute('''INSERT INTO ntak_jobs(id,organization_id,property_id,environment,operation,logical_key,message_id,configuration_json,payload_json,state,error_code,missing_fields_json,next_attempt_at,created_at,updated_at)
                   VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)''',
                (job,org,prop,environment,operation,logical_key,message_id,dump(identity),dump(payload),state,code,dump(fields),created,created,created))
    ntak_evidence.capture(con,con.execute('SELECT * FROM ntak_jobs WHERE id=?',(job,)).fetchone(),created)
    if reservation_id:
        for prior in con.execute('''SELECT j.id FROM ntak_jobs j JOIN government_outbox o ON o.id=j.id
          WHERE j.id<>? AND j.organization_id=? AND j.property_id=? AND j.environment=? AND j.operation=? AND o.reservation_id=?''',
          (job,org,prop,environment,operation,reservation_id)).fetchall():
            ntak_evidence.link(con,job,prior['id'],'reservation_revision' if operation=='reservation' else 'reservation_event',created)
    if operation=='daily_close' and payload.get('napiFeltoltes',{}).get('lezartNap'):
        day=payload['napiFeltoltes']['lezartNap']
        for prior in con.execute("SELECT id,payload_json FROM ntak_jobs WHERE id<>? AND organization_id=? AND property_id=? AND environment=? AND operation='daily_close'",(job,org,prop,environment)).fetchall():
            if json.loads(prior['payload_json']).get('napiFeltoltes',{}).get('lezartNap')==day:
                ntak_evidence.link(con,job,prior['id'],'daily_version',created)
    return job


def capture_reservation(con, org, reservation_id, now=None):
    row = con.execute('SELECT * FROM reservations WHERE organization_id=? AND id=?', (org,reservation_id)).fetchone()
    if not row: return
    config = configuration(con, org, row['property_id'])
    if not config or not config.get('enabled') or row['status'] not in ('confirmed','cancelled'): return
    # Serializes revision capture on both SQLite and PostgreSQL.
    con.execute('UPDATE reservations SET id=id WHERE id=? AND organization_id=?', (reservation_id,org))
    facts = con.execute('SELECT facts_json FROM ntak_reservation_facts WHERE organization_id=? AND reservation_id=? AND property_id=?', (org,reservation_id,row['property_id'])).fetchone()
    source = {k: row[k] for k in ('id','property_id','arrival_date','departure_date','created_at','guest_count','status','total_huf')}
    import reservation_reporting
    extra = reservation_reporting.facts(con,row,json.loads(facts['facts_json']) if facts else {})
    source['id']=row['ntak_booking_id'] or row['id']
    source['created_at']=row['booking_created_at']
    if extra.get('expected_guest_count') is not None:source['guest_count']=extra['expected_guest_count']
    fingerprint = hashlib.sha256(dump([source,extra,config['environment']]).encode()).hexdigest()
    previous = con.execute('SELECT * FROM ntak_reservation_versions WHERE reservation_id=?', (reservation_id,)).fetchone()
    if previous and previous['fingerprint'] == fingerprint: return
    revision = previous['revision'] + 1 if previous else 1
    blocked = None
    try:
        if not source['created_at']:raise ReportingBlocked('original_booking_timestamp_missing',['booking_created_at'])
        if extra.get('vendegKuldoOrszaga')=='EGYEBKULFOLDI':raise ReportingBlocked('sending_country_contract_unresolved',['vendegKuldoOrszaga'])
        payload = reservation_payload(source, extra, stamp(now))
    except (ReportingBlocked, KeyError, TypeError, ValueError) as exc:
        blocked = exc if isinstance(exc, ReportingBlocked) else ReportingBlocked('invalid_reporting_data')
        # Keep factual snapshot for recovery, never invent values for a valid XML.
        payload = {'source':source,'facts':extra}
    job = enqueue(con,org,row['property_id'],config,'reservation',f'reservation:{reservation_id}:{revision}',payload,reservation_id=reservation_id,now=now,blocked=blocked)
    con.execute('INSERT INTO ntak_reservation_versions(reservation_id,fingerprint,revision) VALUES (?,?,?) ON CONFLICT(reservation_id) DO UPDATE SET fingerprint=excluded.fingerprint,revision=excluded.revision', (reservation_id,fingerprint,revision))
    return job


def schedule_daily(con, now=None):
    now = now or datetime.now(timezone.utc)
    for row in con.execute("SELECT organization_id,property_id FROM government_connections WHERE system='NTAK'").fetchall():
        org, prop = row['organization_id'], row['property_id']
        config = configuration(con,org,prop)
        if not config or not config.get('enabled'): continue
        # Configured operating calendars use authoritative normal closing only.
        if con.execute('SELECT 1 FROM business_day_settings WHERE property_id=? AND organization_id=?',(prop,org)).fetchone():continue
        start = config.get('reporting_start_date')
        if not start: continue  # unresolved information operation never invents a start date
        current = now.astimezone(ZoneInfo(config['timezone']))
        last = current.date() - timedelta(days=1 if current.hour >= config['closing_hour'] else 2)
        first = date.fromisoformat(start)
        # No silent loss: retain one requirement per date, including missing data.
        for offset in range(max(0, min(470, (last-first).days+1))):
            day = str(first+timedelta(days=offset))
            con.execute("INSERT OR IGNORE INTO ntak_daily_requirements(organization_id,property_id,business_date,state) VALUES (?,?,?,'awaiting_closing_facts')", (org,prop,day))
            facts = con.execute('SELECT * FROM ntak_day_facts WHERE organization_id=? AND property_id=? AND business_date=?', (org,prop,day)).fetchone()
            if not facts: continue
            job = enqueue(con,org,prop,config,'daily_close',f'daily:{day}:{facts["revision"]}',json.loads(facts['payload_json']),now=now)
            con.execute("UPDATE ntak_daily_requirements SET state='queued',job_id=? WHERE organization_id=? AND property_id=? AND business_date=?", (job,org,prop,day))


def set_state(con, job, state, code, now, **updates):
    values = {'state':state,'error_code':code,'updated_at':stamp(now),**updates}
    con.execute('UPDATE ntak_jobs SET '+','.join(k+'=?' for k in values)+' WHERE id=?', (*values.values(),job['id']))
    con.execute('UPDATE government_outbox SET status=?,last_error=?,external_receipt=COALESCE(?,external_receipt),sent_at=? WHERE id=?',
                (state,code,updates.get('processing_id'),stamp(now) if state=='succeeded' else None,job['id']))


def worker_once(db, *, transport=None, now=None, limit=10):
    """Claim/commit before I/O. Expired sends become uncertain, never blind retries."""
    now = now or datetime.now(timezone.utc)
    adapter = transport or UnresolvedOfficialTransport()
    with db() as con:
        schedule_daily(con,now)
        for job in con.execute("SELECT * FROM ntak_jobs WHERE state='sending' AND lease_until<?", (stamp(now),)).fetchall():
            ntak_evidence.event(con,job['id'],None,'interrupted',{'state':'accepted' if job['processing_id'] else 'uncertain','processing_id':job['processing_id']},stamp(now))
            set_state(con,job,'accepted' if job['processing_id'] else 'uncertain','worker_interrupted',now,lease_token=None,lease_until=None,next_attempt_at=stamp(now))
        due = con.execute("SELECT id FROM ntak_jobs WHERE state IN ('ready','retry','accepted') AND next_attempt_at<=? ORDER BY created_at,id LIMIT ?", (stamp(now),limit)).fetchall()
    processed = 0
    for ref in due:
        with db() as con:
            job = con.execute('SELECT * FROM ntak_jobs WHERE id=?',(ref['id'],)).fetchone()
            if not job or job['state'] not in ('ready','retry','accepted'): continue
            if job['operation']=='stay' and con.execute('''SELECT prior.id FROM stay_events current_event
              JOIN stay_event_guests current_guest ON current_guest.event_id=current_event.id
              JOIN stay_event_guests prior_guest ON prior_guest.guest_id=current_guest.guest_id
              JOIN stay_events prior ON prior.id=prior_guest.event_id
              LEFT JOIN ntak_jobs prior_job ON prior_job.id=prior.reporting_job_id
              WHERE current_event.reporting_job_id=? AND prior.reservation_id=current_event.reservation_id
              AND prior.sequence<current_event.sequence
              AND (prior.reporting_blocker IS NULL OR prior.reporting_blocker NOT IN ('superseded_before_submission','original_not_submitted_no_counter_needed'))
              AND (prior_job.id IS NULL OR NOT (prior_job.state='succeeded' OR (prior_job.state='review_required' AND prior_job.error_code IS NULL))) LIMIT 1''',(job['id'],)).fetchone():continue
            if con.execute("SELECT p.job_id FROM ntak_job_predecessors p JOIN ntak_jobs j ON j.id=p.predecessor_job_id WHERE p.job_id=? AND NOT (j.state='succeeded' OR (j.state='review_required' AND j.error_code IS NULL)) LIMIT 1",(job['id'],)).fetchone():continue
            if 'predecessor_job_id' in job.keys() and job['predecessor_job_id']:
                predecessor=con.execute('SELECT state,error_code FROM ntak_jobs WHERE id=?',(job['predecessor_job_id'],)).fetchone()
                if not predecessor or not (predecessor['state']=='succeeded' or predecessor['state']=='review_required' and predecessor['error_code'] is None):continue
            config = configuration(con,job['organization_id'],job['property_id'])
            if not config or not config.get('enabled') or config['environment'] != job['environment']:
                set_state(con,job,'blocked','environment_or_configuration_changed',now); continue
            identity=json.loads(job['configuration_json'])
            if any(config.get(k)!=identity.get(k) for k in ('registration_id','provider_vat','software_id')):
                set_state(con,job,'blocked','property_identity_changed',now); continue
            # Credentials, signature policy and official transport are unresolved.
            # No environment flag or owner request can turn the default into a mock.
            if transport is None:
                set_state(con,job,'blocked','signature_profile_unresolved',now); continue
            if job['processing_id'] and job['accepted_at'] and now-datetime.fromisoformat(job['accepted_at']) > timedelta(days=28):
                set_state(con,job,'review_required','verification_window_expiring',now); continue
            # Keep below the documented 1000/property/hour including verification.
            used = con.execute('''SELECT COUNT(*) c FROM government_delivery_attempts a JOIN ntak_jobs j ON j.id=a.outbox_id
              WHERE j.organization_id=? AND j.property_id=? AND a.created_at>?''', (job['organization_id'],job['property_id'],stamp(now-timedelta(hours=1)))).fetchone()['c']
            if used >= 900:
                set_state(con,job,job['state'],'hourly_rate_limit',now,next_attempt_at=stamp(now+timedelta(minutes=5))); continue
            try: ntak_evidence.capture(con,job,stamp(now))
            except ReportingBlocked:
                set_state(con,job,'blocked','immutable_evidence_conflict',now); continue
            token = str(uuid.uuid4())
            claimed = con.execute("UPDATE ntak_jobs SET state='sending',lease_token=?,lease_until=?,attempts=attempts+1 WHERE id=? AND state=?", (token,stamp(now+timedelta(minutes=2)),job['id'],job['state'])).rowcount
            if claimed != 1: continue
            poll = bool(job['processing_id'])
            operation = 'verification' if poll else job['operation']
            payload = {'feldolgozasAzonositok':{'feldolgozasAzonosito':[job['processing_id']]}} if poll else json.loads(job['payload_json'])
            try:
                require_resolved_operation(operation)
                if not poll: validate_business(operation,payload,now.astimezone(ZoneInfo(config['timezone'])).date())
                xml = request_xml(operation,json.loads(job['configuration_json']),payload,str(uuid.uuid4()) if poll else job['message_id'],stamp(now) if poll else job['created_at'])
            except (ReportingBlocked,ContractError) as exc:
                set_state(con,job,'blocked',getattr(exc,'code','schema_validation_failed'),now,lease_token=None,lease_until=None); continue
            attempt = str(uuid.uuid4())
            con.execute('''INSERT INTO government_delivery_attempts(id,organization_id,outbox_id,system,attempt_no,state,request_hash,created_at)
              VALUES (?,?,?,'NTAK',?,'started',?,?)''', (attempt,job['organization_id'],job['id'],job['attempts']+1,hashlib.sha256(xml).hexdigest(),stamp(now)))
            ntak_evidence.request(con,job,attempt,operation,xml,stamp(now))
        received = None
        try:
            received = adapter.exchange(operation,xml,property_id=job['property_id'],environment=job['environment'])
            result = response(operation,received,job['processing_id'])
        except ReportingBlocked as exc:
            result = {'state':'blocked','codes':[exc.code],'diagnostics':[{'severity':'error','code':exc.code,'field':'GLOBAL'}]}
        except Exception:
            # A timeout, malformed response or unknown fault may follow acceptance.
            result = {'state':'accepted' if poll else 'uncertain','codes':['outcome_unknown']}
        with db() as con:
            live = con.execute('SELECT * FROM ntak_jobs WHERE id=? AND lease_token=?',(job['id'],token)).fetchone()
            if received is not None:
                ntak_evidence.event(con,job['id'],attempt,'response',ntak_evidence.received(received),stamp(now))
            if not live:
                ntak_evidence.event(con,job['id'],attempt,'late_outcome',{'state':'uncertain','lease_current':False,'operation':operation,
                    'protocol_state':result['state'],'processing_id':result.get('processing_id') or job['processing_id']},stamp(now))
                continue
            state = result['state']; codes = result.get('codes',[])
            local_codes={'signature_profile_unresolved','information_response_contract_unresolved',
                         'outcome_unknown','soap_fault'}
            safe_codes=[c if c in ntak_diagnostics.CATALOG or c in ntak_diagnostics.LOCAL_SECURITY or c in local_codes
                        else 'remote_validation_error' for c in codes][:25]
            code = safe_codes[0] if safe_codes else ('remote_validation_error' if codes else None)
            updates = {'lease_token':None,'lease_until':None,'next_attempt_at':stamp(now+timedelta(minutes=5))}
            if state == 'rejected' and 'SzerverHiba' in codes:
                delays = [1,10,60]
                if job['retries'] < len(delays):
                    state='accepted' if poll else 'retry'
                    updates.update(retries=job['retries']+1,next_attempt_at=stamp(now+timedelta(minutes=delays[job['retries']])))
                else: state='retry_exhausted'
            if state == 'resend_required':
                if 'FeldolgozasHiba' not in codes and job['protocol_resends']==0:
                    state='retry'
                    updates.update(processing_id=None,accepted_at=None,protocol_resends=1)
                else:
                    # A modified version is defined only for daily closures.
                    state='review_required'; code='resend_version_review_required'
            if (result['state']=='resend_required' and 'FeldolgozasHiba' in codes) or (state=='rejected' and 'EgyedisegKorlatozas' in codes and job['protocol_resends']==1):
                if job['operation']=='daily_close' and job['protocol_resends']<2:
                    corrected=json.loads(job['payload_json'])
                    corrected['napiFeltoltes']['napiZarasBesorolas']={'besorolas':'MODOSITO','jegyzokonyvAzonosito':job['id'].replace('-','')[:25],'indoklas':'NTAK processing recovery: '+('FeldolgozasHiba' if 'FeldolgozasHiba' in codes else 'EgyedisegKorlatozas')}
                    successor=enqueue(con,job['organization_id'],job['property_id'],config,'daily_close',job['logical_key']+':protocol-correction',corrected,now=now)
                    ntak_evidence.link(con,successor,job['id'],'protocol_correction',stamp(now))
                    con.execute('UPDATE ntak_jobs SET protocol_resends=2 WHERE id=?',(successor,))
                    con.execute('UPDATE ntak_daily_requirements SET job_id=? WHERE job_id=?',(successor,job['id']))
                    state='replaced_by_correction'; code=None
                else:
                    state='review_required'; code='resend_version_review_required'
            if result.get('processing_id'):
                updates.update(processing_id=result['processing_id'],accepted_at=stamp(now),retries=0)
            set_state(con,job,state,code,now,**updates)
            con.execute('UPDATE government_outbox SET attempts=attempts+1 WHERE id=?',(job['id'],))
            ntak_evidence.event(con,job['id'],attempt,'outcome',{'operation':operation,'protocol_state':result['state'],
                'state':state,'codes':safe_codes,'processing_id':result.get('processing_id') or job['processing_id'],'lease_current':True},stamp(now))
            ntak_diagnostics.record(con, job, attempt, 'verification' if poll else 'receipt',
                                    result.get('diagnostics', []), stamp(now))
            # Store only bounded known-format error keys, no returned guest values/prose.
            con.execute('UPDATE government_delivery_attempts SET state=?,response_summary=? WHERE id=?',(state,dump({'codes':safe_codes,'processing_id':result.get('processing_id')}),attempt))
            if state=='succeeded':
                con.execute("UPDATE government_connections SET last_success_at=?,last_error=NULL WHERE organization_id=? AND property_id=? AND system='NTAK'",(stamp(now),job['organization_id'],job['property_id']))
        processed += 1
    return processed
