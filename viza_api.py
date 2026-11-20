"""Property-scoped VIZA management. No key upload, sender toggle or unrestricted resend."""
from datetime import datetime,timezone,timedelta
from fastapi import APIRouter,Cookie,HTTPException,Request
from pydantic import Field
import json,uuid
from pathlib import Path
ERROR_EN=json.loads((Path(__file__).parent/"docs/viza/error-messages-en.json").read_text(encoding="utf8"))
import viza_contracts as c
import viza_delivery as d
import viza_reporting
from viza_security import SecurityBlocked

class Configuration(c.DTO):
    environment:str=Field(default='test',pattern='^(test|staging|production)$')
    reporting_id:str=Field(pattern='^[A-Za-z0-9]{8}$')
    endpoint:str=Field(max_length=300)
    property_name:str=Field(min_length=1,max_length=200)
    provider_name:str=Field(min_length=1,max_length=200)
    provider_tax:str=Field(pattern=r'^[0-9]{8}-[0-9]-[0-9]{2}$')
    poll_minutes:int=Field(default=5,ge=1,le=60)
class Recovery(c.DTO):
    action:str=Field(pattern='^(refresh_identity|retry_not_sent)$')


def error_details(code):
    entry=c.ERRORS.get(code)
    if not entry:return {'code':code if code=='OK' else 'UNKNOWN_CODE','message_en':'Unrecognized response code; review required.','message_hu':'Ismeretlen v\u00e1laszk\u00f3d; ellen\u0151rz\u00e9s sz\u00fcks\u00e9ges.','target':'support'}
    n=int(code[2:]);page=entry['page']
    label=('Check property/provider and reporting identifiers.' if n<=21 else 'Check actual stay dates and identifiers.' if n<=33 or n in (88,89) else 'Review original and manually corrected identity fields.' if n<200 else 'Review property certificate, trust and signature configuration.' if n<300 else 'Review the THF list request selector.')
    hu=entry['source_text'][:400]
    return {'code':code,'message_en':ERROR_EN[code],'message_hu':hu,'page':page,'target':'identity' if 34<=n<=113 and n not in (88,89) else 'configuration' if n<=21 or 200<=n<=209 else 'support'}


