"""Durable VIZA delivery/monitoring. The runtime default cannot contact any endpoint."""
from datetime import datetime,timedelta,timezone
import hashlib,json,random,re,uuid
import viza_contracts as c
import viza_reporting as capture
from viza_security import Binding,DisabledOfficialTransport,SecurityBlocked,DefinitelyNotSent,OutcomeUncertain,PermanentFailure

GATES={'Q2_outer_ws_security_unresolved','official_transmission_disabled','property_configuration_not_bound'}
FLAGS=frozenset(('VIZA-OFFLINE','KM-OFFLINE','OUTOFKEYS','RA-OFFLINE','CERT-WARNING','CERT-EXPIRED','CERT-RENEWED','RESTART-THF','DATA-REJECTED'))
def stamp(now):return now.astimezone(timezone.utc).isoformat()
def dump(value):return json.dumps(value,sort_keys=True,separators=(',',':'))
def digest(value):return hashlib.sha256(dump(value).encode('utf8')).hexdigest()
def now_utc():return datetime.now(timezone.utc)
def binding_digest(config):return digest({k:v for k,v in (config or {}).items() if k!='poll_minutes'})

def migrate(con,now):
    con.executescript('''CREATE TABLE IF NOT EXISTS viza_settings (
      property_id TEXT PRIMARY KEY REFERENCES properties(id),organization_id TEXT NOT NULL,config_json TEXT NOT NULL,updated_at TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS viza_dispatch (
      job_id TEXT PRIMARY KEY REFERENCES viza_jobs(id),environment TEXT,binding_digest TEXT,encrypted_binding TEXT,
      report_timestamp TEXT,state TEXT NOT NULL,due_at TEXT NOT NULL,claim_id TEXT,lease_until TEXT,
      wire_timestamp TEXT,receipt_id TEXT,error_code TEXT,mode TEXT NOT NULL,updated_at TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS viza_attempts (
      id TEXT PRIMARY KEY REFERENCES government_delivery_attempts(id),job_id TEXT NOT NULL REFERENCES viza_jobs(id),
      claim_id TEXT NOT NULL UNIQUE,wire_timestamp TEXT NOT NULL,finished_at TEXT,encrypted_response TEXT);
    CREATE TABLE IF NOT EXISTS viza_guest_outcomes (
      job_id TEXT NOT NULL REFERENCES viza_jobs(id),arrival_uuid TEXT NOT NULL,state TEXT NOT NULL,codes_json TEXT NOT NULL,
      receipt_id TEXT,downstream_state TEXT NOT NULL DEFAULT 'unknown',PRIMARY KEY(job_id,arrival_uuid));
    CREATE TABLE IF NOT EXISTS viza_message_status(job_id TEXT PRIMARY KEY REFERENCES viza_jobs(id),downstream_state TEXT NOT NULL,observation_id TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS viza_job_dependencies (
      job_id TEXT NOT NULL REFERENCES viza_jobs(id),predecessor_id TEXT NOT NULL REFERENCES viza_jobs(id),PRIMARY KEY(job_id,predecessor_id));
    CREATE TABLE IF NOT EXISTS viza_monitor_schedule (
      property_id TEXT NOT NULL,environment TEXT NOT NULL,operation TEXT NOT NULL,selector TEXT NOT NULL,
      due_at TEXT NOT NULL,claim_id TEXT,lease_until TEXT,last_error TEXT,PRIMARY KEY(property_id,environment,operation,selector));
    CREATE TABLE IF NOT EXISTS viza_observations (
      id TEXT PRIMARY KEY,organization_id TEXT NOT NULL,property_id TEXT NOT NULL,environment TEXT NOT NULL,
      binding_digest TEXT NOT NULL,operation TEXT NOT NULL,selector TEXT NOT NULL,mode TEXT NOT NULL,
      observed_at TEXT NOT NULL,encrypted_payload TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS viza_actions (
      id TEXT PRIMARY KEY,organization_id TEXT NOT NULL,property_id TEXT NOT NULL,job_id TEXT,
      action TEXT NOT NULL,actor_id TEXT NOT NULL,result_code TEXT NOT NULL,created_at TEXT NOT NULL);
    CREATE INDEX IF NOT EXISTS idx_viza_dispatch_due ON viza_dispatch(state,due_at);
    CREATE INDEX IF NOT EXISTS idx_viza_observations ON viza_observations(property_id,environment,observed_at);
    ''')
    if con.backend=='sqlite':
        con.raw.execute("CREATE TRIGGER IF NOT EXISTS viza_binding_immutable BEFORE UPDATE OF environment,binding_digest,encrypted_binding,report_timestamp ON viza_dispatch WHEN OLD.binding_digest IS NOT NULL BEGIN SELECT RAISE(ABORT,'VIZA binding is immutable'); END")
    else:
        con.raw.execute("CREATE OR REPLACE FUNCTION viza_binding_no_update() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN IF OLD.binding_digest IS NOT NULL THEN RAISE EXCEPTION 'VIZA binding is immutable'; END IF; RETURN NEW; END; $$")
        con.raw.execute('DROP TRIGGER IF EXISTS viza_binding_immutable ON viza_dispatch')
        con.raw.execute('CREATE TRIGGER viza_binding_immutable BEFORE UPDATE OF environment,binding_digest,encrypted_binding,report_timestamp ON viza_dispatch FOR EACH ROW EXECUTE FUNCTION viza_binding_no_update()')
    con.execute('INSERT OR IGNORE INTO schema_migrations(version,name,applied_at) VALUES (3087,?,?)',('viza_delivery_monitoring',now))


