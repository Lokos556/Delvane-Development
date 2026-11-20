"""Fictional offline THF v700 contract cases; never interoperability evidence."""
from datetime import date,datetime,timezone,timedelta
import hashlib,json,uuid
import pytest
from lxml import etree as E
import viza_contracts as c

NOW=datetime(2026,11,20,12,tzinfo=timezone.utc)
UID=str(uuid.uuid4())
P=c.Person(csaladnev='Fictional',utonev='Guest',szuletesiDatum=date(1990,1,1),allampolgarsagKod='HU',nem='NO',okmanyTipus='UTLEVEL',okmanyAzonositoSzam='FICTIONAL')
HEADER={'uzenetAzonosito':UID,'szallashely':c.Property(adatszolgaltatasiAzonosito='TEST0000',szallasNev='Fictional House',szallashelySzolgaltatoAdoszam='12345678-1-12',szallashelySzolgaltatoNev='Fictional Provider'),'bejelentesIdopontja':NOW,'pmsValidaciosUzenet':c.Validation(ellenorzoString='OFFLINE',alairoTanusitvany='UNSIGNED',alairas='UNSIGNED')}
def arrival():return c.Arrival(erkezesAzonosito=UID,erkezesIdeje=NOW-timedelta(days=1),tavozasVarhatoDatuma=date(2026,11,21),manualisanRogzitettAdat=P)
def request(op):
    if op=='allapotLekerdezes':return c.StatusRequest()
    if op=='bekuldetlenAdatLista':return c.ListRequest(bekuldetlenAdatTipus='HIBAS')
    if op.startswith('erkezes'):return c.ArrivalRequest(**HEADER,erkezoVendeg=[arrival()])
    return c.DepartureRequest(**HEADER,tavozoVendeg=[c.Departure(erkezesAzonosito=UID,tavozasIdeje=NOW)])
def response(op):
    if op=='allapotLekerdezes':return c.Status(szoftverVerzio=None,allapotKod='WARNING|VIZA-OFFLINE|CERT-WARNING',bekuldetlenUzenetekSzama=2,hibasUzenetekSzama=1,idoPecset=NOW)
    if op=='bekuldetlenAdatLista':return c.Listing(eredmenyKod='OK',bekuldetlenAdat=[c.Unsent(uzenetAzonosito=UID,adatszolgaltatasiAzonosito='TEST0000')])
    return c.Receipt(sikeresBefogadas=False,fogadasAzonosito=UID,fogadasIdeje=NOW,hibaLista=[c.Outcome(erkezesAzonosito=UID,hibaKod='EF0001;EF0033,EF7050',hibaSzoveg='Fictional errors')])
@pytest.mark.parametrize('op',list(c.OPERATIONS))
@pytest.mark.parametrize('is_response',[False,True])
def test_four_contract_paths(op,is_response):
    dto=response(op) if is_response else request(op)
    raw=c.serialize(op,dto,response=is_response,envelope=True,now=NOW)
    assert c.parse(op,raw,response=is_response)==dto

def test_provenance_schema_hash_and_no_external_imports():
    manifest=json.loads((c.ROOT/'PROVENANCE.json').read_text(encoding='utf8'))
    for name,sha in manifest['files'].items():assert hashlib.sha256((c.ROOT/name).read_bytes()).hexdigest()==sha
    assert len(c.ERRORS)==73 and len(c.COUNTRIES)==291
    assert not E.parse(str(c.ROOT/'thf-v700.xsd')).xpath('//*[local-name()="import" or local-name()="include"]')

@pytest.mark.parametrize('count',[0,1,10,11])
def test_batch_bounds(count):
    if 1<=count<=10:
        dto=c.ArrivalRequest(**HEADER,erkezoVendeg=[arrival().model_copy(update={'erkezesAzonosito':str(uuid.uuid4())}) for _ in range(count)]);c.serialize('erkezesiAdatokBekuldese',dto,now=NOW)
    else:
        with pytest.raises(ValueError):c.ArrivalRequest(**HEADER,erkezoVendeg=[arrival()]*count)

