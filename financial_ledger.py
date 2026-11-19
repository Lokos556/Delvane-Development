"""Operational folios. Decimal strings at every boundary; no payment processor I/O."""
from datetime import date
from decimal import Decimal, InvalidOperation, ROUND_HALF_UP
import hashlib
import json
import uuid
from fastapi import Cookie, HTTPException
from pydantic import BaseModel, ConfigDict, Field
from ntak_contracts import contracts, XSD

# Interface v9.07 appendix12.3 pp243â€“246, not validation fixture data.
CATEGORIES = {
 'SZALLASDIJ':[], 'IFA':[],
 'KOZFURDO':'FURDO_PROGRAM STRAND_PROGRAM USZODAI_PROGRAM WELLNESS_PROGRAM EGESZSEGUGYI_SZOLGALTATAS'.split(),
 'TERMESZETES_FURDO':['SZABADVIZI_STRAND_PROGRAM'],
 'MUZEUM_VAR_KASTELY':'KIALLITAS MUZEUMPEDAGOGIA TARLATVEZETES EGYHAZI_LETESITMENY_LATOGATASA KASTELYLATOGATAS VARLATOGATAS EGYEB_MUEMLEK_LATOGATASA OKTATASI_PROGRAM'.split(),
 'TURISZTIKAI_KOZLEKEDES':'TAVI_HAJOZAS FOLYAMI_HAJOZAS HOP_ON_HOP_OFF'.split(),
 'KALANDPARK':'KALANDPARKI_PROGRAM ELMENYKOZPONTI_PROGRAM'.split(),
 'ALLATKERT':'ALLATKERTI_PROGRAM VADASPARKI_PROGRAM'.split(),
 'VIDAMPARK':['VIDAMPARKI_PROGRAM'],
 'VEDETT_TERMESZETI_TERULET':'NEMZETI_PARK_LATOGATAS BARLANGLATOGATAS TARLATVEZETES OKTATASI_PROGRAM PARKLATOGATAS TEMATIKUS_BEMUTATOHELY_LATOGATAS TURAK_KIRANDULASOK'.split(),
 'ZENES_TANCOS_RENDEZVENY':'KULTURALIS_RENDEZVENY KONCERT FESZTIVAL'.split(),
 'ETEL':'REGGELI SZENDVICS ELOETEL LEVES FOETEL KORET SAVANYUSAG_SALATA KOSTOLO PEKSUTEMENY DESSZERT SNACK FOETEL_KORETTEL ETELCSOMAG EGYEB'.split(),
 'ALKMENTESITAL_HELYBEN':'VIZ LIMONADE_SZORP_FACSART ALKOHOLMENTES_KOKTEL TEA_FORROCSOKOLADE ITALCSOMAG KAVE'.split(),
 'ALKMENTESITAL_NEM_HELYBEN':'VIZ ROSTOS_UDITO SZENSAVAS_UDITO SZENSAVMENTES_UDITO ITALCSOMAG'.split(),
 'ALKOHOLOSITAL':'KOKTEL LIKOR PARLAT SOR BOR PEZSGO ITALCSOMAG'.split(),
 'EGYEB':'EGYEB SZERVIZDIJ BORRAVALO EGYEB_VENDEGLATAS'.split(),
}


def enum(name):
    return contracts()['daily_close'][1].xpath('./xs:simpleType[@name="'+name+'"]//xs:enumeration/@value',namespaces={'xs':XSD})


def dec(value, *, positive=False, places=2):
    try:
        if not isinstance(value,str): raise ValueError()
        d=Decimal(value)
        if not d.is_finite() or abs(d)>Decimal('999999999999') or d<0 or (positive and d<=0):raise ValueError()
        rounded=d.quantize(Decimal(1).scaleb(-places),rounding=ROUND_HALF_UP)
        if positive and rounded<=0:raise ValueError()
        return rounded
    except (InvalidOperation,ValueError):raise HTTPException(422,{'code':'invalid_decimal'}) from None


def money(value):return format(value.quantize(Decimal('.01'),rounding=ROUND_HALF_UP),'f')