def settings(con,org,prop):
    row=con.execute('SELECT config_json FROM viza_settings WHERE organization_id=? AND property_id=?',(org,prop)).fetchone()
    return json.loads(row['config_json']) if row else None

def binding(org,prop,config):
    return Binding(org,prop,config['environment'],config['reporting_id'],config['endpoint'],'server_managed').validate()

def retry_delay(attempt,randint=random.randint):
    if attempt<1:raise ValueError('attempt must be positive')
    if attempt<=2:return 0
    if attempt==3:return randint(1,60)
    return {4:600,5:3600,6:21600}.get(attempt,86400)

def safe_codes(raw):
    return list(dict.fromkeys(token for token in re.findall(r'EF[0-9]{4}|\bOK\b',raw or '') if token=='OK' or token in c.ERRORS))


def source_matches(backend,con,job):
    if job['kind']!='arrival':return True
    import viza_identity
    from zoneinfo import ZoneInfo
    event=con.execute('SELECT occurred_at,timezone FROM stay_events WHERE id=?',(job['event_id'],)).fetchone()
    day=datetime.fromisoformat(event['occurred_at']).astimezone(ZoneInfo(event['timezone'])).date()
    for member in backend.decrypt_json(job['encrypted_facts'])['guests']:
        current=viza_identity.readiness(backend,con,member['guest_id'],day)
        snapshot=member['identity']
        for key in ('effective','original','manual','third_country_applicable','ready'):
            if current.get(key)!=snapshot.get(key):return False
        # Q6 is a package rule, not an identity-source change.
        if set(current['blockers'])!=set(snapshot['blockers'])-{'Q6_same_day_expected_departure_unresolved'}:return False
    return True


