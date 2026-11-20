"""Encrypted, append-only NTAK evidence; never a sender or second queue."""
import base64
import hashlib
import json
import sys
import uuid
from datetime import date, datetime
from functools import lru_cache
from ntak_contracts import contracts, XSD
from ntak_protocol import ReportingBlocked


def canonical(value):
    return json.dumps(value,ensure_ascii=False,sort_keys=True,separators=(',',':'),allow_nan=False)


def backend():
    # Called only by the initialized application, never imports/starts it.
    return sys.modules['app']


def digest(value):
    return hashlib.sha256(value).hexdigest()


def migrate(con, now):
    con.executescript("""
    CREATE TABLE IF NOT EXISTS ntak_evidence_versions (
      job_id TEXT PRIMARY KEY REFERENCES ntak_jobs(id), organization_id TEXT NOT NULL,
      property_id TEXT NOT NULL,environment TEXT NOT NULL,encrypted_snapshot TEXT NOT NULL,
      snapshot_hash TEXT NOT NULL,origin TEXT NOT NULL,created_at TEXT NOT NULL
    );
    CREATE TABLE IF NOT EXISTS ntak_evidence_events (
      id TEXT PRIMARY KEY,job_id TEXT NOT NULL REFERENCES ntak_evidence_versions(job_id),
      attempt_id TEXT,phase TEXT NOT NULL,encrypted_event TEXT NOT NULL,
      content_hash TEXT NOT NULL,created_at TEXT NOT NULL,UNIQUE(attempt_id,phase)
    );
    CREATE INDEX IF NOT EXISTS idx_ntak_evidence_events ON ntak_evidence_events(job_id,created_at);
    CREATE TABLE IF NOT EXISTS ntak_evidence_links (
      child_id TEXT NOT NULL REFERENCES ntak_evidence_versions(job_id),
      parent_id TEXT NOT NULL REFERENCES ntak_evidence_versions(job_id),relation TEXT NOT NULL,
      PRIMARY KEY(child_id,parent_id,relation)
    );
    CREATE TABLE IF NOT EXISTS ntak_replay_requests (
      job_id TEXT PRIMARY KEY REFERENCES ntak_evidence_versions(job_id),request_id TEXT NOT NULL,
      actor_id TEXT NOT NULL,encrypted_reason TEXT NOT NULL,created_at TEXT NOT NULL
    );
    CREATE TABLE IF NOT EXISTS ntak_evidence_access (
      id TEXT PRIMARY KEY,job_id TEXT NOT NULL REFERENCES ntak_evidence_versions(job_id),
      actor_id TEXT NOT NULL,action TEXT NOT NULL,encrypted_details TEXT NOT NULL,created_at TEXT NOT NULL
    );
    """)
    for table in ('ntak_evidence_versions','ntak_evidence_events','ntak_evidence_links','ntak_replay_requests','ntak_evidence_access'):
        if con.backend=='sqlite':
            con.raw.execute(f"CREATE TRIGGER IF NOT EXISTS {table}_immutable BEFORE UPDATE ON {table} BEGIN SELECT RAISE(ABORT,'NTAK evidence is immutable'); END")
            con.raw.execute(f"CREATE TRIGGER IF NOT EXISTS {table}_no_delete BEFORE DELETE ON {table} BEGIN SELECT RAISE(ABORT,'NTAK evidence is immutable'); END")
        else:
            con.raw.execute("CREATE OR REPLACE FUNCTION ntak_evidence_no_update() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'NTAK evidence is immutable'; END; $$")
            con.raw.execute(f'DROP TRIGGER IF EXISTS {table}_immutable ON {table}')
            con.raw.execute(f'CREATE TRIGGER {table}_immutable BEFORE UPDATE ON {table} FOR EACH ROW EXECUTE FUNCTION ntak_evidence_no_update()')
            con.raw.execute(f'DROP TRIGGER IF EXISTS {table}_no_delete ON {table}')
            con.raw.execute(f'CREATE TRIGGER {table}_no_delete BEFORE DELETE ON {table} FOR EACH ROW EXECUTE FUNCTION ntak_evidence_no_update()')
    con.execute('INSERT OR IGNORE INTO schema_migrations(version,name,applied_at) VALUES (3089,?,?)',('ntak_encrypted_evidence',now))
    # Only retained facts can be archived: never fabricate lost historical wire data.
    for row in con.execute('SELECT * FROM ntak_jobs WHERE id NOT IN (SELECT job_id FROM ntak_evidence_versions)').fetchall():
        capture(con,row,now,origin='legacy_retained_facts')


