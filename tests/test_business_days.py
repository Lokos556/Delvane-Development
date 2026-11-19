from datetime import timedelta,datetime,timezone
from decimal import Decimal
import json
import uuid
import pytest
import app
import business_days as days
import financial_ledger as ledger
import guest_reporting
from test_flutter_reservation_reception import client,login,body
from test_reservation_allocations import setup as unit_setup,assign
from test_actual_stays import act
from test_guest_reporting_profile import PROFILE
from test_ntak_reporting import CONFIG,BASE
from test_financial_ledger import charge,payment

PROP='/api/properties/prop_flora'


def setup(client):
    rt,units=unit_setup(client)
    with app.db() as con:
        ids=[r['id'] for r in con.execute("SELECT id FROM reservations WHERE property_id='prop_flora' AND organization_id='org_casa_rosa' AND status='confirmed'")]
    for rid in ids:assert client.delete('/api/reservations/'+rid).status_code==200
    return rt,units



def calendar(client,start,automatic=False):
    r=client.put(PROP+'/business-calendar',json={'start_date':str(start),'automatic':automatic,'reason':'Fictional calendar setup'})
    assert r.status_code==200,r.text


def operating(client,day,value=True):
    r=client.put(PROP+'/business-days/'+str(day),json={'operating':value,'reason':'Fictional operating calendar'})
    assert r.status_code==200,r.text


def close(client,day,correction=None):
    return client.post(PROP+'/business-days/'+str(day)+'/close',json={'reason':'Reviewed actual source records','correction_reason':correction})


def test_closed_property_chronology_automatic_restart_and_scope(client):
    rt,units=setup(client);day=app.date.today()-timedelta(days=2);calendar(client,day,True)
    operating(client,day,False);client.put(BASE,json=CONFIG)
    result=close(client,day);assert result.status_code==200,result.text
    assert close(client,day).json()['duplicate']
    with app.db() as con:
        row=con.execute('SELECT * FROM daily_snapshots').fetchone();facts=app.decrypt_json(row['encrypted_facts'])
        assert not facts['operating'] and facts['guest_nights']==0
        job=json.loads(con.execute('SELECT payload_json FROM ntak_jobs WHERE id=?',(row['job_id'],)).fetchone()['payload_json'])['napiFeltoltes']
        assert job['szobaAdatok']=={'osszesSzoba':4,'oooSzobak':4,'oosSzobak':0,'kiadottSzobak':0,'kiadhatoSzobak':0}
        assert job['ferohelyAdatok']['oooFerohelyKapacitas']==10
        assert len(job['uzemenKivuliSzobak']['lakoegyseg'])==4
    operating(client,day+timedelta(days=1),False)
    app.init_db()
    with app.db() as con:
        assert days.automatic(app,con)==1
        assert days.automatic(app,con)==0
        days.migrate(app,con);days.migrate(app,con)
    assert close(client,app.date.today()).status_code==422
    login(client,'cleaner');assert client.get(PROP+'/business-days/'+str(day)).status_code==403
    login(client);assert client.get('/api/properties/prop_other/business-days/'+str(day)).status_code==404
    client.headers.pop('X-Rosa-CSRF');assert close(client,day).status_code==403


def party(client,day,departure,count,uid,name,frozen=True):
    p=body();p.update(guest_name=name,arrival_date=str(day),departure_date=str(departure),guest_count=count,total_huf=0,reporting={'piaciSzegmens':'SZABADIDOS_EGYENI','ertekesitesiCsatorna':'DIREKT_HAGYOMANYOS'})
    made=client.post('/api/reservations',json=p);assert made.status_code==200,made.text
    rid=made.json()['id'];assert assign(client,rid,p,[uid]).status_code==200
    with app.db() as con:
        gids=[r['id'] for r in con.execute('SELECT id FROM guest_records WHERE reservation_id=? ORDER BY id',(rid,))]
        con.execute("UPDATE guest_records SET nationality='HU' WHERE reservation_id=?",(rid,))
    for gid in gids:
        assert client.put(f'/api/registration/records/{gid}/reporting-profile',json={**PROFILE,'ifa_status':'im2','effective_from':str(day)}).status_code==200
        if frozen:
            with app.db() as con:guest_reporting.identity_for_submission(app,con,'org_casa_rosa','prop_flora',gid,canonical_identity='Fictional '+gid+' Budapest 1986.01.01.')
    return rid,gids