def synchronize(backend,con,now,*,organization_id=None,property_id=None):
    # First write acquires the shared SQLite write lock; PostgreSQL property locks below.
    query='SELECT * FROM viza_jobs';params=[];filters=[]
    for column,value in (('organization_id',organization_id),('property_id',property_id)):
        if value is not None:filters.append(column+'=?');params.append(value)
    if filters:query+=' WHERE '+' AND '.join(filters)
    for row in con.execute(query+' ORDER BY created_at,id',params).fetchall():
        job=dict(row)
        con.execute('UPDATE properties SET id=id WHERE id=? AND organization_id=?',(job['property_id'],job['organization_id']))
        job=dict(con.execute('SELECT * FROM viza_jobs WHERE id=?',(job['id'],)).fetchone())
        if job['kind']=='arrival' and job['state']=='blocked' and job['attempts']==0 and not source_matches(backend,con,job):
            event=dict(con.execute('SELECT * FROM stay_events WHERE id=?',(job['event_id'],)).fetchone())
            capture.recover(backend,con,event)
            continue
        # Superseded never-sent predecessors must not block their valid replacement.
        con.execute("DELETE FROM viza_job_dependencies WHERE job_id=? AND predecessor_id IN (SELECT id FROM viza_jobs WHERE state='superseded_before_submission')",(job['id'],))
        config=settings(con,job['organization_id'],job['property_id'])
        d=con.execute('SELECT * FROM viza_dispatch WHERE job_id=?',(job['id'],)).fetchone()
        if not d:
            con.execute("INSERT INTO viza_dispatch(job_id,state,due_at,mode,updated_at) VALUES (?,'blocked',?,'disabled',?)",(job['id'],stamp(now),stamp(now)))
            d=con.execute('SELECT * FROM viza_dispatch WHERE job_id=?',(job['id'],)).fetchone()
        if job['state'] in ('superseded_before_submission','replaced_by_recovery'):
            con.execute("UPDATE viza_dispatch SET state='superseded_before_submission',claim_id=NULL,lease_until=NULL WHERE job_id=?",(job['id'],));continue
        if not config:continue
        try:binding(job['organization_id'],job['property_id'],config)
        except (SecurityBlocked,KeyError):continue
        config_digest=binding_digest(config)
        if not d['binding_digest']:
            con.execute('UPDATE viza_dispatch SET environment=?,binding_digest=?,encrypted_binding=?,report_timestamp=?,updated_at=? WHERE job_id=?',
                (config['environment'],config_digest,backend.encrypt_json(config),stamp(now),stamp(now),job['id']))
        elif d['binding_digest']!=config_digest:
            # Never move an already bound package between properties/environments.
            if d['state'] not in ('accepted','rejected','uncertain','review_required'):
                con.execute("UPDATE viza_dispatch SET state='blocked',error_code='environment_or_configuration_changed',claim_id=NULL,lease_until=NULL WHERE job_id=?",(job['id'],))
        for member in con.execute('SELECT arrival_uuid FROM viza_job_guests WHERE job_id=?',(job['id'],)):
            if job['kind']=='departure':
                for prior in con.execute("SELECT g.job_id FROM viza_job_guests g JOIN viza_jobs j ON j.id=g.job_id WHERE g.arrival_uuid=? AND j.kind='arrival' AND j.state!='superseded_before_submission'",(member['arrival_uuid'],)):
                    con.execute('INSERT OR IGNORE INTO viza_job_dependencies VALUES (?,?)',(job['id'],prior['job_id']))


def recover_leases(con,now):
    for d in con.execute("SELECT * FROM viza_dispatch WHERE state IN ('claimed','sending') AND lease_until<=?",(stamp(now),)).fetchall():
        state='retry' if d['state']=='claimed' else 'uncertain'
        code='claim_expired_before_send' if state=='retry' else 'worker_interrupted_outcome_unknown'
        con.execute('UPDATE viza_dispatch SET state=?,error_code=?,claim_id=NULL,lease_until=NULL,updated_at=? WHERE job_id=? AND claim_id=?',(state,code,stamp(now),d['job_id'],d['claim_id']))
        if state=='uncertain':
            con.execute("UPDATE viza_jobs SET state='uncertain' WHERE id=?",(d['job_id'],))
            con.execute("UPDATE government_outbox SET status='viza_mock_uncertain' WHERE id=?",(d['job_id'],))
            con.execute('UPDATE viza_attempts SET finished_at=? WHERE claim_id=?',(stamp(now),d['claim_id']))
            con.execute("UPDATE government_delivery_attempts SET state='uncertain',response_summary=? WHERE id IN (SELECT id FROM viza_attempts WHERE claim_id=?)",(dump({'code':code}),d['claim_id']))


