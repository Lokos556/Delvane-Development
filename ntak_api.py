"""Owner reporting management. Server-side identities/credentials are never uploaded."""
from datetime import date, datetime, timezone
from zoneinfo import ZoneInfo
from pathlib import Path
import json
import os
import uuid
from fastapi import APIRouter, Cookie, HTTPException, Request
from pydantic import BaseModel, ConfigDict, Field
import ntak_reporting as reporting
from ntak_protocol import ReportingBlocked, header, request_xml, validate_business
from ntak_contracts import ContractError, contracts, XSD
from government_security import certificate_status


class Configuration(BaseModel):
    model_config = ConfigDict(extra='forbid')
    enabled: bool = False
    environment: str = 'test'
    registration_id: str = Field(max_length=10)
    provider_vat: str = Field(max_length=13)
    software_id: str = Field(max_length=15)
    software_version: str = Field(max_length=10)
    timezone: str = 'Europe/Budapest'
    reporting_start_date: str | None = None
    reporting_start_evidence: str = Field(default='',max_length=500)
    closing_hour: int = Field(default=10,ge=1,le=23)


class Facts(BaseModel):
    model_config = ConfigDict(extra='forbid')
    values: dict
    evidence: str = Field(min_length=3,max_length=500)


class Recovery(BaseModel):
    model_config = ConfigDict(extra='forbid')
    action: str
    reason: str = Field(min_length=3,max_length=500)
    processing_id: str | None = None


