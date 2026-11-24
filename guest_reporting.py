"""Encrypted, versioned operational guest profile and property-isolated hash lifecycle."""
from datetime import date
import json
import uuid
import re
from fastapi import APIRouter,Cookie,HTTPException,Request
from pydantic import BaseModel,ConfigDict,Field
from ntak_protocol import guest_hash,ReportingBlocked
from ntak_countries import COUNTRIES

IFA_REASONS={'KOTELES':'Taxable','im1':'Under 18','im2':'Inpatient or social institution care',
 'im3':'Education or vocational training','im4':'Public service obligation',
 'im5':'Authority or court measure','im6':'Local business or employment',
 'im8':'Holiday home ownership or eligible relatives','im9':'Religious activity',
 'im10':'Local residence'}


def migrate(con,now):
    con.executescript('''CREATE TABLE IF NOT EXISTS ntak_property_salts (
      property_id TEXT PRIMARY KEY REFERENCES properties(id),organization_id TEXT NOT NULL,
      encrypted_salt TEXT NOT NULL,created_at TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS guest_reporting_profiles (
      id TEXT PRIMARY KEY,guest_record_id TEXT NOT NULL REFERENCES guest_records(id),
      organization_id TEXT NOT NULL,property_id TEXT NOT NULL,effective_from TEXT NOT NULL,
      encrypted_payload TEXT NOT NULL,source TEXT NOT NULL,reason TEXT NOT NULL,
      actor_id TEXT NOT NULL,created_at TEXT NOT NULL,revision INTEGER NOT NULL, UNIQUE(guest_record_id,revision));
    CREATE INDEX IF NOT EXISTS idx_guest_reporting_profile ON guest_reporting_profiles(guest_record_id,effective_from,created_at);
    ''')
    con.execute('INSERT OR IGNORE INTO schema_migrations(version,name,applied_at) VALUES (?,?,?)',(3077,'guest_reporting_profiles_and_permanent_salts',now))


class Profile(BaseModel):
    model_config=ConfigDict(extra='forbid',str_strip_whitespace=True)
    country_of_residence:str=Field(pattern='^[A-Z]{2}$')
    nationality_country:str|None=None
    postal_code:str=Field(min_length=1,max_length=30)
    full_name:str=Field(min_length=2,max_length=255)
    date_of_birth:date
    birth_place:str=Field(min_length=1,max_length=255)
    birth_name:str=Field(default='',max_length=255)
    sex:str
    ifa_status:str
    effective_from:date
    reason:str=Field(min_length=3,max_length=500)
    source:str='manual'


def profile_on(backend,con,gid,day):
    row=con.execute('''SELECT * FROM guest_reporting_profiles WHERE guest_record_id=? AND effective_from<=?
      ORDER BY effective_from DESC,revision DESC LIMIT 1''',(gid,str(day))).fetchone()
    return (backend.decrypt_json(row['encrypted_payload']),dict(row)) if row else (None,None)


def identity_for_submission(backend,con,org,prop,gid,*,canonical_identity=None):
    """Freeze once at actual reporting use. Unknown normalization never guessed.

    canonical_identity is an internal approved normalization adapter result, never
    accepted through owner HTTP APIs. Future stay/closing serializers must call
    this inside their submission transaction after validating guest/property scope.
    """
    rec=con.execute('''SELECT g.id FROM guest_records g JOIN reservations r ON r.id=g.reservation_id
      WHERE g.id=? AND g.organization_id=? AND r.organization_id=? AND r.property_id=?''',(gid,org,org,prop)).fetchone()
    if not rec:raise ReportingBlocked('guest_property_mismatch')
    con.execute('UPDATE properties SET id=id WHERE id=? AND organization_id=?',(prop,org))
    existing=con.execute('SELECT reporting_id FROM ntak_guest_ids WHERE organization_id=? AND property_id=? AND guest_record_id=?',(org,prop,gid)).fetchone()
    if existing:return existing['reporting_id']
    if canonical_identity is None:raise ReportingBlocked('identity_normalization_unresolved')
    import bcrypt
    row=con.execute('SELECT encrypted_salt FROM ntak_property_salts WHERE property_id=? AND organization_id=?',(prop,org)).fetchone()
    if row:salt=backend.decrypt_json(row['encrypted_salt'])['salt'].encode('ascii')
    else:
        salt=bcrypt.gensalt(rounds=10,prefix=b'2a')
        con.execute('INSERT INTO ntak_property_salts(property_id,organization_id,encrypted_salt,created_at) VALUES (?,?,?,?)',(prop,org,backend.encrypt_json({'salt':salt.decode('ascii')}),backend.now_iso()))
    reporting_id=guest_hash(canonical_identity,salt)
    con.execute('INSERT INTO ntak_guest_ids(organization_id,property_id,guest_record_id,reporting_id,created_at) VALUES (?,?,?,?,?)',(org,prop,gid,reporting_id,backend.now_iso()))
    return reporting_id