def claim(backend,now,*,mode):
    if mode!='mock' or backend.APP_ENV!='test':return None
    with backend.db() as con:
        synchronize(backend,con,now);recover_leases(con,now)
        rows=con.execute("SELECT j.*,d.state dispatch_state,d.binding_digest,d.encrypted_binding,d.report_timestamp,d.error_code FROM viza_jobs j JOIN viza_dispatch d ON d.job_id=j.id WHERE d.state IN ('blocked','pending','retry') AND d.due_at<=? AND d.encrypted_binding IS NOT NULL ORDER BY d.due_at,j.created_at,j.id",(stamp(now),)).fetchall()
        for row in rows:
            job=dict(row);cfg=backend.decrypt_json(job['encrypted_binding'])
            if binding_digest(settings(con,job['organization_id'],job['property_id']))!=job['binding_digest']:continue
            if job['error_code'] in ('environment_or_configuration_changed','request_validation_failed'):continue
            holds=set(json.loads(job['blockers_json']))-GATES
            for hold in con.execute('SELECT h.blocker FROM viza_visit_holds h JOIN viza_job_guests g ON g.arrival_uuid=h.arrival_uuid WHERE g.job_id=?',(job['id'],)):holds.add(hold['blocker'])
            if holds or job['kind'] not in ('arrival','departure'):continue
            if not source_matches(backend,con,job):
                con.execute("UPDATE viza_dispatch SET error_code='source_facts_changed',state='blocked' WHERE job_id=?",(job['id'],))
                continue
            # Every arrival dependency, not only the original single pointer.
            if con.execute("SELECT 1 FROM viza_job_dependencies p LEFT JOIN viza_dispatch d ON d.job_id=p.predecessor_id WHERE p.job_id=? AND (d.state IS NULL OR d.state!='accepted')",(job['id'],)).fetchone():continue
            token=str(uuid.uuid4())
            cur=con.execute("UPDATE viza_dispatch SET state='claimed',claim_id=?,lease_until=?,mode='mock',updated_at=? WHERE job_id=? AND state IN ('blocked','pending','retry') AND claim_id IS NULL",(token,stamp(now+timedelta(seconds=60)),stamp(now),job['id']))
            if cur.rowcount:job.update(claim_id=token,config=cfg);return job
    return None


def finish(backend,job,state,code,now,*,raw=None,receipt=None,randint=random.randint):
    with backend.db() as con:
        d=con.execute("SELECT * FROM viza_dispatch WHERE job_id=? AND claim_id=? AND state='sending'",(job['id'],job['claim_id'])).fetchone()
        if not d:return False
        n=con.execute('SELECT attempts FROM viza_jobs WHERE id=?',(job['id'],)).fetchone()['attempts']
        due=now+timedelta(seconds=retry_delay(n,randint)) if state=='retry' else now
        encrypted=backend.encrypt_json({'xml':raw.decode('utf8',errors='replace')}) if raw is not None and len(raw)<=8*1024*1024 else None
        con.execute('UPDATE viza_attempts SET finished_at=?,encrypted_response=? WHERE claim_id=?',(stamp(now),encrypted,job['claim_id']))
        con.execute('UPDATE government_delivery_attempts SET state=?,response_summary=? WHERE id IN (SELECT id FROM viza_attempts WHERE claim_id=?)',(state,dump({'code':code,'mode':'mock'}),job['claim_id']))
        con.execute('UPDATE viza_dispatch SET state=?,error_code=?,due_at=?,claim_id=NULL,lease_until=NULL,receipt_id=?,updated_at=? WHERE job_id=? AND claim_id=?',
            (state,code,stamp(due),receipt.fogadasAzonosito if receipt else None,stamp(now),job['id'],job['claim_id']))
        con.execute('UPDATE viza_jobs SET state=? WHERE id=?',(state,job['id']))
        con.execute('UPDATE government_outbox SET status=?,attempts=?,external_receipt=? WHERE id=?',('viza_mock_'+state,n,receipt.fogadasAzonosito if receipt else None,job['id']))
        if receipt:
            for result in receipt.hibaLista:
                codes=result.codes
                outcome='accepted_by_thf' if codes==('OK',) and state=='accepted' else 'accepted_candidate' if codes==('OK',) else 'rejected'
                con.execute('''INSERT INTO viza_guest_outcomes(job_id,arrival_uuid,state,codes_json,receipt_id) VALUES (?,?,?,?,?)
                  ON CONFLICT(job_id,arrival_uuid) DO UPDATE SET state=excluded.state,codes_json=excluded.codes_json,receipt_id=excluded.receipt_id''',
                    (job['id'],result.erkezesAzonosito,outcome,dump([code if code=='OK' or code in c.ERRORS else 'UNKNOWN_CODE' for code in codes]),receipt.fogadasAzonosito))
        return True