def test_nil_fields_order_and_invalid_documentation_examples():
    raw=c.serialize('erkezesiAdatokBekuldese',request('erkezesiAdatokBekuldese'))
    root=E.fromstring(raw);person=root.find('.//{'+c.NS+'}manualisanRogzitettAdat')
    assert [E.QName(x).localname for x in person]==list(c.FIELDS)
    assert len(person)==12 and sum(x.get('{'+c.XSI+'}nil')=='true' for x in person)==5
    # Official p22 empty enum/date patterns are invalid; the schema stays unchanged.
    for key in ('szuletesiDatum','nem','okmanyTipus'):
        bad=E.fromstring(raw);element=bad.find('.//{'+c.NS+'}'+key);element.attrib.clear();element.text=''
        with pytest.raises(c.ContractError):c.validate(E.tostring(bad),'erkezesiAdatokBekuldese')
    # Official receipt examples omit required hibaSzoveg (pp24/27); reject that shape.
    raw=c.serialize('tavozasiAdatokBekuldese',response('tavozasiAdatokBekuldese'),response=True);root=E.fromstring(raw)
    e=root.find('.//{'+c.NS+'}hibaSzoveg');e.getparent().remove(e)
    with pytest.raises(c.ContractError):c.validate(E.tostring(root),'tavozasiAdatokBekuldese',True)

@pytest.mark.parametrize('raw',[b'<!DOCTYPE x [<!ENTITY e "x">]><x/>',b'<bad/>',b'x'*(8*1024*1024+1),b'<unclosed'],ids=['dtd','namespace','oversize','malformed'])
def test_xml_security(raw):
    with pytest.raises(c.ContractError):c.validate(raw,'allapotLekerdezes')

@pytest.mark.parametrize('value,valid',[('a'*200,True),('a'*201,False),('\u0151'*127,True),('\u0151'*128,False)])
def test_unicode_limits(value,valid):
    errors=c.identity_errors({**P.model_dump(),'csaladnev':value},NOW.date())
    assert ('length:csaladnev' not in errors)==valid

@pytest.mark.parametrize('offset,requires_doc',[(-1,False),(0,True),(1,True)])
def test_under14_at_actual_arrival(offset,requires_doc):
    born=date(2012,11,20);day=date(2026,11,20)+timedelta(days=offset)
    fields={**P.model_dump(),'szuletesiDatum':born,'okmanyTipus':None,'okmanyAzonositoSzam':None}
    assert ('missing:okmanyTipus' in c.identity_errors(fields,day))==requires_doc

def test_rolling_birth_date_and_countries():
    fields=P.model_dump();fields['szuletesiDatum']=date(1916,11,20)
    assert 'birth_date' not in c.identity_errors(fields,NOW.date())
    fields['szuletesiDatum']=date(1916,11,19);assert 'birth_date' in c.identity_errors(fields,NOW.date())
    assert c.country('HUN')=='HU' and c.country('XKA')=='XK' and c.country('BQ')=='BQ'
    for raw in ('NLD','XKX','IF','Unknown'):
        with pytest.raises(c.ContractError):c.country(raw)
    receipt=response('erkezesiAdatokBekuldese');assert receipt.hibaLista[0].codes==('EF0001','EF0033','EF7050')
    with pytest.raises(c.ContractError):c.UnresolvedOuterSecurity().sign(b'x')

def test_conditional_name_pairs_respect_scanned_and_manual_sources():
    fields={**P.model_dump(),'utonev':None,'szuletesiCsaladnev':'Reader-only partial birth name'}
    assert not any(e.startswith(('missing:utonev','name_pair:')) for e in c.source_identity_errors(fields,{},NOW.date()))
    errors=c.source_identity_errors(fields,{'szuletesiCsaladnev':'Reviewed'},NOW.date())
    assert 'manual_name_pair:szuletesiCsaladnev' in errors
