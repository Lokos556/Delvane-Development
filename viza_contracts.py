"""Unsigned THF v700 business contract. This module has no transport capability."""
from datetime import date, datetime, timedelta
from pathlib import Path
from typing import Literal
import json,re
from lxml import etree as E
from pydantic import BaseModel, ConfigDict, Field

ROOT=Path(__file__).parent/'docs/viza/contracts'
NS='http://vizainfo.hu/thf/v1'
SOAP='http://schemas.xmlsoap.org/soap/envelope/'
XSI='http://www.w3.org/2001/XMLSchema-instance'
ERRORS=json.loads((ROOT/'errors.json').read_text(encoding='utf8'))
COUNTRY_PAIRS=json.loads((ROOT/'countries.json').read_text(encoding='utf8'))
COUNTRIES=frozenset(p[0] for p in COUNTRY_PAIRS)
FIELDS=('csaladnev','utonev','szuletesiCsaladnev','szuletesiUtonev','szuletesiDatum','szuletesiHely','anyjaCsaladnev','anyjaUtonev','allampolgarsagKod','nem','okmanyTipus','okmanyAzonositoSzam')
PAIRS=(FIELDS[:2],FIELDS[2:4],FIELDS[6:8])
UUID_PATTERN=r'^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$'

class ContractError(ValueError):pass
class DTO(BaseModel):
    model_config=ConfigDict(extra='forbid')
class Person(DTO):
    csaladnev:str|None=None
    utonev:str|None=None
    szuletesiCsaladnev:str|None=None
    szuletesiUtonev:str|None=None
    szuletesiDatum:date|None=None
    szuletesiHely:str|None=None
    anyjaCsaladnev:str|None=None
    anyjaUtonev:str|None=None
    allampolgarsagKod:str|None=None
    nem:Literal['NO','FERFI','EGYEB_VAGY_NEM_ISMERT']|None=None
    okmanyTipus:Literal['SZEM_IG','UTLEVEL','VEZ_ENG','EGYEB']|None=None
    okmanyAzonositoSzam:str|None=None
class Property(DTO):
    adatszolgaltatasiAzonosito:str=Field(min_length=8,max_length=8)
    szallasNev:str
    szallashelySzolgaltatoAdoszam:str=Field(pattern=r'^[0-9]{8}-[0-9]-[0-9]{2}$')
    szallashelySzolgaltatoNev:str
class Validation(DTO):
    ellenorzoString:str
    alairoTanusitvany:str
    alairas:str
class Header(DTO):
    uzenetAzonosito:str=Field(pattern=UUID_PATTERN)
    szallashely:Property
    bejelentesIdopontja:datetime
    pmsValidaciosUzenet:Validation
class Arrival(DTO):
    erkezesAzonosito:str=Field(pattern=UUID_PATTERN)
    erkezesIdeje:datetime
    tavozasVarhatoDatuma:date
    manualisanRogzitettAdat:Person|None=None
    okmanybolBeolvasottAdat:Person|None=None
    vizumEngedelySzam:str|None=None
    beutazasDatuma:date|None=None
    beutazasHelye:str|None=None
class Departure(DTO):
    erkezesAzonosito:str=Field(pattern=UUID_PATTERN)
    tavozasIdeje:datetime
class ArrivalRequest(Header):
    erkezoVendeg:list[Arrival]=Field(min_length=1,max_length=10)
class DepartureRequest(Header):
    tavozoVendeg:list[Departure]=Field(min_length=1,max_length=10)
class StatusRequest(DTO):pass
class ListRequest(DTO):
    bekuldetlenAdatTipus:Literal['NEMBEKULDOTT','HIBAS']
class Outcome(DTO):
    erkezesAzonosito:str=Field(pattern=UUID_PATTERN)
    hibaKod:str
    hibaSzoveg:str
    @property
    def codes(self):
        # Q4 delimiter discrepancy: retain the raw value and every token.
        return tuple(c.strip() for c in re.split('[,;]',self.hibaKod) if c.strip())
class Receipt(DTO):
    sikeresBefogadas:bool
    fogadasAzonosito:str=Field(pattern=UUID_PATTERN)
    fogadasIdeje:datetime
    hibaLista:list[Outcome]=Field(min_length=1,max_length=10)
class Status(DTO):
    szoftverVerzio:str|None
    allapotKod:str
    bekuldetlenUzenetekSzama:int=Field(ge=0)
    hibasUzenetekSzama:int=Field(ge=0)
    idoPecset:datetime
class Unsent(DTO):
    uzenetAzonosito:str=Field(pattern=UUID_PATTERN)
    adatszolgaltatasiAzonosito:str
    hibaUzenet:str|None=None
class Listing(DTO):
    eredmenyKod:str
    bekuldetlenAdat:list[Unsent]=Field(default_factory=list,max_length=10000)