def migrate(backend,con):
    con.executescript('''CREATE TABLE IF NOT EXISTS financial_folios (
      reservation_id TEXT PRIMARY KEY REFERENCES reservations(id),organization_id TEXT NOT NULL,
      property_id TEXT NOT NULL,original_quote_huf TEXT,activated_at TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS financial_entries (
      id TEXT PRIMARY KEY,organization_id TEXT NOT NULL,property_id TEXT NOT NULL REFERENCES properties(id),
      reservation_id TEXT REFERENCES reservations(id),unit_id TEXT REFERENCES physical_units(id),guest_id TEXT REFERENCES guest_records(id),
      kind TEXT NOT NULL,business_date TEXT NOT NULL,document_date TEXT,
      description TEXT NOT NULL,quantity TEXT NOT NULL,unit_price TEXT NOT NULL,currency TEXT NOT NULL,
      exchange_rate TEXT NOT NULL,exchange_evidence TEXT NOT NULL,total TEXT NOT NULL,total_huf TEXT NOT NULL,
      category TEXT,subcategory TEXT,vat TEXT,in_package INTEGER NOT NULL,payment_method TEXT,payment_subtype TEXT,
      direction TEXT NOT NULL,supersedes TEXT UNIQUE REFERENCES financial_entries(id),voided INTEGER NOT NULL,
      request_id TEXT NOT NULL,digest TEXT NOT NULL,actor_id TEXT NOT NULL,source TEXT NOT NULL,reason TEXT NOT NULL,posted_at TEXT NOT NULL,
      UNIQUE(organization_id,request_id));
    CREATE INDEX IF NOT EXISTS idx_financial_day ON financial_entries(organization_id,property_id,business_date);
    CREATE INDEX IF NOT EXISTS idx_financial_reservation ON financial_entries(reservation_id);
    ''')
    con.execute('INSERT OR IGNORE INTO schema_migrations(version,name,applied_at) VALUES (?,?,?)',(3081,'operational_decimal_financial_ledger',backend.now_iso()))
    backend.add_column_if_missing(con,'financial_entries','refund_of','TEXT REFERENCES financial_entries(id)')
    con.execute('INSERT OR IGNORE INTO schema_migrations(version,name,applied_at) VALUES (?,?,?)',(3084,'refund_original_payment_links',backend.now_iso()))


class Posting(BaseModel):
    model_config=ConfigDict(extra='forbid',str_strip_whitespace=True)
    request_id:uuid.UUID
    kind:str
    business_date:date
    document_date:date|None=None
    description:str=Field(min_length=1,max_length=250)
    quantity:str='1'
    unit_price:str
    currency:str=Field(default='HUF',pattern='^[A-Z]{3}$')
    exchange_rate:str='1'
    exchange_evidence:str=Field(default='',max_length=300)
    category:str|None=None
    subcategory:str|None=None
    vat:str|None=None
    in_package:bool=False
    payment_method:str|None=None
    payment_subtype:str|None=None
    direction:str='payment'
    unit_id:str|None=None
    guest_id:str|None=None
    supersedes:str|None=None
    refund_of:str|None=None
    voided:bool=False
    reason:str=Field(min_length=3,max_length=500)


def active(con,org,prop,*,rid=None,day=None):
    sql='''SELECT e.* FROM financial_entries e WHERE e.organization_id=? AND e.property_id=? AND e.voided=0
      AND NOT EXISTS (SELECT 1 FROM financial_entries n WHERE n.supersedes=e.id)'''
    args=[org,prop]
    if rid is not None:sql+=' AND e.reservation_id=?';args.append(rid)
    if day is not None:sql+=' AND e.business_date=?';args.append(str(day))
    return [dict(r) for r in con.execute(sql+' ORDER BY e.posted_at,e.id',args)]


def totals(entries):
    charges=sum((Decimal(e['total_huf']) for e in entries if e['kind']=='charge'),Decimal(0))
    payments=sum((Decimal(e['total_huf']) for e in entries if e['kind']=='payment' and e['direction']=='payment'),Decimal(0))
    refunds=sum((Decimal(e['total_huf']) for e in entries if e['kind']=='payment' and e['direction']=='refund'),Decimal(0))
    return {'charges':money(charges),'payments':money(payments),'refunds':money(refunds),'balance':money(charges-payments+refunds)}