def post(client,rid,p,day,uid=None):
    p={**p,'business_date':str(day)}
    if uid:p['unit_id']=uid
    result=client.post(f'/api/reservations/{rid}/folio',json=p);assert result.status_code==200,result.text
    return result.json()['id']


def snapshot(client,day):
    with app.db() as con:
        s=dict(con.execute('SELECT * FROM daily_snapshots WHERE business_date=? ORDER BY revision DESC LIMIT 1',(str(day),)).fetchone())
        return s,app.decrypt_json(s['encrypted_facts']),json.loads(con.execute('SELECT payload_json FROM ntak_jobs WHERE id=?',(s['job_id'],)).fetchone()['payload_json'])


def test_normal_closing_three_actual_nights_two_units_ooo_oos_and_identity_gate(client):
    rt,units=setup(client);day=app.date.today()-timedelta(days=2);calendar(client,day);operating(client,day)
    assert client.put(PROP+'/ifa-rates',json={'effective_from':str(day),'tax_type':'TETELES','rate':'400','reason':'Fictional tax rate'}).status_code==200
    client.put(BASE,json=CONFIG)
    first,g1=party(client,day,day+timedelta(days=2),2,units[0][0],'Fictional first',False)
    second,g2=party(client,day,day+timedelta(days=2),1,units[1][0],'Fictional second',False)
    at=datetime.fromisoformat(str(day)+'T14:00:00+01:00')
    assert act(client,first,g1,at,uid=units[0][0])[0].status_code==200
    assert act(client,second,g2,at,uid=units[1][0])[0].status_code==200
    for rid,uid,amount,gid in [(first,units[0][0],'20000',g1[0]),(second,units[1][0],'25000',g2[0])]:
        client.put(f'/api/registration/records/{gid}/reporting-profile',json={**PROFILE,'ifa_status':'KOTELES','effective_from':str(day),'reason':'Fictional statutory liability'})
        item=charge();item.update(category='SZALLASDIJ',subcategory=None,vat='5',in_package=True,unit_price=amount);post(client,rid,item,day,uid)
        item=charge();item.update(category='IFA',subcategory=None,vat='0',unit_price='400');post(client,rid,item,day,uid)
    for category,sub,vat,amount in [('KOZFURDO','FURDO_PROGRAM','18','5800'),('ETEL','FOETEL','5','4600'),('EGYEB','EGYEB_VENDEGLATAS','27','1000'),('ALKOHOLOSITAL','ITALCSOMAG','27','10000')]:
        item=charge();item.update(category=category,subcategory=sub,vat=vat,unit_price=amount,business_date=str(day))
        result=client.post(PROP+'/financial-entries',json=item);assert result.status_code==200,result.text
    item=payment('BANKKARTYA','21400');item['business_date']=str(day)
    assert client.post(PROP+'/financial-entries',json=item).status_code==200
    for state,u in zip(['OOO','OOS'],units[2:]):
        r=client.post(PROP+'/physical-units/'+u[0]+'/periods',json={'state':state,'date_from':str(day),'date_to':str(day),'reason':'Fictional unavailable room'});assert r.status_code==200,r.text
    result=close(client,day);assert result.status_code==200,result.text
    s,f,p=snapshot(client,day);assert f['guest_nights']==3 and f['sold_units']==2
    assert s['blocker']=='identity_normalization_unresolved'
    frozen_facts=s['encrypted_facts']
    for gid in g1+g2:
        with app.db() as con:guest_reporting.identity_for_submission(app,con,'org_casa_rosa','prop_flora',gid,canonical_identity='Fictional '+gid+' Budapest 1986.01.01.')
    assert client.post(PROP+'/business-days/'+str(day)+'/reporting-recovery').status_code==200
    s,f,p=snapshot(client,day)
    assert s['encrypted_facts']==frozen_facts and s['blocker'] is None
    data=p['napiFeltoltes'];assert data['szobaAdatok']['oooSzobak']==data['szobaAdatok']['oosSzobak']==1
    assert data['ifaAdatok']['ifaMertek']=='400.00' and f['ifa_obligation_huf']=='800.00'
    assert sum(Decimal(x['osszeg']) for x in data['egyebTerhelesek']['egyebTerheles'])==21400
    assert data['egyebKoltesek']['egyebKoltes'][0]['koltesTipus']=='BANKKARTYA'
    other=client.get(PROP+'/financial-entries',params={'business_date':str(day)}).json()
    assert len(other['entries'])==len(other['history'])==5
    assert data['szobaAdatok']['kiadottSzobak']==2 and len(data['lakoegysegEjszakak']['lakoegysegEjszaka'])==2