def capture(con, job, now, *, origin='enqueue'):
    snap={k:job[k] for k in ('id','organization_id','property_id','environment','operation','logical_key','message_id','created_at')}
    snap.update(configuration=json.loads(job['configuration_json']),payload=json.loads(job['payload_json']))
    raw=canonical(snap)
    prior=con.execute('SELECT snapshot_hash FROM ntak_evidence_versions WHERE job_id=?',(job['id'],)).fetchone()
    if prior:
        if prior['snapshot_hash']!=digest(raw.encode()):raise ReportingBlocked('immutable_evidence_conflict')
        return
    con.execute('INSERT INTO ntak_evidence_versions VALUES (?,?,?,?,?,?,?,?)',(job['id'],job['organization_id'],job['property_id'],job['environment'],backend().encrypt_json(snap),digest(raw.encode()),origin,now))


def link(con, child, parent, relation, now):
    rows=[]
    for jid in (child,parent):
        row=con.execute('SELECT * FROM ntak_jobs WHERE id=?',(jid,)).fetchone()
        if not row:raise ReportingBlocked('evidence_lineage_missing')
        capture(con,row,now)
        rows.append(row)
    if any(rows[0][k]!=rows[1][k] for k in ('organization_id','property_id','environment')):
        raise ReportingBlocked('evidence_scope_mismatch')
    con.execute('INSERT OR IGNORE INTO ntak_evidence_links VALUES (?,?,?)',(child,parent,relation))


def event(con, job, attempt, phase, content, now):
    raw=canonical(content)
    con.execute('INSERT INTO ntak_evidence_events VALUES (?,?,?,?,?,?,?)',
                (str(uuid.uuid4()),job,attempt,phase,backend().encrypt_json(content),digest(raw.encode()),now))


def request(con, job, attempt, operation, xml, now):
    capture(con,job,now)
    kind='verification' if operation=='verification' else 'explicit_protocol_resend' if job['protocol_resends']==1 else 'correction' if job['protocol_resends']==2 else 'retry' if job['attempts'] else 'original'
    event(con,job['id'],attempt,'request',{'operation':operation,'kind':kind,'wire_base64':base64.b64encode(xml).decode(),
        'wire_hash':digest(xml),'processing_id':job['processing_id'],'attempt_no':job['attempts']+1,
        'transport':'injected_offline','possible_transmission':True},now)


def received(raw):
    if not isinstance(raw,bytes):return {'invalid_response_type':True}
    result={'wire_hash':digest(raw),'byte_count':len(raw)}
    if len(raw)<=8*1024*1024:result['wire_base64']=base64.b64encode(raw).decode()
    else:result['over_contract_size_limit']=True
    return result


def access(con, job, actor, action, details, now):
    con.execute('INSERT INTO ntak_evidence_access VALUES (?,?,?,?,?,?)',
                (str(uuid.uuid4()),job,actor,action,backend().encrypt_json(details),now))