def scoped(backend,con,org,rid):
    r=con.execute('SELECT * FROM reservations WHERE id=? AND organization_id=?',(rid,org)).fetchone()
    if not r:raise HTTPException(404,'Reservation not found')
    con.execute('UPDATE properties SET id=id WHERE id=? AND organization_id=?',(r['property_id'],org))
    backend._lock_reservation(con,rid,org)
    return dict(con.execute('SELECT * FROM reservations WHERE id=? AND organization_id=?',(rid,org)).fetchone())


def managed(con,rid):return con.execute('SELECT 1 FROM financial_folios WHERE reservation_id=?',(rid,)).fetchone() is not None


def root_id(con,entry):
    while entry['supersedes']:
        entry=con.execute('SELECT * FROM financial_entries WHERE id=?',(entry['supersedes'],)).fetchone()
    return entry['id']


def sync(backend,con,r):
    t=totals(active(con,r['organization_id'],r['property_id'],rid=r['id']))
    status='paid' if Decimal(t['balance'])<=0 else 'partial' if Decimal(t['payments'])>Decimal(t['refunds']) else 'unpaid'
    con.execute('UPDATE reservations SET total_huf=?,payment_status=?,updated_at=? WHERE id=?',
      (int(Decimal(t['charges']).quantize(Decimal('1'),rounding=ROUND_HALF_UP)),status,backend.now_iso(),r['id']))
    import ntak_reporting
    ntak_reporting.capture_reservation(con,r['organization_id'],r['id'])