def test_planned_registration_not_actual_and_transaction_rollback(client,monkeypatch):
    rt,units=setup(client);day=app.date.today()-timedelta(days=2);calendar(client,day);operating(client,day)
    party(client,day,day+timedelta(days=1),1,units[0][0],'Fictional expected')
    assert close(client,day).status_code==409
    with app.db() as con:assert con.execute('SELECT COUNT(*) n FROM daily_snapshots').fetchone()['n']==0
    # A consistent closed-property day fails atomically if capture fails.
    previous=day-timedelta(days=1);calendar(client,previous);operating(client,previous,False)
    monkeypatch.setattr(days,'capture',lambda *a:(_ for _ in ()).throw(RuntimeError('offline failure')))
    with pytest.raises(RuntimeError):close(client,previous)
    with app.db() as con:
        assert con.execute('SELECT state FROM business_days WHERE business_date=?',(str(previous),)).fetchone()['state']=='open'
        assert con.execute('SELECT COUNT(*) n FROM daily_snapshots').fetchone()['n']==0


@pytest.mark.parametrize('outcome,expected,reason',[('rejected','UJ','TECH_HIBA_ADATJAVITAS'),('review_required','MODOSITO','TECH_HIBA_ADATJAVITAS'),('succeeded','MODOSITO','VENDEG_VAGY_IFA_JAVITAS'),('accepted','PENDING','TECH_HIBA_ADATJAVITAS')])
def test_outcome_aware_source_corrections_and_frozen_identity(client,outcome,expected,reason):
    rt,units=setup(client);day=app.date.today()-timedelta(days=2);calendar(client,day);operating(client,day);client.put(BASE,json=CONFIG)
    client.put(PROP+'/ifa-rates',json={'effective_from':str(day),'tax_type':'TETELES','rate':'400','reason':'Fictional rate'})
    rid,gids=party(client,day,day+timedelta(days=2),2,units[0][0],'Fictional corrected party')
    at=datetime.fromisoformat(str(day)+'T14:00:00+01:00');assert act(client,rid,gids,at,uid=units[0][0])[0].status_code==200
    first=post(client,rid,charge(),day,units[0][0]);assert close(client,day).status_code==200
    old,f,p=snapshot(client,day)
    with app.db() as con:con.execute('UPDATE ntak_jobs SET state=?,error_code=NULL WHERE id=?',(outcome,old['job_id']))
    correction=charge();correction.update(supersedes=first,unit_price='3000');post(client,rid,correction,day,units[0][0])
    before=[g['vendegId'] for n in p['napiFeltoltes']['lakoegysegEjszakak']['lakoegysegEjszaka'] for g in n['vendegek']['vendeg']]
    res=client.put(f'/api/registration/records/{gids[0]}/reporting-profile',json={**PROFILE,'date_of_birth':'1987-02-11','ifa_status':'im5','source':'correction','effective_from':str(day),'reason':'Fictional DOB and exemption correction'})
    assert res.status_code==200,res.text
    result=close(client,day,reason);assert result.status_code==200,result.text
    new,f,p=snapshot(client,day);assert new['revision']==2 and new['classification']==expected
    with app.db() as con:
        original=con.execute('SELECT encrypted_facts FROM daily_snapshots WHERE id=?',(old['id'],)).fetchone()['encrypted_facts'];assert original==old['encrypted_facts']
        assert con.execute('SELECT COUNT(*) n FROM financial_entries WHERE reservation_id=?',(rid,)).fetchone()['n']==2
    if expected=='PENDING':assert new['blocker']=='prior_closing_outcome_pending'
    else:
        cls=p['napiFeltoltes']['napiZarasBesorolas'];assert cls['besorolas']==expected
        if expected=='MODOSITO':assert cls['indoklas']==reason and len(cls['jegyzokonyvAzonosito'])==25
        after=[g for n in p['napiFeltoltes']['lakoegysegEjszakak']['lakoegysegEjszaka'] for g in n['vendegek']['vendeg']]
        assert sorted(g['vendegId'] for g in after)==sorted(before)
        assert any(g['szuletesiEv']==1987 and g['ifaStatusz']=='im5' for g in after)