def receipt_state(con,job,receipt):
    expected={r['arrival_uuid'] for r in con.execute('SELECT arrival_uuid FROM viza_job_guests WHERE job_id=?',(job['id'],))}
    actual=[r.erkezesAzonosito for r in receipt.hibaLista]
    if set(actual)!=expected or len(actual)!=len(set(actual)) or receipt.fogadasIdeje.utcoffset() is None:raise OutcomeUncertain('receipt_correlation_failed')
    results=[r.codes==('OK',) for r in receipt.hibaLista]
    if any('EF0021' in r.codes for r in receipt.hibaLista):return 'uncertain','Q7_duplicate_receipt_requires_review'
    if all(results) and receipt.sikeresBefogadas:return 'accepted',None
    if not any(results) and not receipt.sikeresBefogadas:return 'rejected','permanent_validation_error'
    return 'review_required','Q4_mixed_receipt_requires_review'


def worker_once(backend,*,transport=None,renderer=None,now=None,randint=random.randint,limit=10):
    now=now or backend.datetime.now(timezone.utc);transport=transport or DisabledOfficialTransport()
    with backend.db() as con:synchronize(backend,con,now);recover_leases(con,now)
    if transport.mode!='mock' or backend.APP_ENV!='test' or renderer is None:return 0
    processed=0
    for _ in range(limit):
        job=claim(backend,now,mode=transport.mode)
        if not job:break
        op='erkezesiAdatokBekuldese' if job['kind']=='arrival' else 'tavozasiAdatokBekuldese'
        try:
            raw=renderer(job,now);root=c.validate(raw,op)
            # A renderer cannot move a body to another reporting identity or message UUID.
            if root.find('.//{'+c.NS+'}uzenetAzonosito').text!=job['id'] or root.find('.//{'+c.NS+'}adatszolgaltatasiAzonosito').text!=job['config']['reporting_id'] or root.find('.//{'+c.NS+'}bejelentesIdopontja').text!=job['report_timestamp']:raise SecurityBlocked('render_binding_mismatch')
        except Exception:
            with backend.db() as con:con.execute("UPDATE viza_dispatch SET state='blocked',error_code='request_validation_failed',claim_id=NULL,lease_until=NULL WHERE job_id=? AND claim_id=?",(job['id'],job['claim_id']))
            break
        wire=stamp(now);attempt=str(uuid.uuid4())
        with backend.db() as con:
            con.execute('UPDATE properties SET id=id WHERE id=? AND organization_id=?',(job['property_id'],job['organization_id']))
            current=con.execute('SELECT state FROM viza_jobs WHERE id=?',(job['id'],)).fetchone()
            current_config=settings(con,job['organization_id'],job['property_id'])
            current_holds=con.execute('SELECT 1 FROM viza_visit_holds h JOIN viza_job_guests g ON g.arrival_uuid=h.arrival_uuid WHERE g.job_id=?',(job['id'],)).fetchone()
            if not current or current['state']=='superseded_before_submission' or current_holds or not source_matches(backend,con,job) or binding_digest(current_config)!=job['binding_digest']:
                reason='superseded_before_submission' if current and current['state']=='superseded_before_submission' else 'blocked'
                con.execute('UPDATE viza_dispatch SET state=?,error_code=?,claim_id=NULL,lease_until=NULL WHERE job_id=? AND claim_id=?',(reason,'pre_send_source_or_binding_changed',job['id'],job['claim_id']))
                continue
            updated=con.execute("UPDATE viza_dispatch SET state='sending',wire_timestamp=? WHERE job_id=? AND claim_id=? AND state='claimed' AND lease_until>?",(wire,job['id'],job['claim_id'],stamp(now)))
            if not updated.rowcount:continue
            con.execute('UPDATE viza_jobs SET attempts=attempts+1 WHERE id=?',(job['id'],))
            con.execute("UPDATE government_outbox SET status='viza_mock_sending' WHERE id=?",(job['id'],))
            n=con.execute('SELECT attempts FROM viza_jobs WHERE id=?',(job['id'],)).fetchone()['attempts']
            con.execute("INSERT INTO government_delivery_attempts(id,organization_id,outbox_id,system,attempt_no,state,request_hash,created_at) VALUES (?,?,?,'VIZA',?,'sending',?,?)",(attempt,job['organization_id'],job['id'],n,hashlib.sha256(raw).hexdigest(),wire))
            con.execute('INSERT INTO viza_attempts(id,job_id,claim_id,wire_timestamp) VALUES (?,?,?,?)',(attempt,job['id'],job['claim_id'],wire))
        response=None;receipt=None
        try:
            response=transport.exchange(op,raw,binding=binding(job['organization_id'],job['property_id'],job['config']),wire_timestamp=wire)
            receipt=c.parse(op,response)
            if receipt.fogadasIdeje.utcoffset() is None:raise OutcomeUncertain('receipt_time_untrusted')
            with backend.db() as con:state,code=receipt_state(con,job,receipt)
        except DefinitelyNotSent:state,code='retry','definitely_not_sent'
        except PermanentFailure:state,code='rejected','permanent_transport_validation_error'
        except Exception:state,code='uncertain','outcome_unknown';receipt=None
        finish(backend,job,state,code,now,raw=response,receipt=receipt,randint=randint)
        processed+=1
    return processed