def install(backend):
    router=APIRouter(prefix='/api/registration/records/{guest_id}/reporting-profile')
    def access(con,gid,session):
        user=backend.require_user(session);backend.require_roles(user,'owner','manager')
        row=con.execute('''SELECT g.*,r.property_id FROM guest_records g JOIN reservations r ON r.id=g.reservation_id
          WHERE g.id=? AND g.organization_id=? AND r.organization_id=?''',(gid,user['organization_id'],user['organization_id'])).fetchone()
        if not row:raise HTTPException(404,'Guest record not found')
        backend._lock_reservation(con,row['reservation_id'],user['organization_id'])
        return user,row
    @router.get('')
    def get(guest_id:str,business_date:date,rosa_session:str|None=Cookie(default=None)):
        with backend.db() as con:
            user,row=access(con,guest_id,rosa_session)
            import viza_identity
            row=viza_identity.compatibility(backend,con,row)
            profile,revision=profile_on(backend,con,guest_id,business_date)
            history=[{k:r[k] for k in ('id','effective_from','source','reason','actor_id','created_at')} for r in con.execute('SELECT * FROM guest_reporting_profiles WHERE guest_record_id=? ORDER BY effective_from,created_at',(guest_id,))]
            frozen=con.execute('SELECT reporting_id FROM ntak_guest_ids WHERE guest_record_id=? AND organization_id=? AND property_id=?',(guest_id,user['organization_id'],row['property_id'])).fetchone()
            return {'profile':profile,'history':history,'ifa_reasons':IFA_REASONS,'identity_state':'frozen' if frozen else 'identity_normalization_unresolved',
                    'defaults':{k:row[k] for k in ('full_name','date_of_birth','nationality')},'reporting_id':frozen['reporting_id'] if frozen else None}
    @router.put('')
    def put(guest_id:str,body:Profile,request:Request,rosa_session:str|None=Cookie(default=None)):
        with backend.db() as con:
            user,row=access(con,guest_id,rosa_session)
            return apply_profile(backend,con,user,row,body,request)
    backend.app.include_router(router)


def apply_profile(backend,con,user,row,body,request):
    guest_id=row['id']
    if body.country_of_residence not in COUNTRIES:raise HTTPException(422,'Unsupported residence country')
    if body.nationality_country is not None and body.nationality_country not in COUNTRIES:raise HTTPException(422,'Unsupported nationality country')
    if body.source not in ('manual','correction'):raise HTTPException(422,'Scanned provenance can only be recorded by the scanner integration')
    if body.ifa_status not in IFA_REASONS:raise HTTPException(422,'Unsupported official IFA exemption reason')
    if body.sex not in ('NO','FERFI','EGYEB_VAGY_NEM_ISMERT'):raise HTTPException(422,'Invalid sex classification')
    if not date(1920,1,1)<=body.date_of_birth<=date.today():raise HTTPException(422,'Invalid birth date')
    payload=body.model_dump(mode='json')
    previous=con.execute('SELECT encrypted_payload FROM guest_reporting_profiles WHERE guest_record_id=? ORDER BY revision DESC LIMIT 1',(guest_id,)).fetchone()
    if previous and backend.decrypt_json(previous['encrypted_payload'])==payload:return {'ok':True,'duplicate':True}
    con.execute('INSERT INTO guest_reporting_profiles(id,guest_record_id,organization_id,property_id,effective_from,encrypted_payload,source,reason,actor_id,created_at,revision) VALUES (?,?,?,?,?,?,?,?,?,?,?)',
        (str(uuid.uuid4()),guest_id,user['organization_id'],row['property_id'],str(body.effective_from),backend.encrypt_json(payload),body.source,body.reason,user['id'],backend.now_iso(),con.execute('SELECT COALESCE(MAX(revision),0)+1 n FROM guest_reporting_profiles WHERE guest_record_id=?',(guest_id,)).fetchone()['n']))
    import business_days
    business_days.dirty_range(con,user['organization_id'],row['property_id'],body.effective_from,user['id'],body.reason)
    # Preserve scanned fields; a correction is a separate encrypted source,
    # never falsely labelled as a fresh scan or automatic verification.
    con.execute("UPDATE guest_identity_verifications SET status='needs_review',verified_by=NULL,verified_at=NULL,updated_at=? WHERE guest_record_id=?",(backend.now_iso(),guest_id))
    backend._sync_registration(con,row['reservation_id'],user['organization_id'])
    backend.audit_event(con,user['organization_id'],'guest.reporting_profile_updated','Guest reporting profile updated.',actor_user_id=user['id'],entity_type='guest_record',entity_id=guest_id,metadata={'source':body.source,'effective_from':str(body.effective_from)},request=request)
    return {'ok':True,'identity_preserved':True}