def install(backend):
    router = APIRouter(prefix='/api/government/ntak')

    def access(session, prop, *, write=False):
        user=backend.require_user(session)
        backend.require_roles(user, *(['owner'] if write else ['owner','manager']))
        with backend.db() as con:
            if not con.execute('SELECT id FROM properties WHERE organization_id=? AND id=?',(user['organization_id'],prop)).fetchone():
                raise HTTPException(404,'Property not found')
        return user

    def fail(exc):
        raise HTTPException(422,{'code':getattr(exc,'code','schema_validation_failed'),'fields':getattr(exc,'fields',[])}) from None

    def audit(con,user,prop,action,request,metadata=None):
        backend.audit_event(con,user['organization_id'],'ntak.'+action,'NTAK reporting management updated.',actor_user_id=user['id'],entity_type='property',entity_id=prop,metadata=metadata or {},request=request)

    @router.get('/properties/{property_id}')
    def status(property_id: str, rosa_session: str | None=Cookie(default=None)):
        user=access(rosa_session,property_id)
        with backend.db() as con:
            config=reporting.configuration(con,user['organization_id'],property_id)
            jobs=[dict(r) for r in con.execute('''SELECT id,operation,environment,state,error_code,missing_fields_json,processing_id,attempts,next_attempt_at,created_at,updated_at
              FROM ntak_jobs WHERE organization_id=? AND property_id=? ORDER BY created_at DESC,id LIMIT 100''',(user['organization_id'],property_id))]
            for job in jobs: job['missing_fields']=json.loads(job.pop('missing_fields_json'))
            days=[dict(r) for r in con.execute('''SELECT d.business_date,COALESCE(j.state,d.state) state,d.job_id FROM ntak_daily_requirements d
              LEFT JOIN ntak_jobs j ON j.id=d.job_id WHERE d.organization_id=? AND d.property_id=? ORDER BY d.business_date DESC LIMIT 60''',(user['organization_id'],property_id))]
            counts=[dict(r) for r in con.execute('SELECT state,COUNT(*) count FROM ntak_jobs WHERE organization_id=? AND property_id=? GROUP BY state',(user['organization_id'],property_id))]
            success=con.execute("SELECT MAX(updated_at) at FROM ntak_jobs WHERE organization_id=? AND property_id=? AND state='succeeded'",(user['organization_id'],property_id)).fetchone()['at']
        # Operator-managed paths and mappings are neither accepted nor returned by API.
        cert={'state':'not_configured','officially_validated':False}
        root=os.environ.get('DELVANE_NTAK_CREDENTIAL_ROOT')
        references=json.loads(os.environ.get('DELVANE_NTAK_CREDENTIAL_REFERENCES','{}'))
        ref=references.get(property_id)
        if root and ref: cert=certificate_status(root,ref)
        return {'configuration':config,'jobs':jobs,'counts':counts,'daily_closings':days,
                'last_success_at':success,'certificate':cert,'connected':False,'officially_validated':False,
                'transmission_enabled':False,'blockers':['signature_profile_unresolved','official_endpoint_pending'],
                'information_query_blocked':True}

    @router.get('/forms')
    def forms(rosa_session: str|None=Cookie(default=None)):
        user=backend.require_user(rosa_session);backend.require_roles(user,'owner','manager')
        def describe(schema, declaration):
            kind=declaration.get('type','')
            complex_type=declaration.find('{'+XSD+'}complexType')
            if complex_type is None: complex_type=schema.find('{'+XSD+'}complexType[@name="'+kind+'"]')
            info={'name':declaration.get('name'),'required':declaration.get('minOccurs','1')!='0',
                  'repeated':declaration.get('maxOccurs','1')!='1'}
            if complex_type is not None:
                return {**info,'type':'object','fields':[describe(schema,n) for n in complex_type.findall('.//{'+XSD+'}element')]}
            simple=schema.find('{'+XSD+'}simpleType[@name="'+kind+'"]')
            restriction=simple.find('{'+XSD+'}restriction') if simple is not None else None
            base=restriction.get('base') if restriction is not None else kind
            result={**info,'type':'boolean' if base=='xs:boolean' else 'integer' if base in ('xs:integer','xs:int') else 'number' if base in ('xs:double','xs:decimal') else 'string'}
            if restriction is not None:
                result['values']=[n.get('value') for n in restriction.findall('{'+XSD+'}enumeration')]
            return result
        result={}
        for operation,field in [('reservation','foglalasEsemeny'),('stay','esemenyek'),('daily_close','napiFeltoltes')]:
            schema=contracts()[operation][1]
            declaration=next(n for n in schema.findall('.//{'+XSD+'}element') if n.get('name')==field)
            result[operation]=describe(schema,declaration)
        return result

    @router.put('/properties/{property_id}')
    def configure(property_id: str, body: Configuration, request: Request, rosa_session: str | None=Cookie(default=None)):
        user=access(rosa_session,property_id,write=True)
        cfg=body.model_dump()
        if body.environment not in ('test','production'): raise HTTPException(422,'Invalid reporting environment')
        if body.environment=='production' and backend.APP_ENV!='production': raise HTTPException(409,'Production configuration is forbidden in this deployment')
        try:
            ZoneInfo(body.timezone)
            if body.reporting_start_date:
                date.fromisoformat(body.reporting_start_date)
                if not body.reporting_start_evidence.strip(): raise ValueError()
            request_xml('information',cfg,{},str(uuid.uuid4()),reporting.stamp())
        except (ValueError,ContractError,ReportingBlocked,KeyError): raise HTTPException(422,'Invalid NTAK configuration or start-date evidence') from None
        with backend.db() as con:
            current=con.execute("SELECT * FROM government_connections WHERE organization_id=? AND property_id=? AND system='NTAK'",(user['organization_id'],property_id)).fetchone()
            public=json.loads(current['public_config_json']) if current else {}
            previous=public.get('ntak_v9')
            if previous and previous['environment']!=cfg['environment'] and con.execute('SELECT id FROM ntak_jobs WHERE organization_id=? AND property_id=? LIMIT 1',(user['organization_id'],property_id)).fetchone():
                raise HTTPException(409,'Use a separate deployment/database for another reporting environment')
            public['ntak_v9']=cfg
            con.execute('''INSERT INTO government_connections(id,organization_id,property_id,system,status,public_config_json,created_at,updated_at)
              VALUES (?,?,?,'NTAK','protocol_blocked',?,?,?) ON CONFLICT(organization_id,property_id,system)
              DO UPDATE SET public_config_json=excluded.public_config_json,status='protocol_blocked',updated_at=excluded.updated_at''',
              (str(uuid.uuid4()),user['organization_id'],property_id,reporting.dump(public),reporting.stamp(),reporting.stamp()))
            audit(con,user,property_id,'configured',request,{'environment':body.environment,'enabled':body.enabled})
            reporting.schedule_daily(con)
        return {'ok':True,'transmission_enabled':False}

    @router.put('/properties/{property_id}/reservations/{reservation_id}/facts')
    def reservation_facts(property_id: str,reservation_id: str,body: Facts,request: Request,rosa_session: str|None=Cookie(default=None)):
        user=access(rosa_session,property_id,write=True)
        with backend.db() as con:
            record=con.execute('SELECT * FROM reservations WHERE organization_id=? AND property_id=? AND id=?',(user['organization_id'],property_id,reservation_id)).fetchone()
            if not record: raise HTTPException(404,'Reservation not found')
            cfg=reporting.configuration(con,user['organization_id'],property_id)
            if not cfg: raise HTTPException(409,'Configure NTAK first')
            try:
                from ntak_protocol import reservation_payload
                payload=reservation_payload(dict(record),body.values,reporting.stamp())
                request_xml('reservation',cfg,payload,str(uuid.uuid4()),reporting.stamp())
            except (ContractError,ReportingBlocked) as exc: fail(exc)
            except (KeyError,TypeError,ValueError): fail(ReportingBlocked('invalid_reporting_data'))
            con.execute('''INSERT INTO ntak_reservation_facts(reservation_id,organization_id,property_id,facts_json,updated_at) VALUES (?,?,?,?,?)
              ON CONFLICT(reservation_id) DO UPDATE SET facts_json=excluded.facts_json,updated_at=excluded.updated_at''',
              (reservation_id,user['organization_id'],property_id,reporting.dump(body.values),reporting.stamp()))
            job=reporting.capture_reservation(con,user['organization_id'],reservation_id)
            audit(con,user,property_id,'reservation_facts_recorded',request,{'reservation_id':reservation_id,'evidence':body.evidence})
        return {'ok':True,'job_id':job}

    @router.put('/properties/{property_id}/daily-closing/{business_date}')
    def daily_facts(property_id:str,business_date:str,body:Facts,request:Request,rosa_session:str|None=Cookie(default=None)):
        user=access(rosa_session,property_id,write=True)
        with backend.db() as con:
            if con.execute('SELECT 1 FROM business_day_settings WHERE property_id=?',(property_id,)).fetchone():raise HTTPException(409,'Use normal business-day closing; reporting dictionaries cannot override operational snapshots')
            cfg=reporting.configuration(con,user['organization_id'],property_id)
            if not cfg: raise HTTPException(409,'Configure NTAK first')
            payload={'napiFeltoltes':body.values}
            try:
                if body.values.get('lezartNap')!=business_date: raise ReportingBlocked('closing_date_mismatch')
                validate_business('daily_close',payload,datetime.now(ZoneInfo(cfg['timezone'])).date())
                request_xml('daily_close',cfg,payload,str(uuid.uuid4()),reporting.stamp())
            except (ReportingBlocked,ContractError) as exc: fail(exc)
            except (KeyError,TypeError,ValueError): fail(ReportingBlocked('invalid_reporting_data'))
            con.execute('UPDATE properties SET id=id WHERE id=? AND organization_id=?',(property_id,user['organization_id']))
            previous=con.execute('SELECT * FROM ntak_day_facts WHERE organization_id=? AND property_id=? AND business_date=?',(user['organization_id'],property_id,business_date)).fetchone()
            if previous and previous['payload_json']==reporting.dump(payload): return {'ok':True,'duplicate':True}
            if previous and body.values['napiZarasBesorolas']['besorolas']!='MODOSITO': raise HTTPException(409,'A changed closing requires the documented correction classification and reason')
            revision=previous['revision']+1 if previous else 1
            con.execute('''INSERT INTO ntak_day_facts(organization_id,property_id,business_date,revision,payload_json,confirmed_by,confirmed_at) VALUES (?,?,?,?,?,?,?)
              ON CONFLICT(organization_id,property_id,business_date) DO UPDATE SET revision=excluded.revision,payload_json=excluded.payload_json,confirmed_by=excluded.confirmed_by,confirmed_at=excluded.confirmed_at''',
              (user['organization_id'],property_id,business_date,revision,reporting.dump(payload),user['id'],reporting.stamp()))
            audit(con,user,property_id,'day_closed',request,{'business_date':business_date,'revision':revision,'evidence':body.evidence})
            reporting.schedule_daily(con)
        return {'ok':True}

    @router.post('/properties/{property_id}/stay-events/{event_id}')
    def stay_event(property_id:str,event_id:str,body:Facts,request:Request,rosa_session:str|None=Cookie(default=None)):
        user=access(rosa_session,property_id,write=True)
        if len(event_id)>100: raise HTTPException(422,'Invalid event identifier')
        with backend.db() as con:
            cfg=reporting.configuration(con,user['organization_id'],property_id)
            if not cfg: raise HTTPException(409,'Configure NTAK first')
            try:
                payload={'esemenyek':body.values}
                validate_business('stay',payload,datetime.now(ZoneInfo(cfg['timezone'])).date())
                request_xml('stay',cfg,payload,str(uuid.uuid4()),reporting.stamp())
                for entries in body.values.values():
                    for event in entries:
                        if not con.execute('SELECT id FROM reservations WHERE id=? AND organization_id=? AND property_id=?',(event['foglalasiSzam'],user['organization_id'],property_id)).fetchone(): raise HTTPException(404,'Reservation not found')
                job=reporting.enqueue(con,user['organization_id'],property_id,cfg,'stay','stay:'+event_id,payload)
            except (ReportingBlocked,ContractError) as exc: fail(exc)
            except (KeyError,TypeError,ValueError): fail(ReportingBlocked('invalid_reporting_data'))
            audit(con,user,property_id,'actual_stay_event_recorded',request,{'event_id':event_id,'evidence':body.evidence})
        return {'ok':True,'job_id':job}

    @router.post('/properties/{property_id}/jobs/{job_id}/recovery')
    def recover(property_id:str,job_id:str,body:Recovery,request:Request,rosa_session:str|None=Cookie(default=None)):
        user=access(rosa_session,property_id,write=True)
        with backend.db() as con:
            con.execute('UPDATE ntak_jobs SET id=id WHERE id=? AND organization_id=? AND property_id=?',(job_id,user['organization_id'],property_id))
            job=con.execute('SELECT * FROM ntak_jobs WHERE id=? AND organization_id=? AND property_id=?',(job_id,user['organization_id'],property_id)).fetchone()
            if not job: raise HTTPException(404,'Reporting job not found')
            if body.action=='record_processing_id' and job['state']=='uncertain':
                try: receipt=str(uuid.UUID(body.processing_id or ''))
                except ValueError: raise HTTPException(422,'Valid processing identifier required') from None
                reporting.set_state(con,job,'accepted',None,datetime.now(timezone.utc),processing_id=receipt,accepted_at=reporting.stamp(),next_attempt_at=reporting.stamp())
            elif body.action=='retry_after_resolution' and job['state']=='retry_exhausted':
                reporting.set_state(con,job,'accepted' if job['processing_id'] else 'retry',None,datetime.now(timezone.utc),retries=0,next_attempt_at=reporting.stamp())
            else: raise HTTPException(409,'This state cannot safely be retried; correct the source facts or obtain the processing identifier')
            audit(con,user,property_id,'recovery',request,{'job_id':job_id,'action':body.action,'reason':body.reason})
        return {'ok':True,'transmission_enabled':False}

    backend.app.include_router(router)