def parse_health(status):
    codes=status.allapotKod.split('|')
    if not codes or codes[0] not in ('OK','WARNING','ERROR') or any(x not in FLAGS for x in codes[1:]) or len(codes)!=len(set(codes)):raise c.ContractError('invalid_health_codes')
    if 'CERT-EXPIRED' in codes[1:] and codes[0]!='ERROR':raise c.ContractError('expired_certificate_requires_error_status')
    if status.idoPecset.utcoffset() is None:raise c.ContractError('health_timestamp_offset_required')
    return {'primary':codes[0],'flags':codes[1:],'unsent':status.bekuldetlenUzenetekSzama,'rejected':status.hibasUzenetekSzama,'software_version':status.szoftverVerzio,'server_timestamp':status.idoPecset.isoformat()}


def monitor_once(backend,org,prop,*,selector=None,transport=None,now=None,requested=False):
    now=now or backend.datetime.now(timezone.utc);transport=transport or DisabledOfficialTransport()
    op='bekuldetlenAdatLista' if selector else 'allapotLekerdezes';key=selector or ''
    if selector not in (None,'NEMBEKULDOTT','HIBAS'):raise c.ContractError('invalid_list_selector')
    with backend.db() as con:
        con.execute('UPDATE properties SET id=id WHERE id=? AND organization_id=?',(prop,org))
        cfg=settings(con,org,prop)
        if not cfg:return {'state':'blocked','code':'missing_configuration'}
        if transport.mode!='mock' or backend.APP_ENV!='test':return {'state':'blocked','code':'official_transmission_disabled'}
        bound=binding(org,prop,cfg);fingerprint=binding_digest(cfg)
        con.execute('INSERT OR IGNORE INTO viza_monitor_schedule(property_id,environment,operation,selector,due_at) VALUES (?,?,?,?,?)',(prop,cfg['environment'],op,key,stamp(now)))
        schedule=con.execute('SELECT * FROM viza_monitor_schedule WHERE property_id=? AND environment=? AND operation=? AND selector=?',(prop,cfg['environment'],op,key)).fetchone()
        if schedule['due_at']>stamp(now):return {'state':'not_due'}
        if schedule['lease_until'] and schedule['lease_until']>stamp(now):return {'state':'busy'}
        token=str(uuid.uuid4())
        con.execute('UPDATE viza_monitor_schedule SET claim_id=?,lease_until=? WHERE property_id=? AND environment=? AND operation=? AND selector=?',(token,stamp(now+timedelta(seconds=60)),prop,cfg['environment'],op,key))
    error=None;payload=None
    try:
        dto=c.ListRequest(bekuldetlenAdatTipus=selector) if selector else c.StatusRequest()
        response=transport.exchange(op,c.serialize(op,dto),binding=bound,wire_timestamp=stamp(now))
        parsed=c.parse(op,response)
        if not selector:payload=parse_health(parsed)
        else:
            if parsed.eredmenyKod!='OK':raise c.ContractError('list_result_error')
            items=[]
            with backend.db() as con:
                for item in parsed.bekuldetlenAdat:
                    if item.adatszolgaltatasiAzonosito!=bound.reporting_id:raise c.ContractError('list_property_mismatch')
                    match=con.execute('SELECT j.id FROM viza_jobs j JOIN viza_dispatch d ON d.job_id=j.id WHERE j.id=? AND j.organization_id=? AND j.property_id=? AND d.environment=? AND d.binding_digest=?',(item.uzenetAzonosito,org,prop,bound.environment,fingerprint)).fetchone()
                    items.append({'message_id':item.uzenetAzonosito,'correlation':'matched' if match else 'unknown_message','codes':safe_codes(item.hibaUzenet),'raw_error':item.hibaUzenet})
            payload={'items':items,'limit_reached':len(items)==10000,'delivery_inferred':False}
    except Exception:error='monitor_response_unavailable_or_invalid'
    with backend.db() as con:
        schedule=con.execute('SELECT claim_id FROM viza_monitor_schedule WHERE property_id=? AND environment=? AND operation=? AND selector=?',(prop,bound.environment,op,key)).fetchone()
        if not schedule or schedule['claim_id']!=token:return {'state':'superseded'}
        current=settings(con,org,prop)
        if binding_digest(current)!=fingerprint:error='environment_or_configuration_changed';payload=None
        if payload is not None:
            oid=str(uuid.uuid4())
            con.execute('INSERT INTO viza_observations VALUES (?,?,?,?,?,?,?,?,?,?)',(oid,org,prop,bound.environment,fingerprint,op,key,'mock',stamp(now),backend.encrypt_json(payload)))
            if selector=='HIBAS':
                for item in payload['items']:
                    if item['correlation']=='matched':
                        con.execute("INSERT INTO viza_message_status VALUES (?,'rejected',?) ON CONFLICT(job_id) DO UPDATE SET downstream_state=excluded.downstream_state,observation_id=excluded.observation_id",(item['message_id'],oid))
                        count=con.execute('SELECT COUNT(*) n FROM viza_job_guests WHERE job_id=?',(item['message_id'],)).fetchone()['n']
                        con.execute('UPDATE viza_guest_outcomes SET downstream_state=? WHERE job_id=?',('rejected' if count==1 else 'message_rejected_guest_scope_unknown',item['message_id']))
            # Never update a message to delivered from its absence in either list.
        con.execute('UPDATE viza_monitor_schedule SET due_at=?,claim_id=NULL,lease_until=NULL,last_error=? WHERE property_id=? AND environment=? AND operation=? AND selector=?',
            (stamp(now+timedelta(minutes=cfg['poll_minutes'])),error,prop,bound.environment,op,key))
    return {'state':'mock_observed' if payload is not None else 'unknown','code':error}


