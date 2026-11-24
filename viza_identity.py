"""Encrypted append-only VIZA field provenance beside existing guest identity storage."""
from datetime import date
import json,uuid
from fastapi import APIRouter,Cookie,HTTPException,Request
from pydantic import Field
import viza_contracts as contract

EXTRA=('vizumEngedelySzam','beutazasDatuma','beutazasHelye')
ALLOWED=set(contract.FIELDS+EXTRA)
class IdentityEdit(contract.DTO):
    manual:dict[str,str|None]=Field(default_factory=dict)
    reason:str=Field(min_length=3,max_length=500)
    third_country_applicable:bool|None=None
    confirm_ambiguities:bool=False


def migrate(con,now):
    con.executescript('''CREATE TABLE IF NOT EXISTS guest_identity_sources (
      id TEXT PRIMARY KEY,guest_record_id TEXT NOT NULL REFERENCES guest_records(id),
      organization_id TEXT NOT NULL,property_id TEXT NOT NULL,kind TEXT NOT NULL,
      encrypted_payload TEXT NOT NULL,actor_id TEXT NOT NULL,created_at TEXT NOT NULL,
      revision INTEGER NOT NULL,UNIQUE(guest_record_id,revision));
    CREATE TABLE IF NOT EXISTS legacy_guest_identity_archives(guest_record_id TEXT NOT NULL,content_hash TEXT NOT NULL,encrypted_payload TEXT NOT NULL,created_at TEXT NOT NULL,PRIMARY KEY(guest_record_id,content_hash));
    CREATE INDEX IF NOT EXISTS idx_identity_sources_guest ON guest_identity_sources(guest_record_id,revision);
''')
    if con.backend=='sqlite':
        for operation in ('UPDATE','DELETE'):
            con.raw.execute(f"CREATE TRIGGER IF NOT EXISTS identity_sources_no_{operation.lower()} BEFORE {operation} ON guest_identity_sources BEGIN SELECT RAISE(ABORT,'Identity source history is immutable'); END")
    else:
        con.raw.execute("CREATE OR REPLACE FUNCTION viza_identity_no_mutation() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'Identity source history is immutable'; END; $$")
        con.raw.execute('DROP TRIGGER IF EXISTS identity_sources_immutable ON guest_identity_sources')
        con.raw.execute('CREATE TRIGGER identity_sources_immutable BEFORE UPDATE OR DELETE ON guest_identity_sources FOR EACH ROW EXECUTE FUNCTION viza_identity_no_mutation()')
    con.execute('INSERT OR IGNORE INTO schema_migrations(version,name,applied_at) VALUES (3085,?,?)',('encrypted_identity_provenance',now))


def scope(con,org,gid):
    row=con.execute('''SELECT g.*,r.property_id,r.arrival_date FROM guest_records g JOIN reservations r ON r.id=g.reservation_id
      WHERE g.id=? AND g.organization_id=? AND r.organization_id=?''',(gid,org,org)).fetchone()
    if not row:raise HTTPException(404,'Guest record not found')
    return dict(row)


def project(backend,con,gid):
    original={};manual={};provenance={};ambiguities=[];applicable=None;history=[];contexts=[];submission=None
    for row in con.execute('SELECT * FROM guest_identity_sources WHERE guest_record_id=? ORDER BY revision',(gid,)):
        data=backend.decrypt_json(row['encrypted_payload'])
        if 'guest_submission' in data:submission=data['guest_submission']
        history.append({'id':row['id'],'kind':row['kind'],'revision':row['revision'],'created_at':row['created_at'],'actor_id':row['actor_id']})
        assigned=set()
        if row['kind']=='scan':
            if data.get('reader_context'):contexts.append(data['reader_context'])
            # A later reader cannot rewrite an earlier reader's original value.
            for k,v in data['fields'].items():
                if k not in original:
                    original[k]=v
                    if k not in manual:assigned.add(k)
            ambiguities+=data.get('ambiguities',[])
        else:
            assigned=set(data['fields'])
            manual.update(data['fields'])
            if data.get('third_country_applicable') is not None:applicable=data['third_country_applicable']
            if data.get('confirm_ambiguities'):ambiguities=[]
        for k in assigned:
            provenance[k]={'source':row['kind'],'actor_id':row['actor_id'],'timestamp':row['created_at'],'reason':data.get('reason',''),'revision':row['revision']}
    return {'reader_contexts':contexts,'original':original,'manual':manual,'effective':{**original,**manual},'provenance':provenance,'history':history,
            'third_country_applicable':applicable,'ambiguities':sorted(set(ambiguities)),
            'guest_submission':submission,
            'original_state':'retained' if original else 'unknown_not_reconstructed'}