def test_nz03_all_lines_snapshot_and_seven_payments(client):
    from pathlib import Path
    rt,units=setup(client);day=app.date.today()-timedelta(days=2);calendar(client,day);operating(client,day);client.put(BASE,json=CONFIG)
    client.put(PROP+'/ifa-rates',json={'effective_from':str(day),'tax_type':'TETELES','rate':'400','reason':'Fictional rate'})
    first,g1=party(client,day,day+timedelta(days=2),2,units[0][0],'Fictional first party')
    second,g2=party(client,day,day+timedelta(days=2),1,units[2][0],'Fictional worksheet party')
    at=datetime.fromisoformat(str(day)+'T14:00:00+01:00')
    for rid,gids,uid in [(first,g1,units[0][0]),(second,g2,units[2][0])]:assert act(client,rid,gids,at,uid=uid)[0].status_code==200
    # Explicit zero complimentary charge is legitimate source data, not a fabricated revenue.
    p=charge();p.update(unit_price='0');post(client,first,p,day,units[0][0])
    rows=json.loads((Path(__file__).parent/'fixtures/ntak_official_charge_lines.json').read_text(encoding='utf8'))
    for row in rows:
        p=charge();p.update(category=row['category'],subcategory=row['subcategory'],vat=row['vat'],in_package=row['in_package'],unit_price=row['amount'],description=row['source_cells'][1]);post(client,second,p,day,units[2][0])
    for method in ledger.enum('KoltesTipusType'):post(client,second,payment(method,'4066' if method in ('UTOLAGOS','EGYEB') else '4067'),day,units[2][0])
    assert close(client,day).status_code==200
    s,f,p=snapshot(client,day);assert s['blocker'] is None
    assert f['guest_nights']==3 and f['sold_units']==2 and f['totals']['charges']==f['totals']['payments']=='28467.00'
    selected=[r for r in p['napiFeltoltes']['lakoegysegEjszakak']['lakoegysegEjszaka'] if r['ertekesitettLakoegyseg']['lakoegyseg']['szobaszam']=='103'][0]['ertekesitettLakoegyseg']
    charges=[c for g in selected['terhelesek'].values() for v in g.values() for c in v]
    assert len(charges)==69 and sum(Decimal(c['osszeg']) for c in charges)==28467
    assert len(selected['koltesek']['koltes'])==7


def test_nz05_day_use_zero_nights_and_post_stay_invoice_dates(client):
    from test_day_use import make
    rt,units=setup(client);day=app.date.today()-timedelta(days=1);calendar(client,day);operating(client,day);client.put(BASE,json=CONFIG)
    client.put(PROP+'/ifa-rates',json={'effective_from':str(day),'tax_type':'TETELES','rate':'400','reason':'Fictional rate'})
    rid,gids=party(client,day-timedelta(days=2),day-timedelta(days=1),1,units[0][0],'Fictional departed')
    start=datetime.fromisoformat(str(day-timedelta(days=2))+'T14:00:00+01:00')
    assert act(client,rid,gids,start,uid=units[0][0])[0].status_code==200
    assert act(client,rid,gids,start+timedelta(hours=20),kind='depart')[0].status_code==200
    made,p=make(client,units[2:],offset=-1);assert made.status_code==200,made.text
    day_id=made.json()['id']
    assert client.patch('/api/reservations/'+day_id,json={'reporting':{'piaciSzegmens':'ISMERETLEN','ertekesitesiCsatorna':'KOZVETITO_ONLINE'}}).status_code==200
    with app.db() as con:gs=[r['id'] for r in con.execute('SELECT id FROM guest_records WHERE reservation_id=? ORDER BY id',(day_id,))]
    at=datetime.fromisoformat(str(day)+'T10:30:00+01:00')
    for gid,u,amount,method in zip(gs,units[2:],['28000','34500'],['KESZPENZ','BANKKARTYA']):
        client.put(f'/api/registration/records/{gid}/reporting-profile',json={**PROFILE,'ifa_status':'im1','nationality_country':'HU','effective_from':str(day)})
        with app.db() as con:guest_reporting.identity_for_submission(app,con,'org_casa_rosa','prop_flora',gid,canonical_identity='Fictional minor '+gid+' Debrecen 2013.03.07.')
        assert act(client,day_id,[gid],at,uid=u[0])[0].status_code==200
        assert act(client,day_id,[gid],at+timedelta(hours=1),kind='depart')[0].status_code==200
        p=charge();p.update(category='SZALLASDIJ',subcategory=None,vat='5',in_package=True,unit_price=amount);post(client,day_id,p,day,u[0]);post(client,day_id,payment(method,amount),day,u[0])
    p=charge();p.update(category='EGYEB',subcategory='EGYEB',unit_price='10000');post(client,rid,p,day)
    post(client,rid,payment('BANKKARTYA','10000',document_date=str(day)),day)
    result=close(client,day);assert result.status_code==200,result.text
    s,f,p=snapshot(client,day);assert s['blocker'] is None
    data=p['napiFeltoltes'];assert f['guest_nights']==0 and f['sold_units']==0
    assert data['szobaAdatok']['kiadottSzobak']==0
    assert len(data['lakoegysegEjszakak']['lakoegysegEjszaka'])==2
    assert data['tartozkodastKovetoTerhelesek']['tartozkodastKovetoTerheles'][0]['datum']==str(day-timedelta(days=1))
    assert data['tartozkodastKovetoKoltesek']['tartozkodastKovetoKoltes'][0]['datum']==str(day)
    assert f['totals']['charges']==f['totals']['payments']=='72500.00'