def read_model(backend,con,org,prop,now):
    cfg=d.settings(con,org,prop)
    health={'state':'unknown','mode':'disabled','primary':None,'flags':[],'unsent':None,'rejected':None,'observed_at':None,'software_version':None}
    schedules=[];observations=[]
    if cfg:
        fp=d.binding_digest(cfg)
        observations=con.execute('SELECT * FROM viza_observations WHERE organization_id=? AND property_id=? AND environment=? AND binding_digest=? ORDER BY observed_at DESC,id DESC',(org,prop,cfg['environment'],fp)).fetchall()
        status=next((r for r in observations if r['operation']=='allapotLekerdezes'),None)
        if status:
            health.update(backend.decrypt_json(status['encrypted_payload']))
            stale=now-d.datetime.fromisoformat(status['observed_at'])>timedelta(minutes=cfg['poll_minutes']*2)
            health.update(state='stale' if stale else 'mock_observed' if status['mode']=='mock' else 'observed',mode=status['mode'],observed_at=status['observed_at'])
        schedules=[dict(r) for r in con.execute('SELECT operation,selector,due_at,last_error FROM viza_monitor_schedule WHERE property_id=? AND environment=?',(prop,cfg['environment']))]
    jobs=[]
    for row in con.execute('''SELECT j.id,j.event_id,j.kind,j.state capture_state,j.attempts,j.blockers_json,e.reservation_id,
      x.state delivery_state,x.environment,x.due_at,x.mode,x.error_code,x.receipt_id FROM viza_jobs j JOIN stay_events e ON e.id=j.event_id
      LEFT JOIN viza_dispatch x ON x.job_id=j.id WHERE j.organization_id=? AND j.property_id=? ORDER BY j.created_at DESC,j.batch_number LIMIT 200''',(org,prop)):
        job=dict(row);job['blockers']=json.loads(job.pop('blockers_json'));job['state']=job.pop('delivery_state') or job['capture_state']
        job['mode']=job['mode'] or 'disabled'
        downstream=con.execute('SELECT downstream_state FROM viza_message_status WHERE job_id=?',(job['id'],)).fetchone()
        job['downstream_state']=downstream['downstream_state'] if downstream else 'unknown'
        job['guests']=[]
        for g in con.execute('''SELECT v.arrival_uuid,v.guest_record_id,o.state,o.codes_json,o.downstream_state FROM viza_job_guests g JOIN viza_visits v ON v.arrival_uuid=g.arrival_uuid
          LEFT JOIN viza_guest_outcomes o ON o.job_id=g.job_id AND o.arrival_uuid=g.arrival_uuid WHERE g.job_id=?''',(job['id'],)):
            codes=json.loads(g['codes_json'] or '[]')
            job['guests'].append({'arrival_uuid':g['arrival_uuid'],'guest_id':g['guest_record_id'],'state':g['state'] or job['state'],'errors':[error_details(code) for code in codes if code!='OK'],'downstream_state':g['downstream_state'] or 'unknown'})
        job['attempt_history']=[dict(a) for a in con.execute('SELECT g.attempt_no,g.state,g.created_at,a.wire_timestamp,a.finished_at FROM viza_attempts a JOIN government_delivery_attempts g ON g.id=a.id WHERE a.job_id=? ORDER BY g.attempt_no DESC LIMIT 20',(job['id'],))]
        job['can_refresh_identity']=job['kind']=='arrival' and job['attempts']==0 and job['capture_state']=='blocked'
        job['can_retry_not_sent']=job['state']=='retry' and job['error_code']=='definitely_not_sent' and job['mode']=='mock'
        jobs.append(job)
    lists={}
    for selector in ('NEMBEKULDOTT','HIBAS'):
        row=next((r for r in observations if r['selector']==selector),None)
        if row:
            value=backend.decrypt_json(row['encrypted_payload'])
            lists[selector]={'mode':row['mode'],'observed_at':row['observed_at'],'limit_reached':value['limit_reached'],'items':[{k:v for k,v in item.items() if k!='raw_error'} for item in value['items'][:100]],'offset':0,'total':len(value['items']),'delivery_inferred':False}
    actions=[dict(r) for r in con.execute('SELECT id,job_id,action,actor_id,result_code,created_at FROM viza_actions WHERE organization_id=? AND property_id=? ORDER BY created_at DESC,id DESC LIMIT 50',(org,prop))]
    return {'configuration':cfg,'official_transmission_enabled':False,'connection_state':'not_verified','security_blockers':['official_transmission_disabled','Q2_outer_ws_security_unresolved','viza_credentials_and_thf_trust_not_verified'],
      'certificate':{'state':'not_checked','officially_validated':False},'health':health,'schedules':schedules,'jobs':jobs,'lists':lists,'actions':actions,'job_limit':200}