OPERATIONS={
 'allapotLekerdezes':(StatusRequest,Status),
 'erkezesiAdatokBekuldese':(ArrivalRequest,Receipt),
 'tavozasiAdatokBekuldese':(DepartureRequest,Receipt),
 'bekuldetlenAdatLista':(ListRequest,Listing)}

def country(raw):
    if raw in COUNTRIES:return raw
    found=[a for a,b in COUNTRY_PAIRS if b==raw]
    if len(found)!=1:raise ContractError('country_mapping_requires_review')
    return found[0]

def years_before(day,years):
    try:return day.replace(year=day.year-years)
    except ValueError:return day.replace(year=day.year-years,day=28)

def identity_errors(values,arrival_day):
    errors=[]
    for key,value in values.items():
        if value is None:continue
        if key in FIELDS or key in ('vizumEngedelySzam','beutazasHelye'):
            if isinstance(value,str):
                maximum=100 if key in ('okmanyAzonositoSzam','vizumEngedelySzam') else 200
                if len(value)>maximum or (maximum==200 and len(value.encode('utf8'))>254):errors.append('length:'+key)
    dob=values.get('szuletesiDatum')
    try:
        dob=date.fromisoformat(str(dob)) if dob else None
        if not dob or not years_before(arrival_day,110)<=dob<=arrival_day:errors.append('birth_date')
    except ValueError:dob=None;errors.append('birth_date')
    for k in ('csaladnev','utonev','allampolgarsagKod','nem'):
        if not values.get(k):errors.append('missing:'+k)
    for a,b in PAIRS[1:]:
        if bool(values.get(a))!=bool(values.get(b)):errors.append('name_pair:'+a)
    if values.get('allampolgarsagKod') not in COUNTRIES:errors.append('country_mapping_requires_review')
    if values.get('nem') not in ('NO','FERFI','EGYEB_VAGY_NEM_ISMERT'):errors.append('sex')
    if dob and dob<=years_before(arrival_day,14):
        for k in ('okmanyTipus','okmanyAzonositoSzam'):
            if not values.get(k):errors.append('missing:'+k)
    if values.get('okmanyTipus') is not None and values['okmanyTipus'] not in ('SZEM_IG','UTLEVEL','VEZ_ENG','EGYEB'):errors.append('document_type')
    return errors

def source_identity_errors(original,manual,arrival_day):
    errors=identity_errors({**original,**manual},arrival_day)
    if any(original.get(k) for k in PAIRS[0]) and not any(k in manual for k in PAIRS[0]):
        errors=[e for e in errors if e not in ('missing:csaladnev','missing:utonev')]
    for a,b in PAIRS:
        if not any(k in manual for k in (a,b)):
            errors=[e for e in errors if e!='name_pair:'+a]
        if bool(manual.get(a))!=bool(manual.get(b)):errors.append('manual_name_pair:'+a)
    return errors


def business_rules(dto,now,*,expected_departure_days=365):
    errors=[]
    if isinstance(dto,Header):
        if dto.bejelentesIdopontja.utcoffset() is None or not now-timedelta(days=730)<=dto.bejelentesIdopontja<=now:errors.append('report_timestamp')
    if isinstance(dto,ArrivalRequest):
        ids=[g.erkezesAzonosito for g in dto.erkezoVendeg]
        if len(set(ids))!=len(ids):errors.append('duplicate_arrival_uuid')
        for g in dto.erkezoVendeg:
            if g.erkezesIdeje.utcoffset() is None:errors.append('arrival_offset');continue
            if not now-timedelta(days=730)<=g.erkezesIdeje<=now+timedelta(days=1):errors.append('arrival_window')
            if g.tavozasVarhatoDatuma<=g.erkezesIdeje.date():errors.append('Q6_expected_departure')
            if g.tavozasVarhatoDatuma>g.erkezesIdeje.date()+timedelta(days=expected_departure_days):errors.append('expected_departure_parameter')
            merged={}
            for p in (g.okmanybolBeolvasottAdat,g.manualisanRogzitettAdat):
                if p:merged.update({k:v for k,v in p.model_dump().items() if v is not None})
            original=g.okmanybolBeolvasottAdat.model_dump(exclude_unset=True) if g.okmanybolBeolvasottAdat else {}
            manual=g.manualisanRogzitettAdat.model_dump(exclude_unset=True) if g.manualisanRogzitettAdat else {}
            original={k:v for k,v in original.items() if v is not None};manual={k:v for k,v in manual.items() if v is not None}
            errors.extend(source_identity_errors(original,manual,g.erkezesIdeje.date()))
            for person in (g.manualisanRogzitettAdat,g.okmanybolBeolvasottAdat):
                if person:errors.extend(identity_errors_lengths(person.model_dump()))
            if g.manualisanRogzitettAdat:
                manual=g.manualisanRogzitettAdat.model_dump()
                for a,b in PAIRS:
                    if bool(manual.get(a))!=bool(manual.get(b)):errors.append('manual_name_pair:'+a)
            if g.beutazasDatuma and g.beutazasDatuma>now.date():errors.append('entry_date_future')
            errors.extend(identity_errors_lengths(g.model_dump()))
    if isinstance(dto,DepartureRequest):
        for g in dto.tavozoVendeg:
            if g.tavozasIdeje.utcoffset() is None or not now-timedelta(days=365)<=g.tavozasIdeje<=now+timedelta(days=1):errors.append('departure_window')
    return sorted(set(errors))