def monitoring_worker_once(backend,*,transport=None,now=None):
    now=now or backend.datetime.now(timezone.utc)
    with backend.db() as con:configs=[dict(r) for r in con.execute('SELECT organization_id,property_id FROM viza_settings')]
    for row in configs:monitor_once(backend,row['organization_id'],row['property_id'],transport=transport,now=now)


def render_bound_job(backend,job,credential_root,now,*,credential_reference=None):
    """Property-signed business body only. Outer security/transport remain disabled."""
    from viza_security import property_validation
    if not credential_reference:raise SecurityBlocked('missing_server_credential_binding')
    cfg=job['config'];base=binding(job['organization_id'],job['property_id'],cfg)
    bound=Binding(base.organization_id,base.property_id,base.environment,base.reporting_id,base.endpoint,credential_reference)
    facts=backend.decrypt_json(job['encrypted_facts'])
    validation=property_validation(credential_root,bound,[g['arrival_uuid'] for g in facts['guests']],job['report_timestamp'],now=now)
    header={'uzenetAzonosito':job['id'],'szallashely':{'adatszolgaltatasiAzonosito':cfg['reporting_id'],'szallasNev':cfg['property_name'],
      'szallashelySzolgaltatoAdoszam':cfg['provider_tax'],'szallashelySzolgaltatoNev':cfg['provider_name']},
      'bejelentesIdopontja':job['report_timestamp'],'pmsValidaciosUzenet':validation}
    return capture.request_for_snapshot(backend,job,header)