def append(backend,con,row,fields,actor,kind,*,reason='',third_country_applicable=None,ambiguities=None,confirm_ambiguities=False,reader_context=None,guest_submission=None):
    context=reader_context or {}
    if set(context)-{'mrz_birth_raw','mrz_format','scan_side'} or any(not isinstance(v,str) or len(v)>30 for v in context.values()):raise HTTPException(422,'Invalid reader context')
    if set(fields)-ALLOWED:raise HTTPException(422,'Unsupported identity field')
    # Values are untrusted reader/user input; reject objects/images and excessive data.
    if any(v is not None and (not isinstance(v,str) or len(v)>1000) for v in fields.values()):raise HTTPException(422,'Invalid identity value')
    allowed_ambiguities={'mrz_birth_century_confirmation','country_mapping_requires_review'}|{'conflicting_scan:'+k for k in ALLOWED}
    if len(ambiguities or [])>len(allowed_ambiguities) or set(ambiguities or [])-allowed_ambiguities:raise HTTPException(422,'Unsupported scanner review flag')
    before=project(backend,con,row['id'])
    fields=dict(fields)
    if kind=='scan':
        if all(before['original'].get(k)==v for k,v in fields.items()) and not ambiguities:return None
        ambiguities=list(ambiguities or [])+[('conflicting_scan:'+k) for k,v in fields.items() if k in before['original'] and before['original'][k]!=v]
    if kind!='scan':
        for a,b in contract.PAIRS:
            if a in fields or b in fields:
                fields.setdefault(a,before['effective'].get(a));fields.setdefault(b,before['effective'].get(b))
    # Keep raw scanner country; only convert in readiness/serialization, never in history.
    rev=con.execute('SELECT COALESCE(MAX(revision),0)+1 n FROM guest_identity_sources WHERE guest_record_id=?',(row['id'],)).fetchone()['n']
    data={'fields':fields,'reason':reason,'third_country_applicable':third_country_applicable,'ambiguities':ambiguities or [],'confirm_ambiguities':confirm_ambiguities,'reader_context':context}
    if guest_submission is not None:data['guest_submission']=guest_submission
    con.execute('INSERT INTO guest_identity_sources VALUES (?,?,?,?,?,?,?,?,?)',(str(uuid.uuid4()),row['id'],row['organization_id'],row['property_id'],kind,backend.encrypt_json(data),actor,backend.now_iso(),rev))
    if kind!='scan':
        con.execute("UPDATE guest_identity_verifications SET status='needs_review',verified_by=NULL,verified_at=NULL WHERE guest_record_id=?",(row['id'],))
    return rev


def readiness(backend,con,gid,arrival_day):
    p=project(backend,con,gid);effective=dict(p['effective']);errors=list(p['ambiguities'])
    raw=effective.get('allampolgarsagKod')
    try:effective['allampolgarsagKod']=contract.country(raw)
    except contract.ContractError:errors.append('country_mapping_requires_review')
    normalized_original=dict(p['original']);normalized_manual=dict(p['manual'])
    if 'allampolgarsagKod' in normalized_manual:normalized_manual['allampolgarsagKod']=effective.get('allampolgarsagKod')
    else:normalized_original['allampolgarsagKod']=effective.get('allampolgarsagKod')
    errors+=contract.source_identity_errors(normalized_original,normalized_manual,arrival_day)
    for group in ('original','manual'):
        try:contract.Person.model_validate({k:v for k,v in p[group].items() if k in contract.FIELDS})
        except ValueError:errors.append('invalid_'+group+'_source_fields')
        errors.extend(contract.identity_errors_lengths(p[group]))
        for k in ('nem','okmanyTipus'):
            if p[group].get(k)=='':errors.append('empty_enum:'+k)
    if p['third_country_applicable'] is None:errors.append('third_country_applicability_review')
    elif p['third_country_applicable']:
        for k in EXTRA:
            if not effective.get(k):errors.append('missing:'+k)
    entry=effective.get('beutazasDatuma')
    if entry:
        try:
            if date.fromisoformat(entry)>backend.date.today():errors.append('entry_date_future')
        except ValueError:errors.append('entry_date')
    verified=con.execute('SELECT status FROM guest_identity_verifications WHERE guest_record_id=?',(gid,)).fetchone()
    if not verified or verified['status']!='verified':errors.append('owner_verification_required')
    return {'ready':not errors,'blockers':sorted(set(errors)),'effective':effective,'original':p['original'],'manual':p['manual'],
            'third_country_applicable':p['third_country_applicable']}


