import json
import uuid
from pathlib import Path
from decimal import Decimal
import app
import financial_ledger as ledger
from test_flutter_reservation_reception import client,login,body


def reservation(client):
    login(client);p=body();p['total_huf']=28000
    r=client.post('/api/reservations',json=p);assert r.status_code==200,r.text
    return r.json()['id']


def charge(**kwargs):
    return dict(request_id=str(uuid.uuid4()),kind='charge',business_date=str(app.date.today()),description='Fictional service',unit_price='1',category='ETEL',subcategory='FOETEL',vat='27',reason='Observed operational charge',**kwargs)


def test_all_69_official_lines_decimal_metadata_and_restart(client):
    rid=reservation(client);url=f'/api/reservations/{rid}/folio'
    rows=json.loads((Path(__file__).parent/'fixtures/ntak_official_charge_lines.json').read_text(encoding='utf8'))
    assert len(rows)==69 and sum(Decimal(r['amount']) for r in rows)==28467
    for row in rows:
        p=charge();p.update(category=row['category'],subcategory=row['subcategory'],vat=row['vat'],in_package=row['in_package'],unit_price=row['amount'],description=row['source_cells'][1])
        res=client.post(url,json=p);assert res.status_code==200,res.text
        assert client.post(url,json=p).json()['duplicate']
    data=client.get(url).json();assert len(data['entries'])==69 and data['totals']['charges']=='28467.00'
    assert [(e['category'],e['subcategory'],e['vat'],e['in_package']) for e in data['entries']] # compare by descriptions below
    assert sorted((e['category'],e['subcategory'] or '',e['total_huf']) for e in data['entries'])==sorted((r['category'],r['subcategory'] or '',format(Decimal(r['amount']),'.2f')) for r in rows)
    assert client.get(f'/api/reservations/{rid}/detail').json()['reservation']['total_huf']==28467
    app.init_db()
    assert client.get(url).json()['totals']['charges']=='28467.00'
    with app.db() as con:ledger.migrate(app,con);ledger.migrate(app,con)


def test_rounding_corrections_atomicity_scope_and_validation(client):
    rid=reservation(client);url=f'/api/reservations/{rid}/folio'
    p=charge(quantity='3');p['unit_price']='0.335'
    res=client.post(url,json=p);assert res.status_code==200,res.text
    # Exact decimal multiplication, then line rounding: 3 * .335 = 1.005.
    assert client.get(url).json()['totals']['charges']=='1.01'
    assert client.post(url,json={**p,'unit_price':'3'}).status_code==409
    fix={**p,'request_id':str(uuid.uuid4()),'supersedes':res.json()['id'],'unit_price':'1.01'}
    assert client.post(url,json=fix).status_code==200
    assert client.post(url,json={**fix,'request_id':str(uuid.uuid4())}).status_code==409
    for value in ('NaN','Infinity','-1'):
        bad=charge();bad['unit_price']=value;assert client.post(url,json=bad).status_code==422
    assert len(client.get(url).json()['history'])==2
    assert client.post('/api/reservations/res_other_secret/folio',json=charge()).status_code==404
    assert client.post(url,json=charge(unit_id='other-unit')).status_code==404
    login(client,'cleaner');assert client.get(url).status_code==403
    login(client);client.headers.pop('X-Rosa-CSRF');assert client.post(url,json=charge()).status_code==403


def payment(method='KESZPENZ',amount='4067',**extra):
    return {'request_id':str(uuid.uuid4()),'kind':'payment','business_date':str(app.date.today()),'description':'Fictional payment record','unit_price':amount,'payment_method':method,'reason':'Owner recorded payment','payment_subtype':'SZALLASHELY' if method=='SZEP_KARTYA' else None,**extra}


def test_seven_settlements_refund_overpayment_and_ledger_authority(client):
    rid=reservation(client);url=f'/api/reservations/{rid}/folio'
    p=charge();p['unit_price']='28467';assert client.post(url,json=p).status_code==200
    for method in ledger.enum('KoltesTipusType'):
        amount='4066' if method in ('UTOLAGOS','EGYEB') else '4067'
        res=client.post(url,json=payment(method,amount));assert res.status_code==200,res.text
    t=client.get(url).json()['totals'];assert t=={'charges':'28467.00','payments':'28467.00','refunds':'0.00','balance':'0.00'}
    assert client.post(url,json=payment(amount='500')).status_code==200
    assert client.get(url).json()['totals']['balance']=='-500.00'
    refund=client.post(url,json=payment(amount='200',direction='refund'));assert refund.status_code==200
    assert client.get(url).json()['totals']['balance']=='-300.00'
    assert client.patch('/api/reservations/'+rid,json={'total_huf':1}).status_code==409
    assert client.patch('/api/reservations/'+rid+'/operations',json={'payment_status':'unpaid'}).status_code==409
    fixed=payment(amount='100',direction='refund',supersedes=refund.json()['id'])
    assert client.post(url,json=fixed).status_code==200
    assert client.get(url).json()['totals']['balance']=='-400.00'


def test_concurrent_correction_claims_and_rollback(client):
    from concurrent.futures import ThreadPoolExecutor
    rid=reservation(client);url=f'/api/reservations/{rid}/folio';first=client.post(url,json=charge()).json()['id']
    def write(i):
        p=charge();p.update(supersedes=first,unit_price=str(i))
        try:
            with app.db() as con:return ledger.post(app,con,'org_casa_rosa','prop_flora',ledger.Posting(**p),'usr_owner',rid)
        except Exception as e:return e
    with ThreadPoolExecutor(2) as pool:results=list(pool.map(write,[2,3]))
    assert sum(isinstance(r,dict) for r in results)==1
    with app.db() as con:
        before=con.execute('SELECT COUNT(*) n FROM financial_entries').fetchone()['n']
    try:
        with app.db() as con:
            ledger.post(app,con,'org_casa_rosa','prop_flora',ledger.Posting(**charge()),'usr_owner',rid)
            raise RuntimeError('offline rollback')
    except RuntimeError:pass
    with app.db() as con:assert con.execute('SELECT COUNT(*) n FROM financial_entries').fetchone()['n']==before