def replay(con, job, request_id, actor, reason, now):
    previous=con.execute('SELECT * FROM ntak_replay_requests WHERE job_id=?',(job['id'],)).fetchone()
    if previous:
        if previous['request_id']!=request_id:raise ReportingBlocked('replay_already_recorded')
        if previous['actor_id']!=actor or backend().decrypt_json(previous['encrypted_reason'])['reason']!=reason:
            raise ReportingBlocked('replay_request_conflict')
        return {'queued':True,'duplicate':True,'job_id':job['id'],'transmission_enabled':False}
    # This acknowledges an existing, protocol-authorized queue item. Never creates
    # a new job, clears an outcome, changes a message ID or rearms an uncertain send.
    if job['state']!='retry' or job['protocol_resends']!=1 or job['processing_id']:
        raise ReportingBlocked('replay_not_permitted')
    permitted=False
    for row in con.execute("SELECT encrypted_event FROM ntak_evidence_events WHERE job_id=? AND phase='outcome'",(job['id'],)):
        facts=backend().decrypt_json(row['encrypted_event'])
        if facts.get('protocol_state')=='resend_required' and facts.get('operation')=='verification' and 'FeldolgozasHiba' not in facts.get('codes',[]):permitted=True
    if not permitted:raise ReportingBlocked('replay_evidence_missing')
    con.execute('INSERT INTO ntak_replay_requests VALUES (?,?,?,?,?)',(job['id'],request_id,actor,backend().encrypt_json({'reason':reason}),now))
    return {'queued':True,'duplicate':False,'job_id':job['id'],'transmission_enabled':False}


@lru_cache(maxsize=1)
def enum_values():
    return {n.get('value') for _,schema,_ in contracts().values() for n in schema.iter('{'+XSD+'}enumeration')}


def redact(value, key=''):
    # Names, guest IDs, birth facts, free text, booking refs and hashes are unnecessary
    # in a routine export. Exact protocol bytes remain encrypted on the server.
    if any(part in key.lower() for part in ('vendeg','szuletes','dokument','nev','iranyito','lakcim','hash','salt','token','secret','credential','password','private','scan')):
        return '[omitted]'
    if isinstance(value,dict):
        names={n.get('name') for _,schema,_ in contracts().values() for n in schema.iter('{'+XSD+'}element')}
        return {k:redact(v,k) for k,v in sorted(value.items()) if k in names}
    if isinstance(value,list):return [redact(v,key) for v in value]
    if isinstance(value,str):
        if value in enum_values():return value
        if any(part in key.lower() for part in ('nap','datum','idopont')):
            try:
                if len(value)==10:date.fromisoformat(value)
                else:datetime.fromisoformat(value)
                return value if len(value)<=40 else '[omitted]'
            except ValueError:pass
        return '[omitted]'
    if value is None or isinstance(value,(bool,int,float)):return value
    return '[omitted]'


def safe_code(code):
    import ntak_diagnostics
    safe={'outcome_unknown','soap_fault','signature_profile_unresolved','information_response_contract_unresolved',
          'immutable_evidence_conflict','worker_interrupted','remote_validation_error'}
    return code if code is None or code in ntak_diagnostics.CATALOG or code in ntak_diagnostics.LOCAL_SECURITY or code in safe else 'local_reporting_blocker'