def ingest(backend,con,row,scanned,manual,actor,*,ambiguities=None,reader_context=None,guest_submission=None):
    if scanned:append(backend,con,row,scanned,actor,'scan',ambiguities=ambiguities,reader_context=reader_context)
    if manual or guest_submission is not None:
        append(backend,con,row,manual,actor,'manual',reason='Guest reviewed registration fields',guest_submission=guest_submission)


def install(backend):
    router=APIRouter(prefix='/api/registration/records/{guest_id}/viza-identity')
    def access(con,gid,session):
        user=backend.require_user(session);backend.require_roles(user,'owner','manager')
        row=scope(con,user['organization_id'],gid)
        backend._lock_reservation(con,row['reservation_id'],user['organization_id'])
        return user,row
    @router.get('')
    def get(guest_id:str,arrival_date:date|None=None,rosa_session:str|None=Cookie(default=None)):
        with backend.db() as con:
            user,row=access(con,guest_id,rosa_session)
            projected=project(backend,con,guest_id)
            projected.pop('guest_submission')
            return {**projected,'readiness':readiness(backend,con,guest_id,arrival_date or date.fromisoformat(row['arrival_date'])),
                    'assessment_date_source':'explicit_actual_arrival' if arrival_date else 'planned_preview_only'}
    @router.get('/sources')
    def sources(guest_id:str,rosa_session:str|None=Cookie(default=None)):
        with backend.db() as con:
            user,row=access(con,guest_id,rosa_session)
            return [{'id':r['id'],'kind':r['kind'],'actor_id':r['actor_id'],'created_at':r['created_at'],'revision':r['revision'],
                'data':backend.decrypt_json(r['encrypted_payload'])} for r in con.execute('SELECT * FROM guest_identity_sources WHERE guest_record_id=? ORDER BY revision',(guest_id,))]
    @router.put('')
    def put(guest_id:str,body:IdentityEdit,request:Request,rosa_session:str|None=Cookie(default=None)):
        with backend.db() as con:
            user,row=access(con,guest_id,rosa_session)
            return apply_edit(backend,con,user,row,body)
    backend.app.include_router(router)

def apply_edit(backend,con,user,row,body):
    guest_id=row['id']
    effective={**project(backend,con,guest_id)['effective'],**body.manual}
    if effective.get('allampolgarsagKod'):
        try:contract.country(effective['allampolgarsagKod'])
        except contract.ContractError:raise HTTPException(422,'Country mapping requires an explicit accepted two-letter code')
    try:contract.Person.model_validate({k:v for k,v in effective.items() if k in contract.FIELDS})
    except ValueError:raise HTTPException(422,'Invalid structured identity fields') from None
    errors=contract.identity_errors(effective,backend.date.today())
    if any(e.startswith('length:') for e in errors):raise HTTPException(422,'Identity field length exceeded')
    if effective.get('szuletesiDatum') and 'birth_date' in errors:raise HTTPException(422,'Birth date outside rolling 110-year range')
    revision=append(backend,con,row,body.manual,user['id'],'manual',reason=body.reason,
         third_country_applicable=body.third_country_applicable,confirm_ambiguities=body.confirm_ambiguities)
    values=project(backend,con,guest_id)['effective']
    vault_merge(backend,con,guest_id,user['organization_id'],{target:values[source] for source,target in (('szuletesiDatum','date_of_birth'),('okmanyAzonositoSzam','document_number')) if source in values})
    reference=date.fromisoformat(row['arrival_date'])
    # Use the same normalized, source-aware assessment as VIZA readiness.
    # Reader alpha3 codes remain immutable originals; only the operational
    # projection uses the unambiguous accepted alpha2 code.
    assessment=readiness(backend,con,guest_id,reference)
    required=set(assessment['blockers'])-{'owner_verification_required'}
    complete=not required
    con.execute('UPDATE guest_records SET completeness=?,nationality=COALESCE(?,nationality),document_type=COALESCE(?,document_type) WHERE id=?',('complete' if complete else 'incomplete',assessment['effective'].get('allampolgarsagKod'),values.get('okmanyTipus'),guest_id))
    con.execute('''INSERT INTO guest_identity_verifications(guest_record_id,organization_id,reservation_id,status,updated_at)
      VALUES (?,?,?,'needs_review',?) ON CONFLICT(guest_record_id) DO UPDATE SET status='needs_review',verified_by=NULL,verified_at=NULL,updated_at=excluded.updated_at''',(guest_id,user['organization_id'],row['reservation_id'],backend.now_iso()))
    backend._sync_registration(con,row['reservation_id'],user['organization_id'])
    # Audit contains identifiers only, never identity values or correction reasons.
    backend.audit_event(con,user['organization_id'],'guest.identity.reviewed','Identity fields reviewed.',actor_user_id=user['id'],entity_type='guest_record',entity_id=guest_id,metadata={'revision':revision,'fields':sorted(body.manual)})
    return {'ok':True,'revision':revision,'verification_status':'needs_review'}