def test_nz04_exact_tax_and_dob_correction_preserves_original_snapshot(client):
    rt,units=setup(client);day=app.date.today()-timedelta(days=2);calendar(client,day);operating(client,day);client.put(BASE,json=CONFIG)
    client.put(PROP+'/ifa-rates',json={'effective_from':str(day),'tax_type':'TETELES','rate':'400','reason':'Fictional rate'})
    rid,gids=party(client,day,day+timedelta(days=2),2,units[2][0],'Fictional NZ04 party')
    profile={**PROFILE,'date_of_birth':'1986-01-01','ifa_status':'KOTELES','effective_from':str(day),'reason':'Fictional original taxable profile'}
    assert client.put(f'/api/registration/records/{gids[0]}/reporting-profile',json=profile).status_code==200
    assert act(client,rid,gids,datetime.fromisoformat(str(day)+'T14:00:00+01:00'),uid=units[2][0])[0].status_code==200
    item=charge();item.update(category='SZALLASDIJ',subcategory=None,vat='5',in_package=True,unit_price='28000');post(client,rid,item,day,units[2][0])
    item=charge();item.update(category='IFA',subcategory=None,vat='0',unit_price='400',guest_id=gids[0]);tax_id=post(client,rid,item,day,units[2][0])
    assert close(client,day).status_code==200
    old,f,p=snapshot(client,day);assert f['guest_nights']==2 and f['sold_units']==1 and f['ifa_obligation_huf']=='400.00'
    with app.db() as con:con.execute("UPDATE ntak_jobs SET state='succeeded',error_code=NULL WHERE id=?",(old['job_id'],))
    assert client.put(f'/api/registration/records/{gids[0]}/reporting-profile',json={**profile,'date_of_birth':'1987-02-11','ifa_status':'im5','source':'correction','reason':'Fictional authority exemption and DOB correction'}).status_code==200
    item.update(request_id=str(uuid.uuid4()),supersedes=tax_id,voided=True,reason='Fictional reversal of erroneous IFA charge');post(client,rid,item,day,units[2][0])
    assert close(client,day,'VENDEG_VAGY_IFA_JAVITAS').status_code==200
    new,f,p=snapshot(client,day);assert f['guest_nights']==2 and f['ifa_obligation_huf']=='0.00'
    assert p['napiFeltoltes']['napiZarasBesorolas']['besorolas']=='MODOSITO'
    assert f['totals']['charges']=='28000.00'
    with app.db() as con:assert con.execute('SELECT encrypted_facts FROM daily_snapshots WHERE id=?',(old['id'],)).fetchone()['encrypted_facts']==old['encrypted_facts']