def post(backend,con,org,prop,body,actor,rid=None):
    import business_days
    if not con.execute('SELECT id FROM properties WHERE id=? AND organization_id=?',(prop,org)).fetchone():raise HTTPException(404,'Property not found')
    con.execute('UPDATE properties SET id=id WHERE id=? AND organization_id=?',(prop,org))
    r=scoped(backend,con,org,rid) if rid else None
    if r and r['property_id']!=prop:raise HTTPException(404,'Property mismatch')
    payload=body.model_dump(mode='json');digest=hashlib.sha256(json.dumps([rid,prop,payload],sort_keys=True).encode()).hexdigest()
    old=con.execute('SELECT id,digest FROM financial_entries WHERE organization_id=? AND request_id=?',(org,str(body.request_id))).fetchone()
    if old:
        if old['digest']!=digest:raise HTTPException(409,{'code':'request_identity_conflict'})
        return {'id':old['id'],'duplicate':True}
    if body.kind not in ('charge','payment') or body.direction not in ('payment','refund'):raise HTTPException(422,'Invalid entry kind')
    quantity=dec(body.quantity,positive=True,places=6);price=dec(body.unit_price,places=6);rate=dec(body.exchange_rate,positive=True,places=8)
    if body.currency=='HUF' and rate!=1:raise HTTPException(422,'HUF exchange rate must be one')
    if body.currency!='HUF' and len(body.exchange_evidence)<3:raise HTTPException(422,'An evidenced HUF exchange rate is required')
    total=Decimal(money(quantity*price));huf=Decimal(money(total*rate))
    if huf>Decimal('999999999999.99') or total>Decimal('999999999999.99'):raise HTTPException(422,{'code':'invalid_decimal'})
    if body.kind=='charge':
        if body.category not in CATEGORIES or (body.subcategory or '') not in (CATEGORIES.get(body.category) or ['']):raise HTTPException(422,'Invalid official charge classification')
        if body.vat not in enum('AfaKulcsSzazalekType'):raise HTTPException(422,'Invalid VAT classification')
        if body.category=='IFA' and (body.vat!='0' or body.in_package):raise HTTPException(422,'IFA must be outside the package with zero VAT')
        if body.category=='SZALLASDIJ' and not body.in_package:raise HTTPException(422,'Accommodation must be in the package')
        if body.payment_method or body.payment_subtype or body.direction!='payment' or body.refund_of:raise HTTPException(422,'Charge cannot have payment fields')
    else:
        if quantity!=1 or body.payment_method not in enum('KoltesTipusType'):raise HTTPException(422,'Invalid payment classification')
        if (body.payment_method=='SZEP_KARTYA' and body.payment_subtype!='SZALLASHELY') or (body.payment_method!='SZEP_KARTYA' and body.payment_subtype):raise HTTPException(422,'Invalid payment subtype')
        if body.category or body.subcategory or body.vat or body.in_package:raise HTTPException(422,'Payment cannot have charge fields')
    for table,key,value in [('physical_units','property_id',body.unit_id),('guest_records','reservation_id',body.guest_id)]:
        if value:
            expected=prop if table=='physical_units' else rid
            if not expected or not con.execute(f'SELECT id FROM {table} WHERE id=? AND organization_id=? AND {key}=?',(value,org,expected)).fetchone():raise HTTPException(404,'Financial association not found')
    if body.voided and not body.supersedes:raise HTTPException(422,'Reversal requires an original entry')
    previous=None
    if body.supersedes:
        previous=con.execute('SELECT * FROM financial_entries WHERE id=? AND organization_id=? AND property_id=?',(body.supersedes,org,prop)).fetchone()
        if not previous or previous['reservation_id']!=rid:raise HTTPException(404,'Original entry not found')
        if previous['kind']!=body.kind or con.execute('SELECT id FROM financial_entries WHERE supersedes=?',(body.supersedes,)).fetchone():raise HTTPException(409,'Only the current matching entry can be corrected')
    if body.kind=='payment' and body.direction=='refund' and body.refund_of:
        original=con.execute('SELECT * FROM financial_entries WHERE id=? AND organization_id=? AND property_id=?',(body.refund_of,org,prop)).fetchone()
        if not original or original['reservation_id']!=rid or original['kind']!='payment' or original['direction']!='payment':raise HTTPException(404,'Original payment not found')
        if original['business_date']>str(body.business_date):raise HTTPException(422,'Refund cannot precede its original payment')
        target=root_id(con,original)
        if target!=body.refund_of:raise HTTPException(422,'Refund must reference the original payment identity')
        refunds=[e for e in active(con,org,prop,rid=rid) if e['direction']=='refund' and e['refund_of']==target and e['id']!=body.supersedes]
        current_payment=next((e for e in active(con,org,prop,rid=rid) if root_id(con,e)==target),None)
        if not current_payment or not body.voided and sum((Decimal(e['total_huf']) for e in refunds),huf)>Decimal(current_payment['total_huf']):raise HTTPException(409,'Refund exceeds the current original payment')
        business_days.mark_dirty(con,org,prop,original['business_date'],actor,body.reason)
    elif body.refund_of:raise HTTPException(422,'Only a refund can reference an original payment')
    if previous and previous['kind']=='payment' and previous['direction']=='payment':
        refunded=sum((Decimal(e['total_huf']) for e in active(con,org,prop,rid=rid) if e['direction']=='refund' and e['refund_of']==root_id(con,previous)),Decimal(0))
        if refunded and (body.voided or huf<refunded):raise HTTPException(409,'Correct linked refunds before reducing the original payment')
        if refunded and str(body.business_date)!=previous['business_date']:raise HTTPException(409,'Correct linked refunds before moving the original payment date')
    # A closed-day change is retained as a normal source correction and flags all affected revisions.
    import business_days
    for d in {str(body.business_date),previous['business_date'] if previous else str(body.business_date)}:
        business_days.mark_dirty(con,org,prop,d,actor,body.reason)
    if r:
        con.execute('INSERT OR IGNORE INTO financial_folios(reservation_id,organization_id,property_id,original_quote_huf,activated_at) VALUES (?,?,?,?,?)',(rid,org,prop,str(r['total_huf']) if r['total_huf'] is not None else None,backend.now_iso()))
    entry={**payload,'id':str(uuid.uuid4()),'organization_id':org,'property_id':prop,'reservation_id':rid,'quantity':format(quantity,'f'),'unit_price':format(price,'f'),'exchange_rate':format(rate,'f'),'total':money(total),'total_huf':money(huf),'request_id':str(body.request_id),'business_date':str(body.business_date),'document_date':str(body.document_date) if body.document_date else None,'in_package':int(body.in_package),'voided':int(body.voided),'digest':digest,'actor_id':actor,'source':'owner_review','posted_at':backend.now_iso()}
    columns=list(entry)
    con.execute('INSERT INTO financial_entries('+','.join(columns)+') VALUES ('+','.join('?' for _ in columns)+')',tuple(entry.values()))
    if r:sync(backend,con,r)
    backend.audit_event(con,org,'financial.post','Operational financial entry recorded.',actor_user_id=actor,entity_type='financial_entry',entity_id=entry['id'],metadata={'kind':body.kind,'reservation_id':rid,'supersedes':body.supersedes})
    return {'id':entry['id'],'duplicate':False}