def vault_merge(backend,con,gid,org,values):
    previous=vault_data(backend,con,gid,org)
    payload={**previous,**values}
    con.execute('''INSERT INTO sensitive_guest_data(guest_record_id,organization_id,encrypted_payload,updated_at) VALUES (?,?,?,?)
      ON CONFLICT(guest_record_id) DO UPDATE SET encrypted_payload=excluded.encrypted_payload,updated_at=excluded.updated_at''',(gid,org,backend.encrypt_json(payload),backend.now_iso()))


def compatibility(backend,con,row):
    data=dict(row)
    protected=vault_data(backend,con,data['id'],data['organization_id'])
    for k in ('date_of_birth','document_number'):
        if k in protected:data[k]=protected[k]
    return data


def vault_data(backend,con,gid,org):
    row=con.execute('SELECT encrypted_payload FROM sensitive_guest_data WHERE guest_record_id=? AND organization_id=?',(gid,org)).fetchone()
    return backend.decrypt_json(row['encrypted_payload']) if row else {}


def protect_legacy(backend,con):
    # Preserve old mutable facts as legacy values, explicitly NOT scanner originals.
    for row in con.execute('SELECT * FROM guest_records WHERE date_of_birth IS NOT NULL OR document_number IS NOT NULL').fetchall():
        fields={k:row[k] for k in ('date_of_birth','document_number') if row[k] is not None}
        import hashlib
        previous=con.execute('SELECT encrypted_payload FROM sensitive_guest_data WHERE guest_record_id=?',(row['id'],)).fetchone()
        preserved={'legacy_mutable_record':dict(row),'previous_vault':backend.decrypt_json(previous['encrypted_payload']) if previous else {}}
        digest=hashlib.sha256(json.dumps(preserved,sort_keys=True).encode('utf8')).hexdigest()
        con.execute('INSERT OR IGNORE INTO legacy_guest_identity_archives VALUES (?,?,?,?)',(row['id'],digest,backend.encrypt_json(preserved),backend.now_iso()))
        vault_merge(backend,con,row['id'],row['organization_id'],fields)
        con.execute('UPDATE guest_records SET date_of_birth=NULL,document_number=NULL WHERE id=?',(row['id'],))
    for row in con.execute('SELECT id,payload_json FROM government_outbox').fetchall():
        try:data=json.loads(row['payload_json'])
        except (ValueError,TypeError):continue
        if 'guest_records' in data:
            con.execute('UPDATE government_outbox SET payload_json=? WHERE id=?',(json.dumps({'encrypted_legacy_payload':backend.encrypt_json(data)}),row['id']))
    for row in con.execute("SELECT id,request_preview FROM government_test_runs WHERE system='VIZA'").fetchall():
        raw=row['request_preview'] or ''
        if raw and not raw.startswith('encrypted:'):
            con.execute('UPDATE government_test_runs SET request_preview=? WHERE id=?',('encrypted:'+backend.encrypt_json({'preview':raw}),row['id']))