def test_timezone_boundary_historical_rate_and_pending_outcome_recovery(client):
    rt,units=setup(client);day=app.date.today()-timedelta(days=2)
    assert client.put(PROP+'/business-calendar',json={'start_date':str(day),'timezone':'America/New_York','reason':'Fictional timezone'}).status_code==200
    operating(client,day);client.put(BASE,json=CONFIG)
    client.put(PROP+'/ifa-rates',json={'effective_from':str(day),'tax_type':'TETELES','rate':'400','reason':'Fictional initial rate'})
    rid,gids=party(client,day,day+timedelta(days=2),1,units[0][0],'Fictional boundary guest')
    # 01:00 UTC next day is still the reviewed local night.
    at=datetime.fromisoformat(str(day+timedelta(days=1))+'T01:00:00+00:00')
    assert act(client,rid,gids,at,uid=units[0][0])[0].status_code==200
    item=charge();post(client,rid,item,day,units[0][0])
    assert close(client,day).status_code==200
    old,f,p=snapshot(client,day);assert f['guest_nights']==1 and f['timezone']=='America/New_York'
    with app.db() as con:con.execute("UPDATE ntak_jobs SET state='accepted',error_code=NULL WHERE id=?",(old['job_id'],))
    corrected=client.put(PROP+'/ifa-rates',json={'effective_from':str(day),'tax_type':'TETELES','rate':'500','reason':'Fictional documented rate correction'});assert corrected.json()['corrected']
    assert close(client,day,'TECH_HIBA_ADATJAVITAS').status_code==200
    pending,_,_=snapshot(client,day);assert pending['blocker']=='prior_closing_outcome_pending'
    with app.db() as con:
        con.execute("UPDATE ntak_jobs SET state='review_required',error_code=NULL WHERE id=?",(old['job_id'],))
        assert con.execute('SELECT rate FROM property_ifa_rates WHERE property_id=?',('prop_flora',)).fetchone()['rate']=='400.00'
        assert con.execute('SELECT rate FROM property_ifa_rate_corrections').fetchone()['rate']=='500.00'
    client.post(PROP+'/business-days/'+str(day)+'/reporting-recovery')
    resolved,f,p=snapshot(client,day);assert resolved['blocker'] is None
    assert p['napiFeltoltes']['napiZarasBesorolas']['besorolas']=='MODOSITO'
    assert p['napiFeltoltes']['ifaAdatok']['ifaMertek']=='500.00'


def test_concurrent_closing_creates_one_logical_snapshot(client):
    from concurrent.futures import ThreadPoolExecutor
    rt,units=setup(client);day=app.date.today()-timedelta(days=1);calendar(client,day);operating(client,day,False);client.put(BASE,json=CONFIG)
    def finalize(_):
        with app.db() as con:return days.close(app,con,'org_casa_rosa','prop_flora',day,days.Close(reason='Fictional concurrent close'),'usr_owner')
    with ThreadPoolExecutor(2) as pool:out=list(pool.map(finalize,range(2)))
    assert sum(r['duplicate'] for r in out)==1
    with app.db() as con:
        assert con.execute('SELECT COUNT(*) n FROM daily_snapshots').fetchone()['n']==1
        assert con.execute("SELECT COUNT(*) n FROM ntak_jobs WHERE operation='daily_close'").fetchone()['n']==1


def test_linked_refund_corrects_original_day_without_negative_reporting(client):
    rt,units=setup(client);day=app.date.today()-timedelta(days=2);calendar(client,day);operating(client,day);client.put(BASE,json=CONFIG)
    client.put(PROP+'/ifa-rates',json={'effective_from':str(day),'tax_type':'NINCS','rate':'0','reason':'Fictional zero rate'})
    rid,gids=party(client,day,day+timedelta(days=2),1,units[0][0],'Fictional refund guest')
    at=datetime.fromisoformat(str(day)+'T14:00:00+01:00');assert act(client,rid,gids,at,uid=units[0][0])[0].status_code==200
    item=charge();item.update(unit_price='100');post(client,rid,item,day,units[0][0])
    original=post(client,rid,payment('BANKKARTYA','100'),day,units[0][0]);assert close(client,day).status_code==200
    old,_,_=snapshot(client,day)
    with app.db() as con:con.execute("UPDATE ntak_jobs SET state='succeeded',error_code=NULL WHERE id=?",(old['job_id'],))
    refund=payment('BANKKARTYA','30',direction='refund',refund_of=original);post(client,rid,refund,day+timedelta(days=1),units[0][0])
    assert close(client,day,'TERHELES_VAGY_KOLTES_JAV').status_code==200
    new,f,p=snapshot(client,day)
    item=p['napiFeltoltes']['lakoegysegEjszakak']['lakoegysegEjszaka'][0]['ertekesitettLakoegyseg']['koltesek']['koltes'][0]
    assert item['osszeg']=='70.00' and item['koltesTipus']=='BANKKARTYA'
    operating(client,day+timedelta(days=1));assert close(client,day+timedelta(days=1)).status_code==200
    current,f,p=snapshot(client,day+timedelta(days=1));assert current['blocker'] is None
    assert f['totals']['refunds']=='30.00'
    assert client.get(f'/api/reservations/{rid}/folio').json()['totals']['balance']=='30.00'
    with app.db() as con:
        assert con.execute('SELECT total_huf FROM financial_entries WHERE id=?',(original,)).fetchone()['total_huf']=='100.00'