def folio(backend,con,org,rid):
    r=scoped(backend,con,org,rid);entries=active(con,org,r['property_id'],rid=rid)
    for entry in entries:entry['root_id']=root_id(con,entry)
    return {'managed':managed(con,rid),'reservation_id':rid,'property_id':r['property_id'],'quoted_total_huf':r['total_huf'] if not managed(con,rid) else con.execute('SELECT original_quote_huf FROM financial_folios WHERE reservation_id=?',(rid,)).fetchone()['original_quote_huf'],
      'totals':totals(entries),'entries':entries,'history':[dict(e) for e in con.execute('SELECT * FROM financial_entries WHERE reservation_id=? AND organization_id=? ORDER BY posted_at,id',(rid,org))],
      'recording_only':True,'categories':CATEGORIES,'vat_rates':enum('AfaKulcsSzazalekType'),'payment_methods':enum('KoltesTipusType')}


def install(backend):
    @backend.app.get('/api/properties/{property_id}/financial-entries')
    def property_finance(property_id:str,business_date:date,rosa_session:str|None=Cookie(default=None)):
        user=backend.require_user(rosa_session);backend.require_roles(user,'owner','manager')
        with backend.db() as con:
            if not con.execute('SELECT id FROM properties WHERE id=? AND organization_id=?',(property_id,user['organization_id'])).fetchone():raise HTTPException(404,'Property not found')
            entries=[e for e in active(con,user['organization_id'],property_id,day=business_date) if not e['reservation_id']]
            for entry in entries:entry['root_id']=root_id(con,entry)
            return {'business_date':str(business_date),'entries':entries,'totals':totals(entries),'categories':CATEGORIES,'vat_rates':enum('AfaKulcsSzazalekType'),'payment_methods':enum('KoltesTipusType'),
              'history':[dict(r) for r in con.execute('SELECT * FROM financial_entries WHERE organization_id=? AND property_id=? AND reservation_id IS NULL AND business_date=? ORDER BY posted_at,id',(user['organization_id'],property_id,str(business_date)))]}
    @backend.app.get('/api/reservations/{reservation_id}/folio')
    def get(reservation_id:str,rosa_session:str|None=Cookie(default=None)):
        user=backend.require_user(rosa_session);backend.require_roles(user,'owner','manager')
        with backend.db() as con:return folio(backend,con,user['organization_id'],reservation_id)
    @backend.app.post('/api/reservations/{reservation_id}/folio')
    def create(reservation_id:str,body:Posting,rosa_session:str|None=Cookie(default=None)):
        user=backend.require_user(rosa_session);backend.require_roles(user,'owner','manager')
        with backend.db() as con:
            r=scoped(backend,con,user['organization_id'],reservation_id)
            return post(backend,con,user['organization_id'],r['property_id'],body,user['id'],reservation_id)
    @backend.app.post('/api/properties/{property_id}/financial-entries')
    def other(property_id:str,body:Posting,rosa_session:str|None=Cookie(default=None)):
        user=backend.require_user(rosa_session);backend.require_roles(user,'owner','manager')
        with backend.db() as con:return post(backend,con,user['organization_id'],property_id,body,user['id'])