def export(con, job):
    scope=tuple(job[k] for k in ('organization_id','property_id','environment'))
    pending={job['id']};seen=set();versions=[];events=[];links=[];diagnostics=[];attempts=[];actions=[]
    while pending:
        jid=min(pending);pending.remove(jid)
        if jid in seen:continue
        seen.add(jid)
        row=con.execute('SELECT * FROM ntak_evidence_versions WHERE job_id=? AND organization_id=? AND property_id=? AND environment=?',(jid,*scope)).fetchone()
        if not row:raise ReportingBlocked('evidence_scope_or_history_missing')
        facts=backend().decrypt_json(row['encrypted_snapshot'])
        if digest(canonical(facts).encode())!=row['snapshot_hash']:raise ReportingBlocked('evidence_integrity_failure')
        live=con.execute('SELECT state,error_code,processing_id,attempts FROM ntak_jobs WHERE id=?',(jid,)).fetchone()
        versions.append({'job_id':jid,'operation':facts['operation'],'message_id':facts['message_id'],
            'logical_version_hash':digest(facts['logical_key'].encode()),'created_at':facts['created_at'],'capture_origin':row['origin'],
            'snapshot_hash':row['snapshot_hash'],'reporting_facts':redact(facts['payload']),
            'state':live['state'],'error_code':safe_code(live['error_code']),'current_processing_id':live['processing_id'],
            'attempt_count':live['attempts']})
        for edge in con.execute('SELECT * FROM ntak_evidence_links WHERE child_id=? OR parent_id=?',(jid,jid)):
            e=dict(edge)
            if e not in links:links.append(e)
            pending.update((e['child_id'],e['parent_id']))
        for attempt in con.execute("SELECT id,attempt_no,state,request_hash,created_at FROM government_delivery_attempts WHERE outbox_id=? AND organization_id=? AND system='NTAK'",(jid,scope[0])):
            attempts.append({'job_id':jid,**dict(attempt)})
        for item in con.execute('SELECT * FROM ntak_evidence_events WHERE job_id=? ORDER BY created_at,id',(jid,)):
            content=backend().decrypt_json(item['encrypted_event'])
            if digest(canonical(content).encode())!=item['content_hash']:raise ReportingBlocked('evidence_integrity_failure')
            # Explicit allowlist: no XML, remote prose, submitted values or arbitrary extras.
            safe={k:content[k] for k in ('operation','kind','wire_hash','processing_id','attempt_no','transport','possible_transmission','state','protocol_state','codes','lease_current') if k in content}
            events.append({'job_id':jid,'attempt_id':item['attempt_id'],'event_id':item['id'],'phase':item['phase'],
                           'created_at':item['created_at'],'evidence_hash':item['content_hash'],**safe})
        for item in con.execute("SELECT * FROM ntak_evidence_access WHERE job_id=? AND action='recovery'",(jid,)):
            details=backend().decrypt_json(item['encrypted_details'])
            action={'job_id':jid,'actor_id':item['actor_id'],'created_at':item['created_at'],'kind':'operator_recovery','action':details['action'] if details.get('action') in ('record_processing_id','retry_after_resolution') else 'unknown'}
            if action['action']=='record_processing_id':action['processing_id']=str(uuid.UUID(details['processing_id']))
            actions.append(action)
        for item in con.execute('SELECT request_id,actor_id,created_at FROM ntak_replay_requests WHERE job_id=?',(jid,)):
            actions.append({'job_id':jid,'kind':'protocol_replay_acknowledgement',**dict(item)})
        for item in con.execute('SELECT attempt_id,phase,diagnostics_json,created_at FROM ntak_diagnostic_results WHERE job_id=? AND organization_id=? AND property_id=?',(jid,*scope[:2])):
            diagnostics.append({'job_id':jid,'attempt_id':item['attempt_id'],'phase':item['phase'],
                'created_at':item['created_at'],'diagnostics':json.loads(item['diagnostics_json'])})
    return {'format':'delvane.ntak.evidence','format_version':1,
        'label':'Delvane diagnostic/evidence package; not an officially accepted report',
        'property_id':job['property_id'],'environment':job['environment'],'root_job_id':job['id'],
        'transmission_enabled':False,'official_acceptance_confirmed':False,
        'provenance':'Local preparation and injected offline transport evidence only; receipt is not processing success',
        'raw_protocol':'Omitted from export; retained encrypted on server when captured',
        'versions':sorted(versions,key=lambda x:x['job_id']),
        'lineage':sorted(links,key=lambda x:(x['child_id'],x['parent_id'],x['relation'])),
        'attempts':sorted(attempts,key=lambda x:(x['job_id'],x['attempt_no'],x['id'])),
        'operator_actions':sorted(actions,key=lambda x:(x['created_at'],x['job_id'],x['kind'])),
        'history_completeness':'No wire evidence is reconstructed for attempts predating capture; missing replies remain unknown',
        'events':sorted(events,key=lambda x:(x['created_at'],x['event_id'])),
        'diagnostics':sorted(diagnostics,key=lambda x:(x['created_at'],x['attempt_id']))}