def install(backend):
    router=APIRouter(prefix='/api/government/viza/properties/{property_id}')
    def access(con,session,prop,owner=False):
        user=backend.require_user(session);backend.require_roles(user,*(['owner'] if owner else ['owner','manager']))
        if not con.execute('SELECT id FROM properties WHERE id=? AND organization_id=?',(prop,user['organization_id'])).fetchone():raise HTTPException(404,'Property not found')
        con.execute('UPDATE properties SET id=id WHERE id=? AND organization_id=?',(prop,user['organization_id']))
        return user
    def record(con,user,prop,action,result,job=None):
        con.execute('INSERT INTO viza_actions VALUES (?,?,?,?,?,?,?,?)',(str(uuid.uuid4()),user['organization_id'],prop,job,action,user['id'],result,backend.now_iso()))
    @router.get('')
    def get(property_id:str,rosa_session:str|None=Cookie(default=None)):
        with backend.db() as con:
            user=access(con,rosa_session,property_id)
            return read_model(backend,con,user['organization_id'],property_id,backend.datetime.now(timezone.utc))
    @router.put('/settings')
    def configure(property_id:str,body:Configuration,request:Request,rosa_session:str|None=Cookie(default=None)):
        with backend.db() as con:
            user=access(con,rosa_session,property_id,True)
            cfg=body.model_dump()
            try:d.binding(user['organization_id'],property_id,cfg)
            except SecurityBlocked:raise HTTPException(422,'Explicit verified HTTPS endpoint and property binding are required') from None
            con.execute('''INSERT INTO viza_settings VALUES (?,?,?,?) ON CONFLICT(property_id) DO UPDATE SET config_json=excluded.config_json,updated_at=excluded.updated_at''',(property_id,user['organization_id'],d.dump(cfg),backend.now_iso()))
            d.synchronize(backend,con,backend.datetime.now(timezone.utc),organization_id=user['organization_id'],property_id=property_id)
            record(con,user,property_id,'configure','saved_transmission_disabled')
            return {'saved':True,'official_transmission_enabled':False}
    @router.post('/observe')
    def observe(property_id:str,request:Request,rosa_session:str|None=Cookie(default=None)):
        with backend.db() as con:user=access(con,rosa_session,property_id)
        result=d.monitor_once(backend,user['organization_id'],property_id,now=backend.datetime.now(timezone.utc),requested=True)
        with backend.db() as con:record(con,user,property_id,'observe',result.get('code') or result['state'])
        return result
    @router.get('/lists/{selector}')
    def stored_list(property_id:str,selector:str,offset:int=0,limit:int=100,rosa_session:str|None=Cookie(default=None)):
        if selector not in ('NEMBEKULDOTT','HIBAS') or offset<0 or not 1<=limit<=500:raise HTTPException(422,'Invalid local list page')
        with backend.db() as con:
            user=access(con,rosa_session,property_id)
            cfg=d.settings(con,user['organization_id'],property_id)
            if not cfg:raise HTTPException(404,'No observation available')
            row=con.execute('SELECT * FROM viza_observations WHERE organization_id=? AND property_id=? AND environment=? AND binding_digest=? AND selector=? ORDER BY observed_at DESC,id DESC LIMIT 1',
                (user['organization_id'],property_id,cfg['environment'],d.binding_digest(cfg),selector)).fetchone()
            if not row:raise HTTPException(404,'No observation available')
            value=backend.decrypt_json(row['encrypted_payload'])
            return {'mode':row['mode'],'observed_at':row['observed_at'],'limit_reached':value['limit_reached'],'items':[{k:v for k,v in item.items() if k!='raw_error'} for item in value['items'][offset:offset+limit]],'offset':offset,'total':len(value['items']),'delivery_inferred':False}
    @router.post('/lists/{selector}')
    def retrieve(property_id:str,selector:str,request:Request,rosa_session:str|None=Cookie(default=None)):
        if selector not in ('NEMBEKULDOTT','HIBAS'):raise HTTPException(422,'Invalid list selector')
        with backend.db() as con:user=access(con,rosa_session,property_id)
        result=d.monitor_once(backend,user['organization_id'],property_id,selector=selector,now=backend.datetime.now(timezone.utc),requested=True)
        with backend.db() as con:record(con,user,property_id,'retrieve_'+selector,result.get('code') or result['state'])
        return result
    @router.post('/jobs/{job_id}/recover')
    def recover(property_id:str,job_id:str,body:Recovery,request:Request,rosa_session:str|None=Cookie(default=None)):
        with backend.db() as con:
            user=access(con,rosa_session,property_id)
            job=con.execute('SELECT * FROM viza_jobs WHERE id=? AND property_id=? AND organization_id=?',(job_id,property_id,user['organization_id'])).fetchone()
            if not job:raise HTTPException(404,'Reporting work not found')
            if body.action=='refresh_identity':
                if job['state']!='blocked' or job['attempts'] or job['kind']!='arrival':raise HTTPException(409,'Only never-sent blocked arrival facts can be refreshed')
                event=dict(con.execute('SELECT * FROM stay_events WHERE id=?',(job['event_id'],)).fetchone())
                ids=viza_reporting.recover(backend,con,event)
                d.synchronize(backend,con,backend.datetime.now(timezone.utc),organization_id=user['organization_id'],property_id=property_id);code='facts_refreshed' if ids else 'facts_unchanged'
            else:
                row=con.execute('SELECT * FROM viza_dispatch WHERE job_id=?',(job_id,)).fetchone()
                if not row or row['state']!='retry' or row['error_code']!='definitely_not_sent':raise HTTPException(409,'Outcome must be definitely not sent; uncertain submissions cannot be replayed')
                con.execute('UPDATE viza_dispatch SET due_at=? WHERE job_id=?',(d.stamp(backend.datetime.now(timezone.utc)),job_id));code='scheduled_not_sent_retry'
            record(con,user,property_id,body.action,code,job_id)
            return {'state':code,'official_transmission_enabled':False}
    backend.app.include_router(router)