def identity_errors_lengths(values):
    return [e for e in identity_errors(values,date.today()) if e.startswith('length:')]

def parser():return E.XMLParser(resolve_entities=False,no_network=True,load_dtd=False)
SCHEMA=E.XMLSchema(E.parse(str(ROOT/'thf-v700.xsd'),parser()))

def xml_root(raw):
    if len(raw)>8*1024*1024:raise ContractError('xml_size_limit')
    if re.search(br'<!\s*(DOCTYPE|ENTITY)',raw,re.I):raise ContractError('unsafe_xml')
    try:return E.fromstring(raw,parser())
    except E.XMLSyntaxError:raise ContractError('malformed_xml') from None

def validate(raw,operation,response=False):
    if operation not in OPERATIONS:raise ContractError('unknown_operation')
    root=xml_root(raw)
    if root.tag==f'{{{SOAP}}}Envelope':
        bodies=root.findall(f'{{{SOAP}}}Body')
        if len(bodies)!=1 or len(bodies[0])!=1:raise ContractError('soap_body')
        root=bodies[0][0]
    if root.tag!=f'{{{NS}}}{operation}{"Response" if response else "Request"}':raise ContractError('operation_namespace')
    if not SCHEMA.validate(root):raise ContractError('schema_validation_failed')
    return root

def append(parent,key,value):
    if isinstance(value,list):
        for v in value:append(parent,key,v)
        return
    node=E.SubElement(parent,f'{{{NS}}}{key}')
    if value is None:node.set(f'{{{XSI}}}nil','true')
    elif isinstance(value,dict):
        for k,v in value.items():
            if v is None and k in ('manualisanRogzitettAdat','okmanybolBeolvasottAdat','hibaUzenet'):continue
            append(node,k,v)
    else:node.text=('true' if value else 'false') if isinstance(value,bool) else str(value)

def serialize(operation,dto,*,response=False,now=None,envelope=False,exact_report_timestamp=None):
    if operation not in OPERATIONS:raise ContractError('unknown_operation')
    expected=OPERATIONS[operation][int(response)]
    if not isinstance(dto,expected):raise ContractError('dto_operation_mismatch')
    if now is not None:
        errors=business_rules(dto,now)
        if errors:raise ContractError(','.join(errors))
    root=E.Element(f'{{{NS}}}{operation}{"Response" if response else "Request"}',nsmap={None:NS,'xsi':XSI})
    data=dto.model_dump(mode='json')
    if exact_report_timestamp is not None:
        try:
            if not isinstance(dto,Header) or datetime.fromisoformat(exact_report_timestamp.replace('Z','+00:00'))!=dto.bejelentesIdopontja:raise ValueError()
        except ValueError:raise ContractError('report_timestamp_lexical_mismatch') from None
        data['bejelentesIdopontja']=exact_report_timestamp
    if isinstance(dto,(ArrivalRequest,DepartureRequest,Receipt)):
        append(root,'valaszAdat' if response else 'keresAdat',data)
    else:
        for k,v in data.items():append(root,k,v)
    raw=E.tostring(root);validate(raw,operation,response)
    if envelope:
        env=E.Element(f'{{{SOAP}}}Envelope',nsmap={'soap':SOAP});E.SubElement(env,f'{{{SOAP}}}Body').append(root);raw=E.tostring(env)
    return raw

def values(node):
    result={}
    for c in node:
        k=E.QName(c).localname
        v=None if c.get(f'{{{XSI}}}nil')=='true' else values(c) if len(c) else c.text or ''
        if k in ('erkezoVendeg','tavozoVendeg','hibaLista','bekuldetlenAdat'):result.setdefault(k,[]).append(v)
        else:result[k]=v
    return result

def parse(operation,raw,*,response=True):
    root=validate(raw,operation,response);data=values(root)
    return OPERATIONS[operation][int(response)].model_validate(data.get('valaszAdat',data.get('keresAdat',data)))

class UnresolvedOuterSecurity:
    def sign(self,*args,**kwargs):raise ContractError('Q2_outer_ws_security_unresolved')
